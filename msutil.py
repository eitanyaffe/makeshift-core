#!/usr/bin/env python3
"""msutil: query and fetch from the combined makeshift index."""

import argparse
import csv
import fnmatch
import os
import shlex
import shutil
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


# bump freely on any edit, not critical
VERSION = "v1.01"

INSTANCE_FILE = "all.txt"
CLASS_FILE = "all_class.txt"
SUMMARY_FILE = "index.txt"


def die(msg, code=1):
    sys.stderr.write(f"msutil: {msg}\n")
    sys.exit(code)


def load_table(path):
    if not path.is_file():
        die(f"expected {path.name} in {path.parent}; run from the index dir or pass -i")
    with path.open(newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        return list(reader)


def index_dir(args):
    d = Path(args.index).resolve()
    if not d.is_dir():
        die(f"index dir not found: {d}")
    return d


def match_tags(row_tag, pairs):
    if not pairs:
        return True
    parts = set(row_tag.split(":")) if row_tag else set()
    return all(p in parts for p in pairs)


def emit_tsv(rows, fields):
    out = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
    out.writerow(fields)
    for r in rows:
        out.writerow([r.get(k, "") for k in fields])


def human_size(n):
    try:
        n = float(n)
    except (TypeError, ValueError):
        return "?"
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.2f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024
    return f"{n:.2f} PB"


def basename_ext(path):
    base = os.path.basename(path)
    idx = base.find(".")
    return base[idx:] if idx > 0 else ""


def tag_pairs(tag):
    if not tag:
        return []
    out = []
    for part in tag.split(":"):
        if "=" in part:
            k, v = part.split("=", 1)
            out.append((k, v))
        else:
            out.append(("", part))
    return out


def tag_values(tag):
    return [v for _k, v in tag_pairs(tag)]


def local_path(row, layout):
    """Return local path (relative to -o dir) according to layout."""
    variable = row["variable"]
    tag = row.get("tag", "")
    path = row["path"]
    stem = variable.lower()
    ext = basename_ext(path)
    vals = tag_values(tag)
    if layout == "flat":
        suffix = "_" + "_".join(vals) if vals else ""
        return Path(f"{stem}{suffix}{ext}")
    if layout == "module":
        suffix = "_" + "_".join(vals) if vals else ""
        return Path(row["module"]) / f"{stem}{suffix}{ext}"
    # full: module/key/val[/key2/val2/...]/var.ext
    parts = [row["module"]]
    for k, v in tag_pairs(tag):
        if k:
            parts.append(k.lower())
        parts.append(v)
    parts.append(f"{stem}{ext}")
    return Path(*parts)


def is_glob(s):
    return any(ch in s for ch in "*?[")


GCLOUD_INSTALL_URL = "https://cloud.google.com/sdk/docs/install"


def require_gcloud():
    if shutil.which("gcloud") is None:
        die(f"gcloud not found in PATH; install the Google Cloud SDK: {GCLOUD_INSTALL_URL}")


def filter_variables(rows, variable, module, check_ambiguity=True):
    if is_glob(variable):
        hits = [r for r in rows if fnmatch.fnmatchcase(r["variable"], variable)]
    else:
        hits = [r for r in rows if r["variable"] == variable]
    if module:
        hits = [r for r in hits if r["module"] == module]
    if not hits:
        die(f"no variables match: {variable}" + (f" (module={module})" if module else ""), 1)
    if check_ambiguity and not is_glob(variable):
        mods = sorted({r["module"] for r in hits})
        if len(mods) > 1:
            die(f"variable {variable} is ambiguous across modules: {', '.join(mods)}; pass --module", 2)
    return hits


def diagnose_no_match(variable, pairs, pre_tag_hits):
    """Emit a helpful error when tag filters exclude every row."""
    vname = variable or "*"
    if not pairs:
        die("no rows match", 1)
    lines = [f"no rows match for {vname} with tags {' '.join(pairs)}"]
    present_keys = set()
    for r in pre_tag_hits:
        for kv in (r.get("tag") or "").split(":"):
            if "=" in kv:
                present_keys.add(kv.split("=", 1)[0])
    for p in pairs:
        k, v = p.split("=", 1)
        if k not in present_keys:
            lines.append(f"  tag key {k} not found (known keys: {', '.join(sorted(present_keys)) or 'none'})")
            continue
        vals = sorted({kv.split('=', 1)[1] for r in pre_tag_hits
                       for kv in (r.get('tag') or '').split(':') if kv.startswith(k + '=')})
        if v not in vals:
            sample = vals[:8]
            tail = f" ... ({len(vals)} total)" if len(vals) > 8 else ""
            lines.append(f"  {k}={v} not found; available {k}: {', '.join(sample)}{tail}")
    die("\n".join(lines), 1)


def cmd_ls(args):
    # bare 'msutil ls' prints help
    if not any([args.variable, args.resolve, args.tags, args.all, args.module]):
        args._subparser.print_help()
        sys.exit(0)

    if args.all and args.variable:
        die("-a/--all conflicts with a variable argument; use one or the other", 2)

    # -a is equivalent to glob '*'
    variable = "*" if args.all else args.variable
    pairs = list(args.tags or [])
    # tags imply -r, and broadcast across variables if none given
    if pairs:
        args.resolve = True
        if not variable:
            variable = "*"

    d = index_dir(args)

    if not args.resolve:
        rows = load_table(d / CLASS_FILE)
        if args.module:
            rows = [r for r in rows if r["module"] == args.module]
        if variable:
            if is_glob(variable):
                rows = [r for r in rows if fnmatch.fnmatchcase(r["variable"], variable)]
            else:
                rows = [r for r in rows if r["variable"] == variable]
        if not rows:
            die("no class rows match", 1)
        has_desc = any("description" in r for r in rows)
        fields = ["module", "variable", "tag_keys"]
        if has_desc:
            fields.append("description")
        fields.append("path_template")
        emit_tsv(rows, fields)
        return

    rows = load_table(d / INSTANCE_FILE)
    if variable:
        hits = filter_variables(rows, variable, args.module, check_ambiguity=False)
    elif args.module:
        hits = [r for r in rows if r["module"] == args.module]
    else:
        hits = rows
    if pairs:
        pre = hits
        hits = [r for r in hits if match_tags(r.get("tag", ""), pairs)]
        if not hits:
            diagnose_no_match(variable, pairs, pre)
    if not hits:
        die("no instance rows", 1)
    emit_tsv(hits, ["module", "variable", "tag", "size", "found", "path"])


def cmd_info(args):
    d = index_dir(args)
    inst = load_table(d / INSTANCE_FILE)
    summ = load_table(d / SUMMARY_FILE) if (d / SUMMARY_FILE).is_file() else []

    mods = []
    seen = set()
    for r in summ:
        if r["module"] not in seen:
            mods.append(r["module"])
            seen.add(r["module"])
    for r in inst:
        if r["module"] not in seen:
            mods.append(r["module"])
            seen.add(r["module"])

    out = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
    out.writerow(["module", "n_variables", "n_instances", "n_missing", "total_size"])
    g_vars = g_inst = g_miss = 0
    g_size = 0
    for m in mods:
        sub = [r for r in inst if r["module"] == m]
        variables = {r["variable"] for r in sub}
        found = [r for r in sub if r.get("found", "").upper() == "TRUE"]
        missing = len(sub) - len(found)
        size = 0
        for r in found:
            try:
                size += int(r.get("size") or 0)
            except ValueError:
                pass
        out.writerow([m, len(variables), len(sub), missing, human_size(size)])
        g_vars += len(variables)
        g_inst += len(sub)
        g_miss += missing
        g_size += size
    out.writerow(["TOTAL", g_vars, g_inst, g_miss, human_size(g_size)])


def cmd_get(args):
    if args.all and args.variable:
        die("--all conflicts with a variable argument; use one or the other", 2)
    if not args.variable and not args.all and not args.tags and not args.module:
        args._subparser.print_help()
        sys.exit(0)

    d = index_dir(args)
    rows = load_table(d / INSTANCE_FILE)
    # broadcast across all variables when no explicit variable is given
    broadcast = args.all or (not args.variable and (args.tags or args.module))
    variable = "*" if broadcast else args.variable
    hits = filter_variables(rows, variable, args.module)
    pairs = list(args.tags or [])
    pre_tag_hits = hits
    hits = [r for r in hits if match_tags(r.get("tag", ""), pairs)]
    if not hits:
        diagnose_no_match(variable, pairs, pre_tag_hits)

    if args.quiet:
        args.yes = True

    plan = []
    skipped = 0
    total = 0
    matched_vars = []
    seen_v = set()
    for r in hits:
        if r["variable"] not in seen_v:
            seen_v.add(r["variable"])
            matched_vars.append(r["variable"])
        if r.get("found", "").upper() != "TRUE":
            if not args.quiet:
                sys.stderr.write(f"msutil: skipping {r['variable']} [{r.get('tag','')}] (found=FALSE)\n")
            skipped += 1
            continue
        try:
            sz = int(r.get("size") or 0)
        except ValueError:
            sz = 0
        plan.append((r, sz, local_path(r, args.layout)))
        total += sz

    if not plan:
        die("nothing to download", 1)

    odir = Path(args.output).resolve()
    cp_cmd = ["gcloud", "storage", "cp"]
    if args.quiet:
        cp_cmd += ["--verbosity=error"]

    if args.stdout:
        if len(plan) != 1:
            die(f"--stdout requires exactly 1 file, got {len(plan)}; narrow filters or tags", 2)
        r, _sz, _p = plan[0]
        cat_argv = ["gcloud", "storage", "cat", r["path"]]
        if args.dry:
            cmd = " ".join(shlex.quote(a) for a in cat_argv)
            if args.head:
                cmd += f" | head -n {int(args.head)}"
            sys.stdout.write(cmd + "\n")
            return
        require_gcloud()
        if args.head:
            proc = subprocess.Popen(cat_argv, stdout=subprocess.PIPE)
            try:
                for i, line in enumerate(proc.stdout):
                    if i >= args.head:
                        break
                    sys.stdout.buffer.write(line)
                sys.stdout.flush()
            finally:
                proc.terminate()
                proc.wait()
            sys.exit(0)
        rc = subprocess.call(cat_argv)
        sys.exit(rc)

    # split plan into "already present" (skip) and "to download", unless -f/--force or --head
    # (--head produces truncated files whose size will not match the indexed size)
    present = []
    to_dl = []
    if args.force or args.head:
        to_dl = plan
    else:
        for item in plan:
            r, sz, rel = item
            dst = odir / rel
            if dst.exists() and sz > 0 and dst.stat().st_size == sz:
                present.append(item)
            else:
                to_dl.append(item)
    dl_total = sum(sz for _r, sz, _rel in to_dl)

    if not args.quiet:
        if (args.all or is_glob(args.variable or "")) and len(matched_vars) > 1:
            sys.stderr.write(f"matched {len(matched_vars)} variables: {', '.join(matched_vars)}\n")
        if present and not args.force:
            sys.stderr.write(
                f"files: {len(plan)} ({len(to_dl)} to download, {len(present)} already present)  "
                f"to download: {human_size(dl_total)}  -> {odir} (layout={args.layout})\n")
        else:
            sys.stderr.write(
                f"files: {len(plan)}  total: {human_size(total)}  -> {odir} (layout={args.layout})\n")

    if args.dry:
        if to_dl:
            parents = sorted({str((odir / rel).parent) for _r, _sz, rel in to_dl})
            sys.stdout.write("mkdir -p " + " ".join(shlex.quote(p) for p in parents) + "\n")
            sys.stdout.write(f"# actual run uses a thread pool with {args.jobs} workers\n")
            for r, _sz, rel in to_dl:
                dst = str(odir / rel)
                if args.head:
                    cat = " ".join(shlex.quote(a) for a in ["gcloud", "storage", "cat", r["path"]])
                    sys.stdout.write(f"{cat} | head -n {int(args.head)} > {shlex.quote(dst)}\n")
                else:
                    argv = cp_cmd + [r["path"], dst]
                    sys.stdout.write(" ".join(shlex.quote(a) for a in argv) + "\n")
        else:
            sys.stdout.write("# all files already present locally; nothing to download\n")
        return

    if not to_dl:
        if not args.quiet:
            sys.stderr.write("all files already present; nothing to do (use -f to re-download)\n")
        return

    if not args.yes:
        sys.stderr.write("proceed? [Y/n] ")
        sys.stderr.flush()
        try:
            resp = sys.stdin.readline().strip().lower()
        except (KeyboardInterrupt, EOFError):
            sys.stderr.write("\n")
            die("aborted", 0)
        if resp not in ("", "y", "yes"):
            die("aborted", 0)

    require_gcloud()

    odir.mkdir(parents=True, exist_ok=True)
    # pre-create dst parents up front so worker threads don't race
    for _r, _sz, rel in to_dl:
        (odir / rel).parent.mkdir(parents=True, exist_ok=True)

    jobs = max(1, int(args.jobs))
    if not args.quiet and jobs > 1:
        sys.stderr.write(f"jobs: {jobs}\n")

    # track live Popen objects so ^C can kill them
    live = set()
    live_lock = threading.Lock()
    cancel_flag = threading.Event()

    def worker(item):
        r, _sz, rel = item
        dst = odir / rel
        if cancel_flag.is_set():
            return r, dst, -1
        if args.head:
            proc = subprocess.Popen(
                ["gcloud", "storage", "cat", r["path"]], stdout=subprocess.PIPE)
        else:
            proc = subprocess.Popen(cp_cmd + [r["path"], str(dst)])
        with live_lock:
            live.add(proc)
        try:
            if args.head:
                with open(dst, "wb") as f:
                    for i, line in enumerate(proc.stdout):
                        if i >= args.head:
                            break
                        f.write(line)
                proc.terminate()
                rc = proc.wait()
                # early termination via SIGTERM is expected, not a failure
                if rc in (-15, 143):
                    rc = 0
            else:
                rc = proc.wait()
        finally:
            with live_lock:
                live.discard(proc)
        return r, dst, rc

    failed = 0
    completed = 0
    n_dl = len(to_dl)
    interrupted = False
    ex = ThreadPoolExecutor(max_workers=jobs)
    try:
        futs = {ex.submit(worker, item): item for item in to_dl}
        try:
            for fut in as_completed(futs):
                r, dst, rc = fut.result()
                completed += 1
                if rc == -1:
                    continue
                if not args.quiet:
                    sys.stderr.write(f"[{completed}/{n_dl}] {r['path']} -> {dst}\n")
                if rc != 0:
                    sys.stderr.write(f"msutil: gcloud storage cp failed ({rc}) for {r['path']}\n")
                    failed += 1
        except KeyboardInterrupt:
            interrupted = True
            cancel_flag.set()
            sys.stderr.write("\nmsutil: interrupted, cancelling...\n")
            for f in futs:
                f.cancel()
            with live_lock:
                procs = list(live)
            for p in procs:
                try:
                    p.terminate()
                except Exception:
                    pass
    finally:
        ex.shutdown(wait=True, cancel_futures=True)

    if interrupted:
        die("aborted by user", 130)
    if failed:
        die(f"{failed}/{n_dl} downloads failed", 1)
    if skipped and not args.quiet:
        sys.stderr.write(f"note: skipped {skipped} missing file(s)\n")


def cmd_cat(args):
    if not args.variable and not args.tags and not args.module:
        args._subparser.print_help()
        sys.exit(0)

    d = index_dir(args)
    rows = load_table(d / INSTANCE_FILE)
    broadcast = not args.variable and (args.tags or args.module)
    variable = "*" if broadcast else args.variable
    hits = filter_variables(rows, variable, args.module)
    pairs = list(args.tags or [])
    pre_tag_hits = hits
    hits = [r for r in hits if match_tags(r.get("tag", ""), pairs)]
    if not hits:
        diagnose_no_match(variable, pairs, pre_tag_hits)
    hits = [r for r in hits if r.get("found", "").upper() == "TRUE"]
    if not hits:
        die("matched rows are all found=FALSE; nothing to cat", 1)
    if len(hits) != 1:
        examples = "\n  ".join(f"{r['variable']} [{r.get('tag','')}]" for r in hits[:5])
        more = "" if len(hits) <= 5 else f"\n  ... ({len(hits)-5} more)"
        die(f"cat requires exactly 1 matching file, got {len(hits)}. "
            f"narrow with more tags or --module. matches:\n  {examples}{more}", 2)

    r = hits[0]
    cat_argv = ["gcloud", "storage", "cat", r["path"]]
    if args.dry:
        cmd = " ".join(shlex.quote(a) for a in cat_argv)
        if args.head:
            cmd += f" | head -n {int(args.head)}"
        sys.stdout.write(cmd + "\n")
        return
    require_gcloud()
    if args.head:
        proc = subprocess.Popen(cat_argv, stdout=subprocess.PIPE)
        try:
            for i, line in enumerate(proc.stdout):
                if i >= args.head:
                    break
                sys.stdout.buffer.write(line)
            sys.stdout.flush()
        finally:
            proc.terminate()
            proc.wait()
        return
    rc = subprocess.call(cat_argv)
    sys.exit(rc)


def add_index_flag(sp):
    sp.add_argument("-i", "--index", default=".", help="index directory (default: current dir)")


def build_parser():
    p = argparse.ArgumentParser(
        prog="msutil",
        description="query and fetch from the combined makeshift index (produced by utils/index).",
        epilog="run 'msutil <command> -h' for details on a specific command.",
    )
    p.add_argument("-V", "--version", action="version", version=f"msutil {VERSION}")
    sub = p.add_subparsers(dest="cmd")

    ls = sub.add_parser(
        "ls",
        help="list class variables or resolved instances",
        description="list class variables (default) or resolve to concrete instances with -r. "
                    "tag filters (-t) require a single variable and imply -r.",
        epilog="examples:\n"
               "  msutil ls -a                                        # all class variables\n"
               "  msutil ls 'ASSEMBLY_*'                              # class rows, filtered by glob\n"
               "  msutil ls ASSEMBLY_CONTIG_TABLE                     # class row for one variable\n"
               "  msutil ls --module long                             # class rows within one module\n"
               "  msutil ls -r                                        # every instance row in the index\n"
               "  msutil ls ASSEMBLY_ID=BAA                           # every instance with this tag (tag implies -r)\n"
               "  msutil ls ASSEMBLY_CONTIG_TABLE ASSEMBLY_ID=BAA     # instances of one variable, filtered\n"
               "  msutil ls CONTACT_MATRIX HIC_ID=H1 ASSEMBLY_ID=BAA",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ls.add_argument("variable", nargs="?",
                    help="variable name or glob (quote to protect from shell expansion)")
    ls.add_argument("tags", nargs="*", help="zero or more KEY=VAL tag filters (imply -r)")
    ls.add_argument("-a", "--all", action="store_true",
                    help="match every variable (equivalent to a quoted '*' without shell-expansion risk)")
    ls.add_argument("-r", "--resolve", action="store_true",
                    help="resolve to instance rows (path, size, found) instead of class rows")
    ls.add_argument("--module", help="scope to a single module")
    add_index_flag(ls)
    ls.set_defaults(func=cmd_ls, _subparser=ls)

    g = sub.add_parser(
        "get",
        help="download instance(s) of a variable (supports * ? globs)",
        description="download instance(s) of a variable. the variable may be a glob "
                    "(*, ?, [...]); always quote it so the shell does not expand it first.",
        epilog="examples:\n"
               "  msutil get ASSEMBLY_CONTIG_TABLE ASSEMBLY_ID=BAA\n"
               "  msutil get 'ASSEMBLY_*'                    # all variables starting with ASSEMBLY_\n"
               "  msutil get ASSEMBLY_ID=BAA                 # every variable with this tag\n"
               "  msutil get -a ASSEMBLY_ID=BAA              # every variable for assembly BAA\n"
               "  msutil get '*_FILE' ASSEMBLY_ID=BAA        # every *_FILE for assembly BAA\n"
               "  msutil get ASSEMBLY_CONTIG_TABLE ASSEMBLY_ID=BAA -c | head",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    g.add_argument("variable", nargs="?",
                   help="variable name or glob, e.g. ASSEMBLY_CONTIG_TABLE or 'ASSEMBLY_*' "
                        "(quote to protect from shell expansion); omit to show this help")
    g.add_argument("tags", nargs="*", help="zero or more KEY=VAL tag filters")
    g.add_argument("-a", "--all", action="store_true",
                   help="match every variable (equivalent to a quoted '*' without shell-expansion risk)")
    g.add_argument("-o", "--output", default=".", help="output directory (default: .)")
    g.add_argument("--layout", choices=["full", "module", "flat"], default="full",
                   help="output layout: full=module/key/val/var.ext (default), "
                        "module=module/var_val.ext, flat=var_val.ext")
    g.add_argument("-c", "--stdout", action="store_true",
                   help="stream content to stdout (requires exactly 1 matching file)")
    g.add_argument("-y", "--yes", action="store_true", help="skip confirmation prompt")
    g.add_argument("-q", "--quiet", action="store_true",
                   help="suppress progress and summary output (implies -y)")
    g.add_argument("-j", "--jobs", type=int, default=8,
                   help="parallel downloads (default: 8)")
    g.add_argument("-f", "--force", action="store_true",
                   help="re-download files that already exist locally "
                        "(default: skip if local size matches indexed size)")
    g.add_argument("--head", type=int, metavar="N",
                   help="download only the first N lines of each file "
                        "(streams gcloud cat | head; disables resume-skip)")
    g.add_argument("-dry", action="store_true", help="list the plan without downloading")
    g.add_argument("--module", help="disambiguate by module if the variable is ambiguous")
    add_index_flag(g)
    g.set_defaults(func=cmd_get, _subparser=g)

    c = sub.add_parser(
        "cat",
        help="stream a single file to stdout (must resolve to exactly 1 match)",
        description="stream the contents of a single indexed file to stdout. "
                    "filters must resolve to exactly one row.",
        epilog="examples:\n"
               "  msutil cat ASSEMBLY_CONTIG_TABLE ASSEMBLY_ID=BAA\n"
               "  msutil cat ASSEMBLY_CONTIG_TABLE ASSEMBLY_ID=BAA --head 5\n"
               "  msutil cat CONTACT_MATRIX HIC_ID=H1 ASSEMBLY_ID=BAA | less",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    c.add_argument("variable", nargs="?",
                   help="variable name (globs are allowed but the match must still be unique)")
    c.add_argument("tags", nargs="*", help="zero or more KEY=VAL tag filters")
    c.add_argument("--head", type=int, metavar="N",
                   help="stream only the first N lines")
    c.add_argument("--module", help="scope to a single module")
    c.add_argument("-dry", action="store_true",
                   help="print the gcloud storage cat command instead of running it")
    add_index_flag(c)
    c.set_defaults(func=cmd_cat, _subparser=c)

    i = sub.add_parser("info", help="full index summary (per module + totals)")
    add_index_flag(i)
    i.set_defaults(func=cmd_info)

    return p


def main():
    parser = build_parser()
    if len(sys.argv) == 1:
        sys.stdout.write(f"msutil {VERSION}\n\n")
        parser.print_help()
        sys.exit(0)
    args = parser.parse_args()
    if not getattr(args, "func", None):
        parser.print_help()
        sys.exit(0)
    # reposition 'KEY=VAL' typed as variable (happens when no variable + tag was given first)
    if getattr(args, "variable", None) and "=" in args.variable:
        args.tags = [args.variable] + list(getattr(args, "tags", []) or [])
        args.variable = None
    # positional tag sanity-check
    bad = [t for t in getattr(args, "tags", []) if "=" not in t]
    if bad:
        hint = ""
        cmd = getattr(args, "cmd", "")
        if cmd in ("get", "ls", "cat") and getattr(args, "variable", ""):
            looks_expanded = ("." in args.variable or "/" in args.variable) and all("=" not in t for t in args.tags)
            if looks_expanded:
                hint = f"  (did you forget to quote a glob? e.g. msutil {cmd} '*' or \"ASSEMBLY_*\")"
        die(f"tag filter must be KEY=VAL: {bad[0]}{hint}")
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.stderr.write("\nmsutil: interrupted\n")
        sys.exit(130)

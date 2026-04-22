#!/usr/bin/env python3
"""
nf_validate -- compare Makeshift dry-run commands with Nextflow run scripts.

Reads a Makeshift plan output (make plan t=<target> PAR_TYPE=local) and a
Nextflow log output (nextflow log <run> -f 'name,tag,script'), normalizes
both to step signatures, and writes a comparison report.

Typically invoked by `make validate t=<target> nf_run=<run>` from makeshift.mk.

Usage:
    python3 scripts/nf_validate.py --ms <ms_plan.txt> --nf <nf_log.txt> [--out <report.txt>]
"""

import argparse
import os
import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# normalization helpers
# ---------------------------------------------------------------------------

def script_basename(path):
    """Extract script filename without directory prefix."""
    return os.path.basename(path)


def normalize_command(cmd):
    """
    Extract a canonical step signature from a shell command line.
    Returns (tool, script, function) or None if not a recognized invocation.

    Recognized patterns:
      R_call.r <script.r> <function> [params...]
      R_call_nf.r <script.r> <function> [params...]   (treated as R_call.r)
      Rscript <script.r> [args...]
      perl <script.pl> [args...]
      python3 <script.py> [args...]
      python <script.py> [args...]
      echo "<cmd>"   (stub mode: extract the echoed command recursively)
    """
    cmd = cmd.strip()
    if not cmd or cmd.startswith('#') or cmd.startswith('mkdir') or \
       cmd.startswith('touch') or cmd.startswith('if ') or \
       cmd.startswith('fi') or cmd.startswith('then') or \
       cmd.startswith('else') or cmd.startswith('&&') or \
       cmd.startswith('||') or cmd.startswith('cd ') or cmd == '\\':
        return None

    # stub mode: echo "<real command>" -- recurse on the echoed content
    if cmd.startswith('echo '):
        inner = cmd[5:].strip()
        # strip surrounding quotes
        if (inner.startswith('"') and inner.endswith('"')) or \
           (inner.startswith("'") and inner.endswith("'")):
            inner = inner[1:-1]
        return normalize_command(inner) if inner else None

    tokens = cmd.split()
    if not tokens:
        return None

    tool = script_basename(tokens[0])

    # R_call.r / R_call_nf.r: normalize both to R_call.r
    if tool in ('R_call.r', 'R_call_nf.r') and len(tokens) >= 3:
        script = script_basename(tokens[1])
        func   = tokens[2]
        return ('R_call', script, func)

    if tool == 'Rscript' and len(tokens) >= 2:
        script = script_basename(tokens[1])
        return ('Rscript', script, '')

    if tool == 'perl' and len(tokens) >= 2:
        script = script_basename(tokens[1])
        return ('perl', script, '')

    if tool in ('python3', 'python') and len(tokens) >= 2:
        script = script_basename(tokens[1])
        return ('python', script, '')

    # shell tool or binary (awk, gsutil, binary, etc.)
    return ('shell', tool, '')


def sig_str(sig):
    tool, script, func = sig
    if func:
        return f"{tool}  {script}  {func}"
    return f"{tool}  {script}"


# ---------------------------------------------------------------------------
# MS plan parser
# ---------------------------------------------------------------------------

def parse_ms_plan(text):
    """
    Parse `make plan t=<t> PAR_TYPE=local` output.
    Returns list of dicts: {target, commands: [sig, ...]}
    """
    steps = []
    current_target = None
    current_cmds   = []

    step_sep = re.compile(r'^---[><]{2,}')

    for line in text.splitlines():
        line = line.rstrip()

        if step_sep.match(line):
            continue

        if line.startswith('START:'):
            if current_target is not None:
                steps.append({'target': current_target, 'sigs': current_cmds})
            # target name: strip 'START: ' prefix, keep basename of .done path
            target_path = line[len('START:'):].strip()
            # use basename without extension as human label
            current_target = Path(target_path).stem or target_path
            current_cmds   = []
            continue

        if line.startswith('END'):
            if current_target is not None:
                steps.append({'target': current_target, 'sigs': current_cmds})
            current_target = None
            current_cmds   = []
            continue

        if current_target is not None:
            sig = normalize_command(line)
            if sig:
                current_cmds.append(sig)

    if current_target is not None:
        steps.append({'target': current_target, 'sigs': current_cmds})

    return steps


# ---------------------------------------------------------------------------
# NF log parser
# ---------------------------------------------------------------------------

def parse_nf_log(text):
    """
    Parse `nextflow log <run> -f 'name,tag,script'` output.
    Returns list of dicts: {process, tag, sigs: [sig, ...]}
    Each line may be: name<TAB>tag<TAB>script (script may contain newlines
    represented as literal \\n in the log).
    """
    tasks = []
    for line in text.splitlines():
        line = line.rstrip()
        if not line:
            continue
        parts = line.split('\t', 2)
        if len(parts) < 3:
            continue
        name, tag, script = parts

        sigs = []
        # script may have literal \n sequences
        for cmd in script.replace('\\n', '\n').splitlines():
            sig = normalize_command(cmd)
            if sig:
                sigs.append(sig)

        tasks.append({'process': name, 'tag': tag, 'sigs': sigs})

    return tasks


# ---------------------------------------------------------------------------
# deduplication
# ---------------------------------------------------------------------------

def dedup_steps(steps):
    """Deduplicate MS steps by their command signature set."""
    seen = {}
    result = []
    for s in steps:
        key = (s['target'], tuple(s['sigs']))
        if key not in seen:
            seen[key] = True
            result.append(s)
    return result


def dedup_tasks(tasks):
    """Deduplicate NF tasks by process name (ignore per-sample repetition)."""
    seen = {}
    result = []
    for t in tasks:
        # key on process name + frozenset of sigs (order may vary across samples)
        key = (t['process'], frozenset(t['sigs']))
        if key not in seen:
            seen[key] = True
            result.append(t)
    return result


# ---------------------------------------------------------------------------
# comparison
# ---------------------------------------------------------------------------

def match_steps(ms_steps, nf_tasks):
    """
    Match MS steps to NF tasks by overlapping command signatures.
    Returns (matched, ms_unmatched, nf_unmatched).
    """
    matched      = []
    ms_unmatched = []
    nf_used      = set()

    for ms in ms_steps:
        ms_set = set(ms['sigs'])
        if not ms_set:
            continue
        best_task  = None
        best_score = 0
        for i, nf in enumerate(nf_tasks):
            if i in nf_used:
                continue
            nf_set    = set(nf['sigs'])
            intersect = ms_set & nf_set
            if intersect and len(intersect) > best_score:
                best_score = len(intersect)
                best_task  = i
        if best_task is not None:
            nf_used.add(best_task)
            matched.append((ms, nf_tasks[best_task]))
        else:
            ms_unmatched.append(ms)

    nf_unmatched = [nf_tasks[i] for i in range(len(nf_tasks)) if i not in nf_used]
    return matched, ms_unmatched, nf_unmatched


# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------

def write_report(matched, ms_unmatched, nf_unmatched, out_file):
    lines = []

    def h(s):
        lines.append(s)

    total_ms = len(matched) + len(ms_unmatched)
    total_nf = len(matched) + len(nf_unmatched)

    h("=" * 70)
    h("NF VALIDATION REPORT")
    h("=" * 70)
    h(f"MS steps:  {total_ms}   NF processes:  {total_nf}")
    h(f"Matched:   {len(matched)}/{total_ms}")
    h("")

    # matched
    h(f"MATCHED ({len(matched)}):")
    h("-" * 70)
    for ms, nf in matched:
        ms_set = set(ms['sigs'])
        nf_set = set(nf['sigs'])
        same   = ms_set == nf_set
        status = "OK" if same else "DIFF"
        h(f"  [{status}]  MS: {ms['target']}  <->  NF: {nf['process']}")
        if not same:
            only_ms = ms_set - nf_set
            only_nf = nf_set - ms_set
            for sig in sorted(only_ms):
                h(f"         MS only:  {sig_str(sig)}")
            for sig in sorted(only_nf):
                h(f"         NF only:  {sig_str(sig)}")
    h("")

    # unmatched MS
    if ms_unmatched:
        h(f"UNMATCHED MS steps ({len(ms_unmatched)}) -- not yet converted to NF:")
        h("-" * 70)
        for ms in ms_unmatched:
            h(f"  {ms['target']}")
            for sig in ms['sigs']:
                h(f"    {sig_str(sig)}")
        h("")

    # unmatched NF
    if nf_unmatched:
        h(f"UNMATCHED NF processes ({len(nf_unmatched)}) -- extra vs MS:")
        h("-" * 70)
        for nf in nf_unmatched:
            h(f"  {nf['process']}")
            for sig in nf['sigs']:
                h(f"    {sig_str(sig)}")
        h("")

    # summary
    h("=" * 70)
    ok      = sum(1 for ms, nf in matched if set(ms['sigs']) == set(nf['sigs']))
    differs = len(matched) - ok
    h(f"SUMMARY:  {ok} exact  |  {differs} differ  |  "
      f"{len(ms_unmatched)} MS-only  |  {len(nf_unmatched)} NF-only")
    h("=" * 70)

    report = "\n".join(lines)
    if out_file:
        Path(out_file).parent.mkdir(parents=True, exist_ok=True)
        Path(out_file).write_text(report)
    print(report)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="compare makeshift dry-run commands with nextflow run scripts"
    )
    parser.add_argument("--ms",  required=True, help="makeshift plan output file")
    parser.add_argument("--nf",  required=True, help="nextflow log output file")
    parser.add_argument("--out", default="/tmp/nf_validate/report.txt",
                        help="output report file (default: /tmp/nf_validate/report.txt)")
    args = parser.parse_args()

    ms_text = Path(args.ms).read_text()
    nf_text = Path(args.nf).read_text()

    ms_steps = dedup_steps(parse_ms_plan(ms_text))
    nf_tasks = dedup_tasks(parse_nf_log(nf_text))

    matched, ms_unmatched, nf_unmatched = match_steps(ms_steps, nf_tasks)

    write_report(matched, ms_unmatched, nf_unmatched, args.out)


if __name__ == "__main__":
    main()

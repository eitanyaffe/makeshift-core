options(stringsAsFactors=F)

exec=function(command, verbose=T, ignore.error=F)
{
    if (verbose)
        cat(sprintf("running command: %s\n", command))
    rc = system(command)
    if (!ignore.error && rc != 0)
        stop(sprintf("error in command: %s", command))
    rc
}

send.email=function(sendgrid.key, from.email, to.email, subject, message, attachments=NULL)
{
    if (from.email == "none" || to.email == "none")
        return (NULL)
    script = paste0(Sys.getenv("MAKESHIFT_ROOT"), "/makeshift-core/send_email.py")
    command = sprintf("python3 %s -k %s -f %s -t %s -s '%s' -m '%s'", script, sendgrid.key, from.email, to.email, subject, message)
    if (!is.null(attachments))
        command = paste(command, paste("-a", attachments, collapse=" "))
    cat(sprintf("sending email update to %s\n", to.email))
    exec(command, verbose=F, ignore.error=T)
}    

save.lines=function(odir, ofn, lines)
{
    system(paste("mkdir -p", odir))
    cat(sprintf("generating file: %s\n", ofn))
    fc = file(ofn)
    writeLines(lines, fc)
    close(fc)
}

lookup=function(table, lookup.table, lookup.field, value.field, na.value=NA)
{
    mx = match(table[,lookup.field], lookup.table[,lookup.field])
    ifelse(!is.na(mx), lookup.table[mx,value.field], na.value)
}

lookup2=function(table, lookup.table, lookup.field1, lookup.field2, value.field, na.value=NA)
{
    mx = match(table[,lookup.field1], lookup.table[,lookup.field2])
    ifelse(!is.na(mx), lookup.table[mx,value.field], na.value)
}

# anchor name lookup
make.anchor.id=function(anchor, table)
{
    table$id[match(anchor,table$set)]
}
make.anchor=function(anchor.id, table)
{
    table$set[match(anchor.id,table$id)]
}


lookup.append=function(table, lookup.table, lookup.field, value.field, omit.na=T)
{
    table[,value.field] = lookup(table=table, lookup.table=lookup.table, lookup.field=lookup.field, value.field=value.field)
    if (omit.na)
        table = table[!is.na(table[,value.field]),]
    table
}

lookup.append2=function(table, lookup.table, lookup.field1, lookup.field2, value.field, omit.na=T)
{
    table[,value.field] = lookup2(table=table, lookup.table=lookup.table,
             lookup.field1=lookup.field1, lookup.field2=lookup.field2, value.field=value.field)
    if (omit.na)
        table = table[!is.na(table[,value.field]),]
    table
}

expand.range=function(x, factor)
{
    r = range(x)
    d = diff(r)
    c(r[1] - factor*d, r[2] + factor*d)
}

smatrix2matrix=function(smatrix, dim, i.field="i", j.field="j", value.field="value", default.value=0)
{
  indices = smatrix[,i.field] + (smatrix[,j.field]-1) * dim[1]
  v = rep(default.value, dim[1]*dim[2])
  v[indices] = smatrix[,value.field]
  matrix(v, dim[1], dim[2])
}

matrix2smatrix=function(matrix)
{
  dim1 = dim(matrix)[1]
  dim2 = dim(matrix)[2]
  v = as.vector(matrix)
  indices = 1:(dim1*dim2)
  i = (indices-1) %% dim1 + 1
  j = floor((indices-1) / dim1) + 1
  data.frame(i=i, j=j, value=v, stringsAsFactors=F)
}

make.color.panel=function(colors, ncols=256)
{
    library(gplots)
    panel = NULL
    for (i in 2:length(colors))
        panel = c(panel, colorpanel(ncols, colors[i-1], colors[i]))
    panel
}

# the image function needs breaks
make.image.colors=function(colors, breaks, ncols=256) {
    rcolors = NULL
    rbreaks = breaks[1]
    for (i in 2:length(colors)) {
        rcolors = c(rcolors, colorpanel(ncols, colors[i-1], colors[i])[-1])
        rbreaks = c(rbreaks, seq(from=breaks[i-1], to=breaks[i], length.out=ncols)[-1])
    }
    list(col=rcolors, breaks=rbreaks)
}

# for example vals.to.cols(1:10, c(1, 3, 10), ncols=10) returns:
# [1] 1  6 11 12 14 15 16 17 19 20
vals.to.cols=function(vals, breaks, ncols=256)
{
  min = breaks[1]
  max = breaks[length(breaks)]
  vals = ifelse(vals < min, min, ifelse(vals>max, max, vals))
  n = length(breaks)-1
  cols = rep(-1, length(vals))
  for (i in 1:n)
  {
    ind = (breaks[i] <= vals) & (vals <= breaks[i+1])
    if (!any(ind))
      next
    # normalize to [0,1]
    cols[ind] = (vals[ind] - breaks[i]) / (breaks[i+1] - breaks[i])
    # normalize to [i*ncols,i*(ncols+1)]
    cols[ind] = (i-1)*ncols + cols[ind]*(ncols-1) + 1
    # round
    cols[ind] = floor(cols[ind])
  }
  return (cols)
}

field.count=function(x, field="gene")
{
    tt = table(x[,field])
    result = data.frame(x=names(tt), count=as.vector(tt))
    names(result)[1] = field
    result[order(result$count, decreasing=T),]
}

add.field.count=function(x, field, title=paste(field, "count", sep="_"))
{
    df = field.count(x, field)
    x[,title] = df$count[match(x[,field], df[,field])]
    x
}

split.size=function(x, split.by.field) {
    s = sapply(split(x[,1], x[,split.by.field]), length)
    df = data.frame(x=names(s), count=s)
    names(df)[1] = split.by.field
    df
}

################################################################################################
# plot heatmap
################################################################################################

# heatmap for sparse matrix
wheat=function(sm, field.x=1, field.y=2, field.value=3, main="", mai=c(1, 1, 0, 0),
    plot.only.to.screen=F, fdir, ofn.prefix, width=4, height=4,
    plot.names=F, add.box=F,
    plot.legend=T, legend.horiz=F, labels=NULL, add.lines=NULL,
    colors=NULL, breaks=NULL,             # continious
    colors.force=NULL, values.force=NULL, # discrete
    add.text=F, title="legend")
{
    library(gplots)
    vals = sm[,field.value]

    if (is.null(colors))
        colors = topo.colors(5)
    M = length(colors)
    if (is.null(breaks))
        breaks = quantile(vals, 0:(M-1)/(M-1))

    names = sort(unique(c(sm[,field.x], sm[,field.y])))
    N = length(names)
    if (is.null(labels))
        labels = names

    # coords
    x = match(sm[,field.x], names)
    y = match(sm[,field.y], names)
    lim = c(0, N)

    # colors
    ncols = 256
    if (length(colors) != length(breaks))
        stop(sprintf("colors and breaks must be same length"))
    panel = NULL
    for (i in 2:length(colors))
        panel = c(panel, colorpanel(ncols, colors[i-1], colors[i]))
    sm$cc = panel[vals.to.cols(vals=vals, breaks=breaks, ncols=ncols)]

    if (!is.null(colors.force)) {
        ix = match(vals, values.force)
        sm$cc = ifelse(is.na(ix), sm$cc, colors.force[ix])
    }

    # heatmap
    if (!plot.only.to.screen) fig.start(ofn=paste(ofn.prefix, "_matrix.pdf", sep=""), type="pdf",
                                        fdir=fdir, width=width, height=height)
    par(mai=mai)
    plot.new()
    plot.window(xlim=lim, ylim=lim)
    title(main=main)
    rect(x-1,y-1,x,y,border=NA,col=sm$cc)
    if (!is.null(add.lines)) {
        abline(v=add.lines, lwd=1)
        abline(h=add.lines, lwd=1)
    }

    if (add.box)
        box()
    if (plot.names) {
        axis(1, at=1:N - 0.5, labels=labels, las=2)
        axis(2, at=1:N - 0.5, labels=labels, las=2)
    }
    if (add.text) {
        text(x-0.5,y-0.5,round(vals,2), cex=0.75)
    }

    if (!plot.only.to.screen) fig.end()

    if (plot.only.to.screen || !plot.legend)
        return ()

    # legend
    LN = length(panel)
    if (legend.horiz) {
        height = 200
        width = 200+LN/4
        mai.bottom = 2
        mai.left = 0
        xlim = c(0,LN)
        ylim = c(0,1)
        rect.x0 = 0:(LN-1)
        rect.x1 = 1:LN
        rect.y0 = 0
        rect.y1 = 1
        axis.side = 1
    } else {
        width = 200
        height = 200+LN/4
        mai.left = 2
        mai.bottom = 0
        ylim = c(0,LN)
        xlim = c(0,1)
        rect.y0 = 0:(LN-1)
        rect.y1 = 1:LN
        rect.x0 = 0
        rect.x1 = 1
        axis.side = 2
    }
    wlegend2(fdir=fdir, panel=panel, breaks=breaks, title=title)

    fig.start(fdir=fdir, height=4, width=4, ofn=paste(ofn.prefix, "_legend_density.pdf", sep=""), type="pdf")
    par(mai=c(1, 1, 1, 0.4))
    dd = density(vals)
    plot.new()
    plot.window(xlim=range(dd$x), ylim=range(dd$y))
    box()
    grid()
    abline(v=breaks, lty=2)
    abline(h=0)
    lines(dd, lwd=2)
    axis(side=3, labels=round(breaks,1), at=breaks, las=2)
    axis(1)
    fig.end()
}

################################################################################################
# figures
################################################################################################

plot.empty=function(title, cex=1)
{
    plot.new()
    plot.window(xlim=0:1, ylim=0:1)
    text(0.5, 0.5, title, cex=cex)
}

plot.init=function(xlim, ylim, log="",
    main="", xlab="", ylab="",
    add.box=T, x.axis=T, y.axis=T, axis.las=0,
    add.grid=T, grid.nx=NULL, grid.ny=NULL, grid.lty="dotted", xaxs="r", yaxs="r")
{
    plot.new()
    plot.window(xlim=xlim, ylim=ylim, log=log, xaxs=xaxs, yaxs=yaxs)
    title(main=main, xlab=xlab, ylab=ylab)
    if (x.axis) axis(1, las=axis.las)
    if (y.axis) axis(2, las=axis.las)
    if (add.box) box()
    if (add.grid) grid(nx=grid.nx, ny=grid.ny, lty=grid.lty)

}

fig.dir=function(dir, verbose=T)
{
    if (verbose) cat(sprintf("figure dir: %s\n", dir))
    if (!file.exists(dir)) {
        command = paste("mkdir -p", dir)
        if (system(command) != 0)
            stop(sprintf("failed command: %s\n"))
    }
}

fig.start=function(ofn, type="png", fdir=NA, verbose=T, width=400, height=400, ...)
{
    if (!is.na(fdir))
        fig.dir(fdir, verbose=verbose)

    if (verbose) cat(sprintf("creating figure: %s\n", ofn))
    switch(type,
           png = png(ofn, width=width, height=height, ...),
           pdf = pdf(ofn, width=width, height=height, ...)
           )
}

fig.end=function()
{
    dev.off()
}

wbarplot=function(m, main, fdir, ofn, beside, normalize.columns=F, cols, names, ylab, make.file=T)
{
    if (beside)
        width = 200 + dim(m)[1] * (5 + 10*dim(m)[2])
    else
        width = 200 + dim(m)[2] * 10

    if (make.file) fig.start(fdir=fdir, width=width, height=400, ofn=ofn)
    par(mai=c(2,1.5,1,0.5))
    if (normalize.columns)
        m = 100 * t(t(m) / colSums(m))

    ff = if (normalize.columns) 1 else 1.2
    if (beside)
        ylim = c(0, ff * max(m))
    else
        ylim = c(0, ff * max(colSums(m)))

    barplot(as.matrix(m), beside=beside, border=NA, main=main, names.arg=names, las=2, col=cols, ylab=ylab, ylim=ylim)
    if (make.file) fig.end()
}

# discrete
wlegend=function(fdir, names, cols, title="general", ofn.prefix=title, width=6, make.file=T, border=NA, verbose=T)
{
    N = length(names)
    if (make.file) fig.start(fdir=fdir, width=width, height=2 + N*0.4, ofn=paste(fdir, "/", ofn.prefix, "_legend.pdf", sep=""), type="pdf", verbose=verbose)
    par(mai=c(0,0,1,0))
    plot.new()
    title(main=title)
    legend("top", fill=cols, legend=names, border=border)
    if (make.file) fig.end()
}

# continous
wlegend2=function(fdir, panel, breaks, title="general", size=1, height, width, make.file=T, tick.size=0.3, border=NA, lwd=2)
{
    N = length(panel)
    step = 1/N
    coords = (1:N)/N
    coords.breaks = (vals.to.cols(breaks, breaks))/N - step/2

    for (orient in c("v", "h")) {
        long = size + 1 + length(breaks)*0.1
        short = size
        if (orient == "h") {
            mai = c(0.4,0.2,0.3,0.5)
            width = long
            height = short
        } else {
            mai = c(0.3,0.1,0.3,0.5)
            width = short
            height = long
        }

        if (make.file) fig.start(fdir=fdir, width=width, height=height, type="pdf", ofn=paste(fdir, "/", title, "_legend_", orient, ".pdf", sep=""))

        par(xpd=NA)
        par(mai=mai)

        if (orient == "h") {
            plot.init(xlim=c(0,1), ylim=c(-4*tick.size,1), add.box=F, add.grid=F, x.axis=F, y.axis=F)
            rect(xleft=coords-step, xright=coords, ybottom=0, ytop=1, col=panel, border=panel)
            rect(xleft=0, xright=1, ybottom=0, ytop=1, col=NA, border=border, lwd=1)
            segments(x0=coords.breaks, x1=coords.breaks, y0=-tick.size, y1=0, col=1, lwd=lwd)
            text(x=coords.breaks, y=-tick.size, labels=breaks, pos=1, cex=1)
        } else {
            plot.init(ylim=c(0,1), xlim=c(0,1+4*tick.size), add.box=F, add.grid=F, x.axis=F, y.axis=F)
            rect(ybottom=coords-step, ytop=coords, xleft=0, xright=1, col=panel, border=panel)
            rect(ybottom=0, ytop=1, xleft=0, xright=1, col=NA, border=border, lwd=lwd)
            segments(y0=coords.breaks, y1=coords.breaks, x0=1, x1=1+tick.size, col=1, lwd=lwd)
            text(y=coords.breaks, x=1+tick.size, labels=breaks, pos=4, cex=1)
        }

        title(main=title, cex.main=0.7)

        if (make.file) fig.end()
    }
}

################################################################################################
# tables
################################################################################################

save.table=function(x, ofn, verbose=T)
{
    if (verbose) cat(sprintf("saving table: %s\n", ofn))
    write.table(x, ofn, quote=F, row.names=F, sep="\t")
}

load.table=function(ifn, assert.exists=T, verbose=T, ...)
{
    if (verbose) cat(sprintf("reading table: %s\n", ifn))
    if (!assert.exists && !file.exists(ifn))
        return (NULL)
    read.delim(ifn, ...)
}

source(paste0(Sys.getenv("MAKESHIFT_ROOT"), "/makeshift-core/combo_matrix.r"))

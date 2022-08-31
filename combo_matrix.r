################################################################################################
# parameter function
################################################################################################

combo.matrix.plot.params=function(create.pdf=T,
                                  field.x="xid", field.y="yid",
                                  title.x="X", title.y="Y",
                                  field.matrix="value",
                                  color.f.mm=NULL,
                                  plot.legend=T,
                                  cell.size=0.3, panel.gap=0.08, margin.gap=0.5,
                                  cex.text=1, add.text=F)
{
    list(create.pdf=create.pdf,
         field.x=field.x, field.y=field.y,
         title.x=title.x, title.y=title.y,
         field.matrix=field.matrix,
         color.f.mm=color.f.mm,
         plot.legend=plot.legend,
         cex.text=cex.text, add.text=add.text,
         cell.size=cell.size, panel.gap=panel.gap, margin.gap=margin.gap)
}

################################################################################################
# utility functions
################################################################################################

combo.matrix.plot.color=function(ll, values)
{
    breaks = ll$breaks
    colors = ll$colors
    if (ll$type == "smooth") {
        panel = make.color.panel(colors=colors)
        rr = panel[vals.to.cols(values, breaks=breaks)]
        if (is.element("na.value", names(ll)))
            rr = ifelse(values == ll$na.value, ll$na.color, rr)
        return (rr)
    } else {
        ix = match(values, breaks)
        if (any(is.na(ix)))
            stop("not all values defined in discrete coloring scheme")
        return (colors[ix])
    }
}

combo.matrix.plot.color.legend=function(ll, title, fdir)
{
    if (is.null(ll))
        return (NULL)
    breaks = ll$breaks
    colors = ll$colors
    if (ll$type == "smooth") {
        panel = make.color.panel(colors=colors)
        wlegend2(fdir=fdir, panel=panel, breaks=breaks, title=title)
    } else {
        wlegend(fdir=fdir, names=breaks, cols=colors, title=title)
    }
}

make.panel=function(df, fields, colors, round.d=1, add.text=F,
                    min.value=NA, max.value=NA)
{
    if (any(!is.element(fields, names(df))))
        stop(sprintf("missing some fields: %s", paste(fields, collapse=",")))
    values = df[,fields]
    N = length(colors)
    
    if (!all(is.numeric(values)))
        stop(sprintf("some values not numeric: %s", paste(fields, collapse=",")))
    if(is.na(min.value)) min.value = min(values)
    if(is.na(max.value)) max.value = max(values)
    breaks = seq(min.value, max.value, length.out=N)
    list(fields=fields, type="smooth", colors=colors, breaks=breaks,
         round.d=round.d, add.text=add.text)
}

# user-defined colors/values
make.discrete.panel=function(df, fields, breaks, colors, round.d=0, add.text=F)
{
    if (any(!is.element(fields, names(df))))
        stop(sprintf("missing some fields: %s", paste(fields, collapse=",")))
    list(fields=fields, type="discrete", colors=colors, breaks=breaks,
         round.d=round.d, add.text=add.text)
}

make.discrete.panel.auto=function(df, field, round.d=0, add.text=F)
{
    if (any(!is.element(field, names(df))))
        stop(sprintf("missing field: %s", field))
    tt = sort(table(df[,field]), decreasing=T)
    breaks = names(tt)
    colors = rainbow(length(tt))
    
    list(fields=field, type="discrete", colors=colors, breaks=breaks,
         round.d=round.d, add.text=add.text)
}

################################################################################################
# main function
################################################################################################

combo.matrix.plot=function(df.x=NULL, df.y=NULL, df.mm=NULL,
                           panels.x=NULL, panels.y=NULL,
                           fdir=NULL, sfn=NULL,
                           params=combo.matrix.plot.params())
{
    pp = params
    pp$fdir = fdir
    pp$sfn = sfn

    if (!is.null(df.x)) {
        Nx = dim(df.x)[1]
        ids.x = df.x[,pp$field.x]
        df.x$ii = 1:Nx
        Mx = length(panels.x)
    } else {
        Nx = 0
        Mx = 0
    }
    
    if (!is.null(df.y)) {
        Ny = dim(df.y)[1]
        ids.y = df.y[,pp$field.y]
        df.y$ii = 1:Ny
        My = length(panels.y)
    } else {
        Ny = 0
        My = 0
    }
    
    if (!is.null(df.mm)) {
        df.mm$ii.x = match(df.mm[,pp$field.x], ids.x)
        df.mm$ii.y = match(df.mm[,pp$field.y], ids.y)
    }
    
    MM = Mx * My
    null.mm = matrix(rep(Mx + My + 2, MM), Mx, My)
    if (MM > 0) {
        layout.mm = rbind(cbind(null.mm, 1:Mx + 1), c(1:My + Mx + 1, 1))
    } else {
        if (My == 0 || Mx > 0)
            stop("expecting only y-panels")
        layout.mm = matrix(1:My, 1, My)
    }

    ###############################################################
    # compute total plot dimensions
    ###############################################################

    cells.x = sapply(panels.x, function(x) { length(x$fields) })
    cells.y = sapply(panels.y, function(x) { length(x$fields) })
    
    if (!is.null(panels.x)) {
        widths = c(pp$panel.gap + pp$cell.size*cells.y, pp$cell.size*Nx + pp$panel.gap + pp$margin.gap)
        widths[1] = widths[1] +  pp$margin.gap
        heights = c(pp$panel.gap + pp$cell.size*cells.x, pp$cell.size*Ny + pp$panel.gap + pp$margin.gap)
        heights[1] = heights[1] +  pp$margin.gap
    } else {
        widths = c(pp$panel.gap + pp$cell.size*cells.y)
        widths[1] = widths[1] +  pp$margin.gap
        heights = c(pp$cell.size*Ny + pp$panel.gap + pp$margin.gap)
    }

    
    ###############################################################
    # plot matrix
    ###############################################################

    plot.matrix=function() {
        panel = pp$color.f.mm
        df.mm$col =  combo.matrix.plot.color(ll=panel, values=df.mm[,pp$field.matrix])
        
        par(mai=c(pp$margin.gap, pp$panel.gap/2, pp$panel.gap/2, pp$margin.gap))
        plot.new()
        plot.window(xlim=c(0, Nx), ylim=c(0, Ny), xaxs="i", yaxs="i")

        rect(xleft=df.mm$ii.x-1, xright=df.mm$ii.x, ybottom=df.mm$ii.y-1, ytop=df.mm$ii.y,
             col=df.mm$col, border=NA)
        if (pp$add.text || panel$add.text) {
            text(x=df.mm$ii.x-0.5, y=df.mm$ii.y-0.5,
                 labels=round(df.mm[,pp$field.matrix], panel$round.d),
                 cex=pp$cex.text)
        }
        box()
    }
    
    ###############################################################
    # plot panel
    ###############################################################

    plot.panels=function(df, panels, is.x) {
        for (i in 1:length(panels)) {
            panel = panels[[i]]
            Np = length(panel$fields)
            labs = if (Np > 1) panel$fields else names(panels)[i]
            if (is.x) {
                mai = c(pp$panel.gap/2, pp$panel.gap/2, pp$panel.gap/2, pp$margin.gap)
                if (i == 1)
                    mai[3] = mai[3] + pp$margin.gap
                xlim=c(0, Nx)
                ylim=c(0, Np)
                side = 4
            } else {
                mai = c(pp$margin.gap, pp$panel.gap/2, pp$panel.gap/2, pp$panel.gap/2)
                if (i == 1)
                    mai[2] = mai[2] + pp$margin.gap
                xlim = c(0, Np)
                ylim  =c(0, Ny)
                side = 1
            }
            par(mai=mai)
            plot.new()
            plot.window(xlim=xlim, ylim=ylim, xaxs="i", yaxs="i")
            mtext(text=labs, side=side, at=1:Np-0.5, las=2, line=1)
            
            for (j in 1:Np) {
                field = panel$fields[j]
                cols =  combo.matrix.plot.color(ll=panel, values=df[,field])

                labels = if(panel$type == "smooth") round(df[,field], panel$round.d) else df[,field]
                if (is.x) {
                    rect(xleft=df$ii-1, xright=df$ii, ybottom=j-1, ytop=j, col=cols, border=NA)
                    if (pp$add.text || panel$add.text)
                        text(x=df$ii-0.5, y=j-0.5, labels=labels, cex=pp$cex.text)
                } else {
                    rect(xleft=j-1, xright=j, ybottom=df$ii-1, ytop=df$ii, col=cols, border=NA)
                    if (pp$add.text || panel$add.text)
                        text(x=j-0.5, y=df$ii-0.5, labels=labels, cex=pp$cex.text)
                }
            }
            if (i == 1) {
                if (is.x)
                    mtext(text=ids.x, side=3, at=1:Nx-0.5, las=2, line=1)
                else
                    mtext(text=ids.y, side=2, at=1:Ny-0.5, las=2, line=1)
            }
            box()
        }
    }

    if (pp$plot.legend) {
        combo.matrix.plot.color.legend(ll=pp$color.f.mm, title="matrix", fdir=pp$fdir)
        for (i in 1:length(panels.x)) {
            panel = panels.x[[i]]
            name = names(panels.x)[i]
            combo.matrix.plot.color.legend(ll=panel, title=name, fdir=pp$fdir)
        }
        for (i in 1:length(panels.y)) {
            panel = panels.y[[i]]
            name = names(panels.y)[i]
            combo.matrix.plot.color.legend(ll=panel, title=name, fdir=pp$fdir)
        }
    }

    ofn = paste(pp$fdir, "/", pp$sfn, sep="")
    if (pp$create.pdf) {
        height = sum(heights)
        width = sum(widths)
        fig.start(fdir=pp$fdir, ofn=ofn,
                  type="pdf", height=height, width=width)
    }

    layout(layout.mm, widths=widths, heights=heights)
    par(xpd=NA)

    if (!is.null(df.mm))
        plot.matrix()
    
    if (!is.null(df.x))
        plot.panels(df=df.x, panels=panels.x, is.x=T)
    
    if (!is.null(df.y))
    plot.panels(df=df.y, panels=panels.y, is.x=F)
    
    if (pp$create.pdf)
        fig.end()

    ofn
}

test.combo.matrix.plot=function()
{
    df.x = data.frame(xid=paste0("x", 1:5), vx1=c(0,1,0,1,0), vx2=1:5, vx3=5:1)
    df.y = data.frame(yid=paste0("y", 1:3), vy1=7, vy2=3:1, vy3=c(1,0,1))

    # matrix
    df.mm = expand.grid(df.x$xid, df.y$yid)
    names(df.mm) = c("xid", "yid")
    df.mm$value = runif(dim(df.mm)[1])

    color.f.mm = list(type="smooth", colors=c("white", "red"), breaks=c(0,1))
        
    # default params
    pp = combo.matrix.plot.params(color.f.mm=color.f.mm, fdir=getwd(), sfn="x.pdf")

    # x panels
    panels.x = list(p1=list(fields="vx1", type="discrete", colors=c("white", "red"), breaks=c(0,1)),
                    p2=list(fields=c("vx2", "vx3"), type="smooth", colors=c("white", "green"), breaks=c(1,5)))
    
    # y panels
    panels.y = list(p3=list(fields=c("vy1", "vy2"), type="smooth", colors=c("white", "blue"), breaks=c(1,3)))
    
    combo.matrix.plot(df.x=df.x, df.y=df.y, df.mm=df.mm, params=pp,
                      panels.x=panels.x, panels.y=panels.y)    
}

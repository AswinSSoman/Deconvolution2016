require(edgeR)
de.dir <- "DEresults/edgeR"
dir.create(de.dir, recursive=TRUE)

for (x in c("Zeisel", "Klein")) {
    cur.data <- readRDS(sprintf("%sData.rds", x))
    counts <- cur.data$Counts
    size.facs <- cur.data$SF

    if (x=="Zeisel") { 
        # Using only microglia
        grouping <- cur.data$Cells$level1class
        of.interest <- grouping %in% c("pyramidal CA1", "oligodendrocytes")
        counts <- counts[,of.interest]
        size.facs <- size.facs[of.interest,]
        grouping <- grouping[of.interest]
    } else {
        grouping <- cur.data$Cells$Time
    }
   
    # Using the precomputed size factors.
    alt.methods <- c("DESeq", "TMM", "LibSize") 
    stopifnot(all(alt.methods %in% colnames(size.facs)))
    stopifnot(all("Deconvolution" %in% colnames(size.facs)))
    fhandle <- file.path(de.dir, paste0(x, "_switched.tsv"))
    written <- FALSE
    
    for (group in unique(grouping)) {
        current <- grouping==group
        
        for (method in alt.methods) {
            y <- DGEList(counts[,current])
            y$samples$norm.factors <- size.facs$Deconvolution[current]/y$samples$lib.size
            design <- model.matrix(~log(size.facs[[method]][current]))
            y <- estimateDisp(y, design, prior.df=0, trend='none')
            fit <- glmFit(y, design)
            res <- glmLRT(fit)
            out <- decideTestsDGE(res)
            write.table(file=fhandle, data.frame(Group=group, Offset="Deconvolution", Covariate=method, DE=sum(out!=0), Total=length(out), Proportion=sum(out!=0)/length(out)*100),
                        sep="\t", quote=FALSE, append=written, col.names=(!written), row.names=FALSE)
            written <- TRUE
            gc()

            # Re-using same dispersion and p-value threshold, for a valid comparison.
            pval <- max(res$table$PValue[abs(out) > 1e-8])
            disp <- y$tagwise.dispersion

            y$samples$norm.factors <- size.facs[[method]][current]/y$samples$lib.size
            design <- model.matrix(~log(size.facs$Deconvolution[current]))
            fit <- glmFit(y, design, dispersion=disp)
            res <- glmLRT(fit)
            out <- res$table$PValue <= pval
            write.table(file=fhandle, data.frame(group, method, "Deconvolution", sum(out!=0), length(out), sum(out!=0)/length(out)*100),
                        sep="\t", quote=FALSE, append=TRUE, col.names=FALSE, row.names=FALSE)
            gc()
        }
    }
}

# Making a bar plot.

de.dir <- "DEresults/edgeR"
legended <- FALSE
for (x in c("Zeisel", "Klein")) {
    curfile <- file.path(de.dir, paste0(x, "_switched.tsv")) 
    xxx <- read.table(curfile, header=TRUE, sep="\t", stringsAsFactors=TRUE)

    allgroups <- unique(xxx$Group)
    for (g in allgroups) {
        gname <- sub(" ", "", g)
        chosen <- xxx$Group==g

        pdf(file.path(de.dir, paste0(x, "_", gname, ".pdf")))
        par(mar=c(4.1, 5.1, 2.1, 1.1))
        out <- barplot(xxx$Proportion[chosen], ylim=c(0, 100), space=rep(c(0.5, 0), 3), col=rep(c("grey80", "grey20"), 3), ylab="Proportion of genes DE (%)", 
                       cex.axis=1.2, cex.lab=1.4, main=paste0(x, " (", g, ")"), cex.main=1.4)
        mids <- colMeans(matrix(out, nrow=2))
        axis(side=1, at=mids, c("DESeq", "TMM", "Library size"), cex.axis=1.4)

        irked <- xxx[chosen,]$Offset=="LibSize"
        toprow <- c(xxx[chosen,]$DE[irked], xxx[chosen,]$Total[irked]-xxx[chosen,]$DE[irked])
        dirked <- xxx[chosen,]$Covariate=="LibSize"
        bottomrow <- c(xxx[chosen,]$DE[dirked], xxx[chosen,]$Total[dirked]-xxx[chosen,]$DE[dirked])
        print(fisher.test(rbind(toprow, bottomrow))$p.value)

        if (!legended) {
            legended <- TRUE
            legend("topright", fill=c("grey80", "grey20"), legend=c("As offset", "As covariate"), cex=1.4)
        }
        dev.off()
    }

}

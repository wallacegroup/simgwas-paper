#!/usr/bin/env Rscript
library(randomFunctions)
args <- getArgs(defaults=list(NCSE=1000,NCTL=1000,NSIM=10,NCV=2,SPECIAL=0),numeric=c("NCSE","NCTL","NSIM","NCV"))
source("~/DIRS.txt")

d <- SIMGWAS

## FIRST 5000 snps in Africans only
dref <- file.path(REFDATA,"1000GP_Phase3")
fhg <- file.path(d,"input")#tempfile(tmpdir=dtmp)
## crange <- paste0("7-",ncol(h)+6)
## system(paste("zcat",
##             file.path(dref,"chr21_afr.hap.gz"),
##             "|head -n 5000 | cut -d' ' -f",crange,
##             "> ", paste0(fhg,".hap")))
## system(paste("zcat",
##              file.path(dref,"1000GP_Phase3_chr21.legend.gz"),
##              "| head -n 5001 > ", paste0(fhg,".leg")))


## read in haplotypes
library(data.table)
## h <- fread(file.path(d,"example/ex.haps"))[1:1000,]
## snps <- fread(file.path(d,"example/ex.leg"))
## map <- fread(file.path(d,"example/ex.map"))
## wh <- which(c(0,diff(map[["Genetic_Map(cM)"]]))>0.1)
h <- fread(paste0(fhg,".hap"))
h <- as.matrix(h)
snps <- fread(paste0(fhg,".leg"))
## samples <- fread(file.path(dref,"1000GP_Phase3.sample"))
## map <- fread(file.path(d,"example/ex.map"))
## wh <- which(c(0,diff(map[["Genetic_Map(cM)"]]))>0.1)

devtools::load_all("~/RP/simGWAS")
## library(simGWAS)
library(mvtnorm)
library(corpcor)
h1 <- h[, seq(1,ncol(h)-1,by=2)] #[,samples$GROUP=="AFR"]
h2 <- h[, seq(2,ncol(h),by=2)] #[,samples$GROUP=="AFR"]
freq <- as.data.frame(t(cbind(h1,h2))+1)
snps$rs <- make.names(snps$id)
colnames(freq) <- snps$rs
use <- snps$AFR>0.01 & snps$AFR < 0.99 & apply(freq,2,var)>0
freq <- freq[,use,drop=FALSE]
dfsnps <- snps[use,,drop=FALSE]
dfsnps$maf <- colMeans(freq-1)
LD <- cor(freq)
LD <- as.matrix(make.positive.definite(LD))
## XX <- new("SnpMatrix", as.matrix(freq))S""
freq$Probability <- 1/nrow(freq)
sum(freq$Probability)

if(args$SPECIAL=="0") {
    CV=sample(which(dfsnps$AFR > 0.2 & dfsnps$AFR < 0.8),args$NCV)
#c(474) #sample(1:nrow(snps),2)
## g1 <- rep(2,args$NCV) #sample(c(1.2,1.5,1.8),args$NCV,replace=TRUE)
    g1 <- sample(c(1.1,1.2,1.3),args$NCV,replace=TRUE)
} else {
    source("~/Projects/simgwas/getspec.R") # defines CV and g1 according to args$SPECIAL
    CV <- match(CV,dfsnps$rs) # make numeric
}
FP <- make_GenoProbList(snps=dfsnps$rs,W=dfsnps$rs[CV],freq=freq)

## method 1 - simulate Z scores and adjust by expected variance to get beta
EZ <- est_statistic(N0=args$NCTL, # number of controls
                    N1=args$NCSE, # number of cases
                    snps=dfsnps$rs, # column names in freq of SNPs for which Z scores should be generated
                    W=dfsnps$rs[CV], # causal variants, subset of snps
                    gamma.W=log(g1), # odds ratios
                    freq=freq, # reference haplotypes
                    GenoProbList=FP) # FP above
simz <- rmvnorm(n = args$NSIM, mean = EZ, sigma = LD)
simv <- simulated_vbeta(N0=args$NCTL, # number of controls
                N1=args$NCSE, # number of cases
                snps=dfsnps$rs, # column names in freq of SNPs for which Z scores should be generated
                W=dfsnps$rs[CV], # causal variants, subset of snps
                gamma.W=log(g1), # odds ratios
                freq=freq, # reference haplotypes
                GenoProbList=FP,
                nrep=args$NSIM)
## simv <- 1/simv
simbeta <- simz* sqrt(simv)
## head(dv <- data.frame(maf=pmin(dfsnps$maf,1-dfsnps$maf),oneoverv=1/v,v=v,valt=valt,vb1=VB[[1]],vb2=VB[[2]],hg1=hg.se[,1],hg2=hg.se[,2]))
## ggplot(dv,aes(x=sqrt(v),y=1/sqrt(vb1),col=maf)) + geom_point() + geom_smooth() + geom_abline()
    

## ## method 6 - method 2 but with randomly sampled v(beta)
## valt <- expected_vbeta(N0=args$NCTL, # number of controls
##                   N1=args$NCSE, # number of cases
##                   snps=dfsnps$rs, # column names in freq of SNPs for which Z scores should be generated
##                   W=dfsnps$rs[CV], # causal variants, subset of snps
##                   gamma.W=log(g1), # odds ratios
##                   freq=freq, # reference haplotypes
##                   GenoProbList=FP) # FP above
## Ebeta <- EZ * valt

## do the same for hapgen
dtmp <- file.path(d,"tmp")
## dir.create(dtmp)
gstr <- paste(sapply(1:length(CV), function(i) { paste(dfsnps[CV[[i]],"position"], 1, g1[[i]], g1[[i]]^2) })  , collapse=" ")

funhg <- function() {
    tmp <- tempfile()#tmpdir=dtmp)
    tmp2 <- tempfile()#tmpdir=dtmp)
    system(paste(file.path(BINDIR,"hapgen2"),
                 "-m",file.path(dref,"genetic_map_chr21_combined_b37.txt"),
                 "-l",paste0(fhg,".leg"),
                 "-h",paste0(fhg,".hap"),
                 "-o", tmp,
                 "-dl",gstr,
                 "-n",args$NCTL,args$NCSE,
                 "-no_haps_output"))
    system(paste(file.path(BINDIR,"snptest")," -data ",
                 paste0(tmp,".controls.gen"),paste0(tmp,".controls.sample"),
                 paste0(tmp,".cases.gen"),paste0(tmp,".cases.sample"),
                 "-o",tmp2,
                 "-frequentist 1 -method score -pheno pheno"))
    unlink(list.files(dtmp,pattern=basename(tmp),full=TRUE)) ## cleanup
    ret <- fread(tmp2,skip=10L,sep=' ',fill=TRUE)
    ret[,rsid:=make.names(rsid)]
    ret <- ret[rsid %in% colnames(freq),
                       .(rsid,frequentist_add_pvalue,frequentist_add_beta_1,frequentist_add_se_1)]
    unlink(list.files(dtmp,pattern=basename(tmp2),full=TRUE)) ## cleanup
    return(ret)
}

## library(parallel)
results <- replicate(args$NSIM,funhg(),simplify=FALSE)
#results <- mclapply(1:20,function(i) fhg(),mc.cores=3)

hg.beta <- sapply(results,function(x) x$frequentist_add_beta_1)
hg.se <- sapply(results,function(x) x$frequentist_add_se_1)
## hg.p <- sapply(results,function(x) x$frequentist_add_pvalue)
## hg <- results[[1]]

## ## compare var(beta)
## head(dv <- data.frame(maf=pmin(dfsnps$maf,1-dfsnps$maf),oneoverv=1/v,v=v,valt=valt,vb1=VB[[1]],vb2=VB[[2]],hg1=hg.se[,1],hg2=hg.se[,2]))
## library(ggplot2)
## ggplot(dv,aes(x=sqrt(v),y=sqrt(1/vb1),col=maf)) + geom_point() + geom_smooth() + geom_abline()
## ggplot(dv,aes(x=valt,y=sqrt(1/vb1),col=maf)) + geom_point() + geom_smooth() + geom_abline()

## ggplot(dv,aes(x=sqrt(v),y=valt,col=maf)) + geom_point() + geom_smooth() + geom_abline()
## ggplot(dv,aes(x=sqrt(v),y=sqrt(vb2),col=maf)) + geom_point() + geom_smooth() + geom_abline()
## ggplot(dv,aes(x=sqrt(v),y=hg1,col=maf)) + geom_point() + geom_smooth() + geom_abline()
## ggplot(dv,aes(x=hg1,y=1/sqrt(vb1),col=maf)) + geom_point() + geom_smooth() + geom_abline()

## compare

## beta at causal var
## qqplot(betab[CV[[1]],], hg.beta[CV[[1]],]); abline(0,1)
## qqplot(simbetab[CV[[1]],], hg.beta[CV[[1]],]); abline(0,1)
## qqplot(betab[CV[[1]],], simbetab[CV[[1]],]); abline(0,1)

meth1 <- data.table(snp=rep(dfsnps$rs,each=args$NSIM),sim=rep(1:args$NSIM,nrow(dfsnps)),
                    beta1=as.vector(simbeta),#beta2=as.vector(simbeta2),
                    v=as.vector(simv))
hg <- data.table(snp=rep(results[[1]]$rsid,args$NSIM),sim=rep(1:args$NSIM,each=nrow(hg.beta)),
                 beta.hg=as.vector(hg.beta),
                 v.hg=as.vector(hg.se^2))
results <- merge(meth1,hg,by=c("snp","sim"),all.x=TRUE)
CV <- dfsnps$rs[CV]

of <- if(args$SPECIAL=="0") {
          tempfile(pattern=paste0("sim-c",args$NCSE,"-s",args$NSIM,"-"),tmpdir=d,fileext = ".RData")
      } else {
          tempfile(pattern=paste0("sim-c",args$NCSE,"-spec",args$SPECIAL,"-"),tmpdir=d,fileext = ".RData")
      }
## of <- "~/simgwas-1kg.RData"
save(results,CV,g1,args,file=of)

                     
unlink(tempdir(), recursive=TRUE)

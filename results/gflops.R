# =========================================================================================
# Benchmark
# Author: Giovanni Azua
# Date: 25 July 2013
# =========================================================================================
rm(list=ls())                                                        # clear workspace

library(boot)                                                        # use boot library
library(ggplot2)                                                     # use ggplot2 library
library(doBy)                                                        # use doBy library
library(utils)                                                       # use utils library
library(nlme)                                                        # use utils library
library(MASS)                                                        # use MASS library
library(Hmisc)
library(vcd)
library(directlabels)
library(extrafont)

loadfonts()

# =========================================================================================
# main
# =========================================================================================

# data directory
basedir <- "/Users/bravegag/code/eigen-magma-benchmark/results/"

# the main data frame
dfa <- NULL
dfa_mt <- NULL

# read the relevant files
file_names <- c('dgeqp3_eigen', 'dgeqp3_mkl', 'dgeqp3_magma')
#file_names <- c('dgemm_eigen', 'dgemm_mkl', 'dgemm_magma')
labels <- c('eigen', 'mkl', 'magma')
i <- 1
for (f in file_names) {
	all_files <- dir(path=basedir, pattern=paste(f, '\\.dat', sep=""))
	file_name <- all_files[1];
	
	print(paste("processing", file_name, "..."))	
	
	df <- read.table(paste(basedir, file_name, sep=""), header=FALSE)              # read the data as a data frame
	baseline <- f
	df$baseline <- labels[i]
	names(df)[1] <- "n"
	names(df)[2] <- "time"
	names(df)[3] <- "gflops"
	print(df)
	i <- i + 1

	if (is.null(dfa)) {
		dfa <- df		
	} else {
		dfa <- rbind(dfa, df)
	}		
}

dfa <- dfa[with(dfa, order(baseline, n)), ]

# =========================================================================================
# Define utility functions
# =========================================================================================

df <- dfa
df$main <- FALSE
df$main[df$baseline == "magma"] <- TRUE

# =========================================================================================
# Gflops plot
# =========================================================================================

# Draw the graph
p <- ggplot(data=df, mapping=aes(x=n, y=gflops, colour=baseline)) +
 scale_colour_manual(values=c("grey20", "red", "darkgreen"), guide="none") +
 geom_path(aes(size=main),size=0.8) + geom_point(size=3.2) + 
 geom_path(data=df[df$main,],size=0.75,colour="red") + geom_point(data=df[df$main,],size=3.0,colour="red") +
 scale_size_discrete(range=c(0.5,1), guide="none") +
 scale_x_continuous(expand=c(0,0), breaks=seq(0,5000,by=1000), limit=c(0,max(df$n + 800))) +
 geom_hline(aes(yintercept=0)) +
 scale_y_continuous("[Gflop/s]", limit=c(0,200), expand=c(0,0)) + 
 labs(title="Gflops dgeqp3, Xeon E5-2690, nVidia GTX Titan")

p <- direct.label(p, list("last.qp",vjust=0.3,hjust=-0.2,fontfamily="sans",fontsize=15,fontface="plain"))

dev.new(width=7, height=5)
p

filename <- paste(basedir, 'dgeqp3_gflops.svg',sep="")
ggsave(filename=filename, width=7, height=4)
embed_fonts(filename)
filename <- paste(basedir, 'dgeqp3_gflops.png',sep="")
ggsave(filename=filename, width=7, height=4)
embed_fonts(filename)

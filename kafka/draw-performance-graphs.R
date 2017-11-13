#!/usr/bin/env Rscript
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#needed functions
plotAndSummarize <- function(topicName,data){
    timeIndex <- grep("time",colnames(data))
    time <- data[,timeIndex[1]]
    subset <- data.frame(data[,-c(timeIndex)])##subset of data that isn't time
    numCols <- length(colnames(subset))

    png(paste(topicName,".png",sep = ""), width = 800, height = 800*numCols)
    par(mfrow=c(numCols,1))
    for(i in 1:numCols){
        ## time series
        plot(time, subset[,i], xlab = "time", ylab = colnames(subset)[i], main = paste(topicName,colnames(subset)[i], sep = " "), type = "l")
    }
    dev.off()

    names <- colnames(subset)
    for(i in 1:numCols){
            ## time series
        png(paste(topicName,"_",names[i],".png",sep = ""), width = 800, height = 800)
        plot(time, subset[,i], xlab = "time", ylab = colnames(subset)[i], main = paste(topicName,colnames(subset)[i], sep = " "), type = "l")
        dev.off()
    }
}

testingMetrics <- function(topicName, path){
    data <- read.csv(path, header = TRUE, sep = ",")
    numCols <- length(colnames(data))
    if(sum(grep("time",colnames(data)))>0){
        plotAndSummarize(topicName, data)
    } else{
        stop("Missing time arg.")
    }
}

strippedName <- function(files){
    names <- files
    for (i in 1:length(names)){
        names[i] = read.table(text = names[i], sep = ".", as.is = TRUE)$V1
    }
    names
}

args <- commandArgs(TRUE)

if(args[1]){
    files <- args[-1]
    fileNames <- strippedName(args[-1])
    for(i in 1:length(files)){
        if(sum(grep(".csv",files[i]) == 1)) testingMetrics(fileNames[i],files[i])
    }
} else{
    files <- list.files() #assume r is running in the same directory as the files
    fileNames <- strippedName(files)
    for(i in 1:length(files)){
        if(sum(grep(".csv",files[i]) == 1)) testingMetrics(fileNames[i],files[i])
    }
}

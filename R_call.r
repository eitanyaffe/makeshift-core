#!/bin/env Rscript

options(warn=1)

# get script name
all.args = commandArgs(F)
fn.arg = "--file="
script.name = sub(fn.arg, "", all.args[grep(fn.arg, all.args)])

args = commandArgs(T)
if (length(args) == 0) {
  cat(sprintf("usage: %s <makeshift dir> <working dir> <r file> <function> [param1=v11 v12 ... param2=v21 v22 ...]\n", script.name))
  q(status=1)
}

mk.dir = args[1]
work.dir = args[2]
source.fn = args[3]
func = args[4]
params = args[5:length(args)]

if (Sys.getenv("MAKESHIFT_ROOT") == "")
    Sys.setenv(MAKESHIFT_ROOT=dirname(mk.dir))

source(paste(mk.dir, "/utils.r", sep=""))
source(paste(mk.dir, "/ptree.r", sep=""))

params = paste(params, collapse=" ")
s = strsplit(params, '=', perl=T)[[1]]
s = sapply(strsplit(s, '\\s+', perl=T), function(x) x[x != ""])

if (length(s) > 2) {
    s[[length(s)]] = c(s[[length(s)]], -1)
    if (length(s[[1]]) != 1)
        stop(sprintf("first parameter (%s) must be followed by a = mark\n", s[[1]][1]))
    keys = sapply(s[1:length(s)-1], function(x) x[length(x)])
    values = sapply(s[2:length(s)], function(x) x[-length(x)])
} else {
    keys = s[[1]]
    values = s[2]
}

param.list = list()
for (i in seq_along(keys)) {
  key = keys[i]
  value = values[[i]]

  # first try to convert to numerical
  options(warn=-1) # to disable warning 'NAs introduced by coercion'
  if (all(!is.na(as.numeric(value))))
    value = as.numeric(value)
  options(warn=1)

  # check if we have booleans
  if (all(is.element(value, c("T", "F"))))
    value = (value == "T")

  param.list[[key]] = value
}

# set working dir
setwd(work.dir)

# load source file
cat(sprintf("loading %s\n", source.fn))
suppressPackageStartupMessages(source(source.fn))
options(error=NULL)

tostr = function(x)
{
  if (length(x) == 1 && x == "NULL")
    return (NULL)
  if (typeof(x) == "character")
    x = paste("\"", x, "\"", sep="")
  if (length(x) > 1)
    x = paste("c(", paste(x, collapse=",", sep=""), ")", sep="")
  x
}

# print the function call, helpful for debug
fmt.list = lapply(param.list, tostr)
str = paste(names(fmt.list), fmt.list, sep="=", collapse=", ")
cat(sprintf(">> Calling:\n%s(%s)\n", func, str))

str2 = paste(names(fmt.list), fmt.list, sep="=", collapse="; ")
str3 = paste(sprintf("source(\"%s/utils.r\");", mk.dir), sprintf("source(\"%s/ptree.r\");", mk.dir), str2, collapse=";")
cat(sprintf(">> Parameters:\n%s\n", str3))

# finally we omit NULL values from list
param.list[sapply(param.list, function(x) length(x) == 1 && x == "NULL")] = NULL

# call the function
do.call(func, param.list)

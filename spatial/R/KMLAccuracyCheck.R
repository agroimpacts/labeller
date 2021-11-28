#! /usr/bin/Rscript
# KMLAccuracyCheck.R
# Main script for calling QAQC accuracy assessment functions
# Author: Lyndon Estes

# Static arguments
diam <- 0.005 / 2 ## new master grid diameter
prjsrid <- 102022
count.acc.wt <- 0.1
in.acc.wt <- 0.7  
out.acc.wt <- 0.2  
new.in.acc.wt <- 0.4 ## for new score
new.out.acc.wt <- 0.2 ## for new score
cate.acc.wt <- 0.2 ## for new score, categorical accuracy
frag.acc.wt <- 0.1 ## for new score
edge.acc.wt <- 0.1 ## for new score
edge.buf <- 9 ## for new score, 3 planet pixels
acc.switch <- 1  ### 5/2/2016 Changed to 1
comments <- "F"
write.acc.db <- "T"  
# write.acc.db <- "N" 
draw.maps  <- "T"  
test.root <- "N"  
pngout <- TRUE


#### Test codes ####
# mtype <- 'qa'
# assignmentid <- '4386'
# kmlid <- 'GH0452367'
# tryid <- '1'
# host <- NULL

suppressMessages(library(rmapaccuracy)) # have to load this to get connection

# Input args 
arg <- commandArgs(TRUE)
mtype <- arg[1]  # training "tr" or normal qaqc check "qa"
kmlid <- arg[2]  # ID of grid cell 
assignmentid <- arg[3]  # Job identifier
if(length(arg) < 4) stop("At least 4 arguments needed", call. = FALSE)
tryid <- arg[4]
if(length(arg) == 4) {
  if(tryid != "None" & mtype == "qa") {
    stop("QAs do not have try numbers", call. = FALSE)
  }
  host <- NULL
} 
if(length(arg) > 4) {
  if(tryid == "None" & mtype == "qa") {
    tryid <- NULL
  } else if(arg[4] == "None" & mtype == "tr") {
    stop("Training sites need to have try numbers", call. = FALSE)
  }
  if(is.na(arg[5])) {
    host <- NULL
  } else {
    host <- arg[5]
  }
}
if(comments == "T") {
  print(paste("Mapping Type:", mtype))
  print(paste("KML ID:", kmlid))
  print(paste("Assignment ID:", assignmentid))
  print(paste("Try ID:", tryid))
  print(paste("Host name:", host))
}

if(test.root == "Y") {
  coninfo <- mapper_connect(host = host)
  prjstr <- (tbl(coninfo$con, "spatial_ref_sys") %>% 
               filter(srid == prjsrid) %>% collect())$proj4text
  print(paste("database =", coninfo$dinfo["db.name"], "directory = ", 
              coninfo$dinfo["project.root"]))
  print(prjstr)
  print("Stopping here: Just checking args and paths")
  
} else {
  # Execute accuracy function
  kml_accuracy(mtype = mtype, kmlid = kmlid, assignmentid = assignmentid,
               diam = diam, tryid = tryid, prjsrid = prjsrid, 
               count.acc.wt = count.acc.wt, in.acc.wt = in.acc.wt, 
               out.acc.wt = out.acc.wt, new.in.acc.wt = new.in.acc.wt,
               new.out.acc.wt = new.out.acc.wt, frag.acc.wt = frag.acc.wt,
               edge.acc.wt = edge.acc.wt, cate.acc.wt = cate.acc.wt,
               edge.buf = edge.buf, acc.switch = acc.switch, 
               comments = comments, write.acc.db = write.acc.db, 
               draw.maps = draw.maps, pngout = pngout, test = test, 
               test.root = test.root, host = host)
}


  
  


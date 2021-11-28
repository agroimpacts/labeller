#! /usr/bin/Rscript
# Purpose    : Script for retrieving worker assignments

# Libraries
# suppressMessages(library(RPostgreSQL))
suppressMessages(library(rmapaccuracy))
suppressWarnings(suppressMessages(library(sf)))
suppressWarnings(suppressMessages(library(dplyr)))

# Get HIT ID, assignment ID
args <- commandArgs(TRUE)
if(length(args) < 3) stop("Need at least 3 arguments")
# args <- c("1435", "26", "N", "crowdmapper.org")
# hitid <- '1435'; workerid <- "26"; test_root <- "N"; host <- "crowdmapper.org"
hitid <- args[1] 
workerid <- args[2]   
test_root <- args[3]
if(!is.na(args[4])) {
  host <- args[4]
} else {
  host <- NULL
}

# Find working location
coninfo <- mapper_connect(host = host)

initial_options <- commandArgs(trailingOnly = FALSE)
kml_path <- paste0(coninfo$dinfo$project_root, "/maps/")
kml_root <- strsplit(coninfo$dinfo$project_root, "/")[[1]][3]

if(test_root == "Y") {
  print(paste("database =", coninfo$dinfo["db.name"], "; kml.root =", kml_root, 
              "; worker kml directory =", kml_path, "; hit =", hitid))
  print(paste("Stopping here: Just making sure we are working and writing to", 
              "the right places"))
} 

if(test_root == "N") {
  
  # Paths and connections
  # Read in hit and assignment ids  
  hits <- tbl(coninfo$con, "hit_data") %>% filter(hit_id == hitid) %>%
    select(name) %>% collect()
  assignments <- tbl(coninfo$con, "assignment_data") %>% 
    filter(hit_id == hitid & worker_id == workerid & status != "Abandoned") %>% 
    select(assignment_id) %>% collect()
  
  if(nrow(assignments) > 1) {
    stop("More than one assignment for this worker for this HIT")
  }
  
  # Collect QAQC fields (if there are any; if not then "N" value will be 
  # returned). This should work for both
  # training and test sites
  qaqc_sql <- paste0("select gid from qaqcfields where name=", "'", 
                     hits$name, "'")
  qaqc_polys <- DBI::dbGetQuery(coninfo$con, qaqc_sql)
  qaqc_hasfields <- ifelse(nrow(qaqc_polys) > 0, "Y", "N") 
  if(qaqc_hasfields == "Y") {
    qaqc_sql <- paste0("select gid, name, category, geom_clean",
                       " from qaqcfields where name=", "'", hits$name, "'", 
                       " order by gid")
    qaqc_polys <- suppressWarnings(st_read(coninfo$con, query = qaqc_sql))
    # reorganize: this won't be necessary if we revise qaqcfields table
    qaqc_polys <- qaqc_polys %>% 
      mutate(name = paste0(name, "_", 1:nrow(qaqc_polys))) %>% select(-gid)
  }
  
  # Read in user data
  # first test if user fields exist
  user_sql <- paste0("select name from user_maps where ", "
                     assignment_id=", "'", assignments$assignment_id, "'")
  user_polys <- DBI::dbGetQuery(coninfo$con, user_sql)
  user_hasfields <- ifelse(nrow(user_polys) > 0, "Y", "N") 
  if(user_hasfields == "Y") {  # Read in user fields if there are any
    user_sql <- paste0("select name, category, categ_comment, geom_clean",  
                       " from user_maps where assignment_id=", "'", 
                       assignments$assignment_id, "'", " order by name")
    user_polys <- suppressWarnings(st_read(coninfo$con, query = user_sql))
  } 

  # Create unique directory for worker if file doesn't exist
  worker_path <- paste(kml_path, workerid, sep = "")
  if(!file.exists(worker_path)) dir.create(path = worker_path)
  
  # Write KMLs out to worker specific directory
  # setwd(worker_path)
  # nm <- paste(hits$name, assignments$assignment_id, sep = "_")
  kmlid <- hits$name
  if(nrow(user_polys) > 0) {  # Write it
    suppressWarnings(user_poly <- user_polys %>% 
                       select(name, category, categ_comment))
    suppressWarnings(st_write(user_poly, delete_dsn = TRUE, 
                              driver = 'kml', quiet = TRUE, 
                              dsn = paste0(worker_path, "/", kmlid, "_w.kml")))
  }
  if(nrow(qaqc_polys) > 0) {  # First convert to geographic coords
    suppressWarnings(qaqc_poly <- qaqc_polys %>% 
                       select(name, category))
    suppressWarnings(st_write(qaqc_poly, delete_dsn = TRUE, quiet = TRUE, 
                              dsn = paste0(worker_path, "/", kmlid, "_r.kml")))
  }
  # worker_url <- paste0("https://", kml_root,
  worker_url <- paste0("https://", coninfo$dinfo$server_name, 
                       "/api/getkml?kmlName=", kmlid, "&workerId=", workerid)
  cat(worker_url, "\n") # Return details
}

## Author: Lei Song
## To update the database after clear the database
## if it is initial, update master_grid and scenes_data table
## if it is the regular production, 
## update the configuration propotion values in DB to generate initial F sites
## This simply make sure all the initial Fs are validate
## the lines should be changed later if the demands change.

PkgNames <- c("DBI", "dplyr",  "aws.s3", "rmapaccuracy", "data.table")
invisible(suppressMessages(suppressWarnings(
  lapply(PkgNames, require, character.only = T))))

arg <- commandArgs(TRUE)
initial_num <- arg[1]

# Connect to DB
coninfo <- mapper_connect()

# Set all to T
sql <- paste0("UPDATE master_grid SET avail='T' WHERE avail in ('I', 'Q')")
dbExecute(coninfo$con, sql)

# Is
Is <- tbl(coninfo$con, "kml_data_static") %>%
  filter(kml_type == "I") %>%
  collect()
names <- paste0("'", Is$name, "'", collapse = ",")
sql <- paste0("UPDATE master_grid SET avail='I' WHERE name in (", names, ")")
dbExecute(coninfo$con, sql)

# Qs
Qs <- tbl(coninfo$con, "kml_data_static") %>%
  filter(kml_type == "Q") %>%
  collect()
names <- paste0("'", Qs$name, "'", collapse = ",")
sql <- paste0("UPDATE master_grid SET avail='Q' WHERE name in (", names, ")")
dbExecute(coninfo$con, sql)

# Clean iteration_metrics
sql <- paste0("delete from iteration_metrics")
dbExecute(coninfo$con, sql)

# Read params
common_path <- file.path(coninfo$dinfo["project_root"], "common")
params <- yaml::yaml.load_file(file.path(common_path, 'config.yaml'))

# Check if it is the initial drawing
if (params$labeller$initial == 1 | params$labeller$initial == 2) {
  # Condition judgement
  # This file need to get beforehand
  train_static <- s3read_using(read.csv,
                               object = file.path(params$learner$prefix,
                                                  params$learner$incoming_names_static),
                               bucket = params$learner$bucket)
  
  # Update the master_grid
  names <- paste0("'", train_static$name, "'", collapse = ",")
  sql <- paste0("UPDATE master_grid SET avail='F' WHERE name in (", names, ")")
  dbExecute(coninfo$con, sql)
  
  # Update iteration_metrics and incoming_names
  sql <- sprintf(paste0("insert into iteration_metrics",
                        " (run, iteration, aoi, iteration_time) values",
                        " (%d, %d, %d, '%s');"),
                 0, 0, params$learner$aoiid, as.character(Sys.time()))
  dbExecute(coninfo$con, sql)
  # Insert new ones
  # train_static <- train_static %>%
  #   filter(aoi == params$learner$aoiid)
  insert_db <- lapply(train_static$name, function(name_each) {
    sql <- sprintf(paste0("insert into incoming_names",
                          " (name, run, iteration, usage) values",
                          " ('%s', %d, %d, '%s');"),
                   name_each, 0, 0, "train")
    dbExecute(coninfo$con, sql)
    # db_commit(coninfo$con)
  })
  
  # Run register_f_sites
  cmd_text <- sprintf("python %s/common/register_f_sites.py",
                      coninfo$dinfo$project_root)
  system(cmd_text, intern = FALSE)
  
  # Update scenes_data table
  planet_catalog_path <- file.path(params$learner$prefix,
                                   params$labeller$s3_catalog_name)
  planet_catalog <- s3read_using(read.csv, 
                                 stringsAsFactors = F,
                                 bucket = params$learner$bucket,
                                 object = planet_catalog_path)
  # Get Qs, Is and incoming_names
  names_quality <- tbl(coninfo$con, "kml_data_static") %>%
    select(name) %>% collect() %>% data.table()
  incoming_names <- tbl(coninfo$con, "incoming_names") %>%
    select(name) %>% collect() %>% data.table()
  names_exist <- c(names_quality$name, incoming_names$name)
  ids_exist <- tbl(coninfo$con, "master_grid") %>%
    filter(name %in% names_exist) %>%
    collect() %>% data.table()
  
  planet_catalog <- planet_catalog %>%
    filter(cell_id %in% ids_exist$id)
  
  # Insert new ones
  insert_db <- lapply(1:nrow(planet_catalog), function(i) {
    row_catalog <- planet_catalog[i, ]
    # "cell_id", "scene_id", "col", "row", "season", "url", "tms_url"
    sql <- sprintf(
      paste0("insert into scenes_data",
             " (provider, scene_id, cell_id, season, ",
             "global_col, global_row, ",
             "url, tms_url, date_time) values",
             " ('%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s');"),
      "planet", row_catalog$scene_id, row_catalog$cell_id,
      row_catalog$season, row_catalog$col, row_catalog$row,
      row_catalog$url, row_catalog$tms_url, Sys.time()
    )
    dbExecute(coninfo$con, sql)
  })
  
} else if (params$labeller$initial == 3) {
  # Update initialFnum
  sql <- sprintf("UPDATE configuration SET value=%s where key = 'InitialFnum'", 
                 initial_num)
  dbExecute(coninfo$con, sql)
  
  # Update the percentage of holdouts
  sql <- paste0("UPDATE configuration SET value=100 where ",  
                "key = 'ProportionHoldout'")
  dbExecute(coninfo$con, sql)
  sql <- paste0("UPDATE configuration SET value=0 where ", 
                "key = 'ProportionHoldout1'")
  dbExecute(coninfo$con, sql)
  db_commit(coninfo$con)
}
## No regular rules for the single mode, so skip it


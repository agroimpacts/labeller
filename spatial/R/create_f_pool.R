## Author: Lei Song
## To create the F pool for an instance
## Getting familiar with config.yaml before to read it
## Inputs:
## geojson of aois, master_grid.tif
## outputs:
## f_pool_aoi.csv, qs_in_aoi.csv to S3

PkgNames <- c("sf", "DBI", "dplyr", "dbplyr","yaml", 
              "aws.s3", "data.table", "rmapaccuracy")
invisible(suppressMessages(suppressWarnings(
  lapply(PkgNames, require, character.only = T))))

arg <- commandArgs(TRUE)
aois_index <- arg[1]

## Read the config.yaml file and connect to the database
coninfo <- mapper_connect()
common_path <- file.path(coninfo$dinfo["project_root"], "common")
params <- yaml::yaml.load_file(file.path(common_path, 'config.yaml'))
gcsstr <- "+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"

## Read AOIs
aois <- s3read_using(st_read, 
                     quiet = TRUE,
                     object = params$labeller$aoi_s3_object,
                     bucket = params$learner$bucket)
aois <- aois[aois_index, ]

## Read grid tif
master_grid <- s3read_using(raster::raster,
                            object = params$labeller$master_grid_s3_object,
                            bucket = params$learner$bucket)
raster::crs(master_grid) <- gcsstr

## Extract the ids of master grid of AOIs
aois_grid <- raster::mask(raster::crop(master_grid, aois), aois)
aois_grid <- na.omit(raster::getValues(aois_grid))

## Update the master grid table
## Update the master grid using the full F
## because it is possible we will get the could-free images later
## Make sure this is the whole thing.

## Extract the col and row number of the F grids.
coors <- tbl(coninfo$con, "master_grid") %>% 
  filter(id %in% aois_grid) %>% 
  dplyr::select(x, y, name) %>% 
  collect()

f_pool <- cbind("name" = as.character(coors$name), 
                rowcol_from_xy(x = coors$x, 
                               y = coors$y, 
                               offset = -1)) %>%
  data.table() %>%
  mutate(name_col_row = paste0(name, "_", col, "_", row))

## Delete the names already in kml_data_static
names_exist <- tbl(coninfo$con, "kml_data_static") %>%
  dplyr::select(name) %>% collect() %>% data.table()
f_pool_new <- f_pool %>% 
  filter(!name %in% names_exist$name) %>%
  select(name, col, row, name_col_row)

# Merge the incoming_names_static
incomes_static_path <- file.path(params$learner$prefix,
                                 params$learner$incoming_names_static)
incomes_static <- s3read_using(read.csv, 
                               stringsAsFactors = F,
                               bucket = params$learner$bucket,
                               object = incomes_static_path)
## Update the master grid table
## Update the master grid using the full F
## because it is possible we will get the could-free images later
## Make sure this is the whole thing.
f_pool_new_nostatic <- f_pool_new %>%
  filter(!name %in% incomes_static$name)
names <- paste0("'", f_pool_new_nostatic$name, "'", collapse = ",")
sql <- paste0("UPDATE master_grid SET avail='F' WHERE name in (", names, ")")
dbExecute(coninfo$con, sql)

if (nrow(incomes_static) > 0){
  incomes_static <- incomes_static %>%
    filter(! name %in% f_pool_new$name)
  coors <- tbl(coninfo$con, "master_grid") %>% 
    filter(name %in% !!incomes_static$name) %>% 
    dplyr::select(x, y, name) %>% 
    collect()
  
  f_pool_new_comp <- cbind(
    "name" = as.character(coors$name), 
    rowcol_from_xy(x = coors$x, y = coors$y, offset = -1)
  ) %>% data.table() %>% mutate(name_col_row = paste0(name, "_", col, "_", row))
  f_pool_out <- rbind(f_pool_new, f_pool_new_comp)
} else {f_pool_out <- f_pool_new}

# Save out a csv with Qs within this AOI
qs_in <- setdiff(f_pool, f_pool_new)
qs_path <- file.path(params$learner$prefix,
                     params$learner$qs)
s3write_using(qs_in, 
              FUN = write.csv,
              row.names = F,
              object = qs_path, 
              bucket = params$learner$bucket)

# Not necessary anymore since all sites must have images
# ## Update the F pool using scene data
# scenes_gs <- tbl(coninfo$con, "scenes_data") %>%
#   select(cell_id, season, global_col, global_row) %>% 
#   filter(season == "GS") %>% collect() %>% data.table()
# scenes_os <- tbl(coninfo$con, "scenes_data") %>%
#   select(cell_id, season, global_col, global_row) %>% 
#   filter(season == "OS") %>% collect() %>% data.table()
# scenes_data <- merge(scenes_gs, scenes_os, by = "cell_id") %>%
#   select(col = global_col.x, row = global_row.x, cell_id)
# 
# f_pool_new <- f_pool_new %>% 
#   merge(scenes_data,
#         by = c("col", "row")) %>% 
#   select(-cell_id) %>% data.table()

## Make a corresponding planet_catalog.csv file
## Make a subset of scenes data based on f_pool and Qs
f_pool$col <- as.integer(f_pool$col)
f_pool$row <- as.integer(f_pool$row)

# Update the scenes_data table
# Get Qs and Is not in f_pool
ids_exist <- tbl(coninfo$con, "master_grid") %>%
  filter(name %in% local(names_exist$name) &
           !name %in% local(f_pool$name)) %>%
  collect() %>% data.table()

# Get the static incoming_names not in f_pool
incomes_static <- s3read_using(read.csv, 
                               stringsAsFactors = F,
                               bucket = params$learner$bucket,
                               object = incomes_static_path)
ids_incomes_others <- tbl(coninfo$con, "master_grid") %>%
  filter(name %in% local(incomes_static$name) &
           !name %in% local(f_pool$name)) %>%
  collect() %>% data.table()

planet_catalog_path <- file.path(params$learner$prefix,
                                 params$labeller$s3_catalog_name)
planet_catalog <- s3read_using(read.csv, 
                               stringsAsFactors = F,
                               bucket = params$learner$bucket,
                               object = planet_catalog_path)
planet_catalog <- planet_catalog %>%
  filter(cell_id %in% c(aois_grid, 
                        ids_exist$id, 
                        ids_incomes_others$id))

# Insert new ones
insert_db <- lapply(1:nrow(planet_catalog), function(i) {
                  row_catalog <- planet_catalog[i, ]
                  # "cell_id", "scene_id", "col", "row", "season", "url", "tms_url"
                  sql <- sprintf(paste0("insert into scenes_data",
                                        " (provider, scene_id, cell_id, season, ",
                                        "global_col, global_row, ",
                                        "url, tms_url, date_time) values",
                                        " ('%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s');"),
                                 "planet", row_catalog$scene_id, row_catalog$cell_id,
                                 row_catalog$season, row_catalog$col, row_catalog$row,
                                 row_catalog$url, row_catalog$tms_url, Sys.time())
                  dbExecute(coninfo$con, sql)
                  # db_commit(coninfo$con)
})

## Pair the scenes for growing and off season
scenes_gs <- tbl(coninfo$con, "scenes_data") %>%
  select(cell_id, season, global_col, global_row) %>%
  filter(season == "GS") %>% collect() %>% data.table()
scenes_os <- tbl(coninfo$con, "scenes_data") %>%
  select(cell_id, season, global_col, global_row) %>%
  filter(season == "OS") %>% collect() %>% data.table()
scenes_data <- merge(scenes_gs, scenes_os, by = "cell_id") %>%
  select(col = global_col.x, row = global_row.x, cell_id)

################# Temporary#################
# Update the F pool using scene data
f_pool_out <- f_pool_out %>%
  merge(scenes_data,
        by = c("col", "row")) %>%
  select(-cell_id) %>% data.table()
################# Temporary#################

# Here should save out the comprehensive f_pool table
## Save f_pool csv to the S3 bucket
Sys.setenv("AWS_ACCESS_KEY_ID" = params$learner$aws_access,
           "AWS_SECRET_ACCESS_KEY" = params$learner$aws_secret,
           "AWS_DEFAULT_REGION" = params$learner$aws_region)

f_pool_path <- file.path(params$learner$prefix,
                         params$learner$pool)
s3write_using(f_pool_out, 
              FUN = write.csv,
              row.names = F,
              object = f_pool_path, 
              bucket = params$learner$bucket)

# Double check and save out planet catalog file
planet_catalog <- tbl(coninfo$con, "scenes_data") %>% 
  select(cell_id, scene_id, global_col, 
         global_row, season, url) %>% 
  collect() %>% data.table()
names(planet_catalog) <- c("cell_id", "scene_id", "col", "row", "season", "uri")

## Save catalog csv to the S3 bucket
s3write_using(planet_catalog, 
              FUN = write.csv,
              row.names = F,
              object = params$learner$image_catalog, 
              bucket = params$learner$bucket)

cmd_text <- sprintf("python %s/common/initial_f_sites.py",
                    coninfo$dinfo$project_root)
system(cmd_text, intern = FALSE)

# Update master grid for other incomes
names <- paste0("'", incomes_static$name, "'", collapse = ",")
sql <- paste0("UPDATE master_grid SET avail='F' WHERE name in (", names, ")")
dbExecute(coninfo$con, sql)

## Disconnect the database
dbDisconnect(coninfo$con)

# inspect worker's maps across multiple instances and print it out to a 
# presentation. Takes for a single input worker and pulls random draws across
# multiple instances

######################
# place and change these arguments in a separate untracked .R file that you use 
# to run this script. Intended to run in specific directory structure. 
# worker <- 111
# hostname <- "labeller"
# host_ids <- c(10:11, 13:14, 16)
# host_root <- "crowdmapper.org"
# nmaps <- 2
# seed <- 1
# iteration <- "max"
## set these paths. Note the requirement for the display_user_maps.R function
## in labeller's repo
# out_path <- here::here("spatial/notebooks/figures/mappers/individual")
# display_func_path <- here::here("spatial/R/tools/display_user_maps.R")
# password <- "postgis password here"
# source(here::here("spatial/R/tools/inspect_user_maps.R"))
######################

library(dplyr)
library(sf)
library(glue)

# setup directories
worker_path <- file.path(out_path, worker)
worker_sub_paths <- file.path(worker_path, c("presentation", "data"))
data_path <- file.path(out_path, "presentation")
if(!dir.exists(worker_path)) {
  dir.create(worker_path)
  for(i in worker_sub_paths) dir.create(i)
}

# rmapaccuracy function here to allow usage independent of package
point_to_gridpoly <- function(xy, w, OldCRSobj, NewCRSobj) {
  dw <- list("x" = c(-w, w, w, -w, -w), "y" = c(w, w, -w, -w, w))
  pols <- do.call(rbind, lapply(1:nrow(xy), function(i) {  # i <- 1
    xs <- unlist(sapply(dw$x, function(x) unname(xy[i, "x"] + x)))
    ys <- unlist(sapply(dw$y, function(x) unname(xy[i, "y"] + x)))
    p1 <- list(t(sapply(1:length(xs), function(i) c(xs[i], ys[i]))))
    ## create a geometry (sfg) from points, e.g., point, polygon, multipolygon
    pol <- st_polygon(p1)
    ## create a sfc, which is a list of sfg
    poldf <- st_sfc(pol)
    polsf <- st_sf(xy[i, .(name)], geom = poldf)
    st_crs(polsf) <- OldCRSobj # first set GCS
    polsf <- st_transform(polsf, crs = NewCRSobj) # then transform into PRS
    polsf
  }))
  return (pols)
}

selected_fields <- lapply(host_ids, function(x) { # x <- host_ids[1]
  # print(x)
  host <- paste0(hostname, x, ".", host_root)
  upw <- list("user" = "postgis", "password" = password)
  con <- DBI::dbConnect(RPostgreSQL::PostgreSQL(), host = host, 
                        dbname = "Africa", user = upw$user, 
                        password = upw$password)
  
  # Read in incoming_names from selected iteration
  if(iteration != "max") {
    iter <- iteration
  } else {
    iter <- tbl(con, "incoming_names") %>% filter(processed == TRUE) %>% 
      distinct(iteration) %>% pull(iteration) %>% max()
  }
  if(run != "max") {
    run <- run
  } else {
    run <- tbl(con, "incoming_names") %>% filter(processed == TRUE) %>% 
      distinct(run) %>% pull(run) %>% max()
  }
  
  ## get data from dbase
  categories <- tbl(con, "categories") %>% collect()
  
  # incoming_names (for F type)
  incoming_names <- tbl(con, "incoming_names") %>% 
    filter(iteration == iter & run == run) %>% pull(name)
  
  # assignments, randomly 
  assignments <- tbl(con, "assignment_data") %>%
    filter(!is.null(completion_time)) %>% filter(worker_id == worker) %>% 
    collect()
  
  # HITs, randomly select two of workers' hits
  set.seed(seed)
  hits <- tbl(con, "hit_data") %>% filter(hit_id %in% !!assignments$hit_id) %>% 
    filter(name %in% incoming_names) %>% collect() %>% 
    sample_n(size = nmaps) %>% left_join(., assignments, by = "hit_id") %>% 
    select(name, hit_id, assignment_id, worker_id)
  
  # corresponding grids -> convert to polygons
  grids <- tbl(con, "master_grid") %>%
    filter(name %in% !!hits$name)  %>% select(id, name, x, y, avail) %>%
    collect() %>% data.table::data.table()
  gcs <- "+proj=longlat +datum=WGS84 +no_defs"
  gpoly <- point_to_gridpoly(grids, w = 0.005 / 2, gcs, gcs)
  
  # tms_urls for images
  tms_urls <- tbl(con, "scenes_data") %>% filter(cell_id %in% !!grids$id) %>%
    distinct(cell_id, tms_url, season) %>% collect() %>% 
    left_join(., grids, by = c("cell_id" = "id"))
  
  # user maps pick up fields for assignment
  sqls <- paste0("select name, category, geom_clean",
                 " FROM user_maps INNER JOIN categories ",
                 "USING (category) where assignment_id IN (",
                 paste0("'", hits$assignment_id, "'", collapse = ", "), ") ",
                 "AND categ_group='field'")
  
  # get fields if they exist, return null if not
  fields <- DBI::dbGetQuery(con, gsub(", geom_clean", "", sqls))
  if(nrow(fields) > 0) {
    user_polys <- st_read(con, query = sqls)
    user_polys <- user_polys %>% mutate(fldname = name) %>% 
      mutate(name = gsub("_.*", "", name)) %>% select(name, fldname, category)
  } else {
    user_polys <- NULL
  }
  DBI::dbDisconnect(con)  # disconnect
  return(list("grid" = gpoly, "user" = user_polys, "tms" = tms_urls, 
              "iteration" = iter, "cats" = categories))
})
names(selected_fields) <- paste0("i", host_ids)

tstamp <- format(Sys.time(), "%Y-%m-%d_%H%M%S")
dat_file <- file.path(worker_sub_paths[2], 
                      paste0("worker", worker, "_", tstamp, ".rda"))
dat <- selected_fields
save(dat, file = dat_file)

## Create rmarkdown document
outfile <- paste0(worker_sub_paths[1], "/worker_", worker, "_", tstamp, ".Rmd")
head_text <- c(paste0("title: 'Labels: mapper ", worker, "'\n"), 
               "output: html_document\n", "---\n")
chunk_text <- c("```{r, echo=FALSE, message=FALSE, warning=FALSE}\n", "```\n")

# write presentation header  
cat("---\n", file = outfile)
for(i in head_text) cat(i, file = outfile, append = TRUE)

nl <- function(x) paste0(x, "\n")
# write presentation body
for(i in 1:length(dat)) {
  # if first slide, write in echo = FALSE statement to source function and 
  # data
  if(i == 1) {
    cat(chunk_text[1], file = outfile, append = TRUE)
    cat("library(leaflet)\n", file = outfile, append = TRUE)
    cat("library(dplyr)\n", file = outfile, append = TRUE)
    cat("library(sf)\n", file = outfile, append = TRUE)
    cat(paste0("source('", display_func_path, "')\n"), file = outfile, 
        append = TRUE)
    cat(paste0("load('", dat_file, "')\n"), file = outfile, 
        append = TRUE)
    cat(chunk_text[2], file = outfile, append = TRUE)
  }
  for(j in 1:nrow(dat[[i]]$grid)) {  # i <- 1; j <- 1
    d <- dat[[i]]
    gname <- d$grid %>% slice(j) %>% pull(name)
    cat(chunk_text[1], file = outfile, append = TRUE)
    cat_strings <- c(
      nl(glue("d <- dat[[{i}]]")),
      nl(glue("gpoly <- d$grid %>% slice({j})")), 
      nl(glue("gname <- gpoly %>% pull(name)")), 
      nl(glue("if(!is.null(d$user)) user_maps <- d$user %>%", 
              "filter(name == gname)")),
      nl(glue("if(is.null(d$user)) user_maps <- NULL")),
      nl(glue("os_url <- d$tms %>% filter(name == gname & season == 'OS') ", 
              "%>% pull(tms_url)")),
      nl(glue("gs_url <- d$tms %>% filter(name == gname & season == 'GS') ",
              "%>% pull(tms_url)"))
    )
    for(k in cat_strings) cat(k, file = outfile, append = TRUE)
    cat(chunk_text[2], file = outfile, append = TRUE)
    cat("\n", file = outfile, append = TRUE)

    cat(nl(glue("## Labeller {gsub('i', '', names(dat)[i])} Cell {gname}")), 
        file = outfile, append = TRUE)
    cat(chunk_text[1], file = outfile, append = TRUE)
    cat(nl(glue(
      "display_user_maps(gpoly, user_maps, os_url, gs_url, d$cats)")
    ), file = outfile, append = TRUE)
    cat(chunk_text[2], file = outfile, append = TRUE)
    
    # cat("---\n", file = outfile, append = TRUE)
    cat("\n", file = outfile, append = TRUE)
  }
}

# render markdown, both html (for interactive viewing) and pdf (for annotating)
rmarkdown::render(outfile, output_file = gsub(".Rmd", ".html", outfile))
# replace writeout to html, writes more slowly
BrailleR::FindReplace(outfile, "output: html_document", "output: pdf_document")
rmarkdown::render(outfile, output_file = gsub(".Rmd", ".pdf", outfile))



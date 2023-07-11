# inspect worker's maps across multiple instances and print it out to a 
# presentation. Takes for a single input worker and pulls random draws across
# multiple instances

######################
# place and change these arguments in a separate untracked .R file that you use 
# to run this script. Intended to run in specific directory structure. 
# worker <- 111
# hostname <- "congo"
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
pres_path <- file.path(out_path, "presentation")
if(!dir.exists(pres_path)) dir.create(pres_path)
data_path <- file.path(out_path, "presentation/data")
if(!dir.exists(data_path)) dir.create(data_path)

host <- paste0(hostname, ".", host_root)
upw <- list("user" = "postgis", "password" = password)
con <- DBI::dbConnect(RPostgreSQL::PostgreSQL(), host = host, 
                      dbname = "Africa", user = upw$user, 
                      password = upw$password)

# get grids
grids <- tbl(con, "master_grid") %>%
  filter(name %in% !!sites$name)  %>% dplyr::select(id, name, x, y, avail) %>%
  collect() %>% data.table::data.table()
gcs <- "+proj=longlat +datum=WGS84 +no_defs"
gpoly <- point_to_gridpoly(grids, w = 0.005 / 2, gcs, gcs)

# tms_urls for images
tms_urls <- tbl(con, "scenes_data") %>% filter(cell_id %in% !!grids$id) %>%
  distinct(cell_id, tms_url, season) %>% collect() %>% 
  left_join(., grids, by = c("cell_id" = "id"))

# save out data
tstamp <- format(Sys.time(), "%Y-%m-%d_%H%M%S")
dat <- list("grid" = gpoly, "tms" = tms_urls)
dat_file <- file.path(data_path, paste0("image_viewer_data_", tstamp, ".rda"))
save(dat, file = dat_file)

## Create rmarkdown document
outfile <- paste0(pres_path, "/image_viewer_", tstamp, ".Rmd")
head_text <- c(paste0("title: 'Image overview'\n"), 
               "output: html_document\n", "---\n")
chunk_text <- c("```{r, echo=FALSE, message=FALSE, warning=FALSE}\n", "```\n")

# write presentation header  
cat("---\n", file = outfile)
for(i in head_text) cat(i, file = outfile, append = TRUE)

nl <- function(x) paste0(x, "\n")
# write presentation body
for(i in 1:nrow(dat$grid)) {
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
  d <- dat$grid[i, ]
  gname <- d %>% pull(name)
  cat(chunk_text[1], file = outfile, append = TRUE)
  cat_strings <- c(
    nl(glue("gpoly <- dat$grid[{i}, ]")), 
    nl(glue("gname <- gpoly %>% pull(name)")), 
    nl(glue("os_url <- dat$tms %>% filter(name == gname & season == 'OS') ", 
            "%>% pull(tms_url)")),
    nl(glue("gs_url <- dat$tms %>% filter(name == gname & season == 'GS') ",
            "%>% pull(tms_url)"))
  )
  for(k in cat_strings) cat(k, file = outfile, append = TRUE)
  cat(chunk_text[2], file = outfile, append = TRUE)
  cat("\n", file = outfile, append = TRUE)
  
  cat(nl(glue("## {hostname} cell {gname}")), 
      file = outfile, append = TRUE)
  cat(chunk_text[1], file = outfile, append = TRUE)
  cat(nl(glue(
    "display_imagery(gpoly, user_maps = NULL, os_url, gs_url, d$cats)")
  ), file = outfile, append = TRUE)
  cat(chunk_text[2], file = outfile, append = TRUE)
  
  # cat("---\n", file = outfile, append = TRUE)
  cat("\n", file = outfile, append = TRUE)
}

# render markdown, both html (for interactive viewing) and pdf (for annotating)
rmarkdown::render(outfile, output_file = gsub(".Rmd", ".html", outfile))


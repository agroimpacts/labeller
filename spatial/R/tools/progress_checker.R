#! /usr/bin/Rscript
# 
suppressMessages(library(dplyr))
suppressMessages(library(tidyr))

args <- commandArgs(TRUE)
instance <- args[1]
password <- args[2]
lastdate <- as.Date(args[3], "%Y-%m-%d")
if(length(args) == 4) {
  runno <- as.numeric(args[3])
} else if(length(args) == 3) {
  runno <- "max"
} 
# lastdate <- "2020-05-12"
# id_filter <- c(1, 23, 25, 27, 45, 90, 91, 92, 93, 107, 115, 121)

# instance <- "labeller1"
dbase <- "Africa"
host <- paste0(instance, ".crowdmapper.org")
upw <- list("user" = "postgis", "password" = password)
con <- DBI::dbConnect(RPostgreSQL::PostgreSQL(), host = host, 
                      dbname = "Africa", user = upw$user, 
                      password = upw$password)
# View(tbl(con, "iteration_metrics") %>% collect())
id_filter <- tbl(con, "worker_data") %>% select(worker_id, last_time) %>% 
  filter(last_time > lastdate) %>% pull(worker_id)

# select data
max_assign <- tbl(con, "configuration") %>% 
  filter(key == "Hit_MaxAssignmentsF") %>% select(value) %>% collect() %>% 
  pull() %>% as.numeric(.)
# parameter for maxrun if that is the default
maxrun <- tbl(con, "incoming_names") %>% select(run) %>% 
  summarize(max(run, na.rm = TRUE)) %>% pull()
current_names <- tbl(con, "incoming_names") %>% 
  filter(run == !!ifelse(runno == "max", maxrun, runno)) %>% 
  filter(iteration == max(iteration, na.rm = TRUE)) %>% pull(name)
# current_names <- tbl(con, "incoming_names") %>% 
#   filter(iteration == max(iteration, na.rm = TRUE)) %>% pull(name)
hits <- tbl(con, "hit_data") %>% 
  left_join(., tbl(con, "kml_data"), by = "name") %>% 
  filter(name %in% current_names) %>% 
  left_join(., tbl(con, "assignment_data"), by = "hit_id") %>% 
  full_join(., tbl(con, "users"), by = c("worker_id" = "id")) %>% 
  select(name, worker_id, assignment_id, mapped_count, status, 
         hit_id, max_assignments, mappers_needed, kml_type, first_name, 
         last_name) %>%
  collect()

# All F assignments remaining in current iteration (mapped_count < max F count)
# Also F sites that have not yet had any assignments
fkml_remain <- tbl(con, "kml_data") %>% 
  filter(kml_type == "F" & mapped_count < max_assign) %>% 
  collect()
hit_names <- hits %>% distinct(name) %>% drop_na %>% pull
if(nrow(fkml_remain) > 0) {
  assign_remain <- fkml_remain %>% 
    summarise(sum(max_assign - mapped_count, na.rm = TRUE)) %>% pull()
  notyet_assigned <- fkml_remain %>% 
    filter(mapped_count == 0 & !name %in% hit_names) %>%
    distinct(name) %>% nrow
} else {
  assign_remain <- 0
  notyet_assigned <- 0 
}

# workers
workers <- hits %>% distinct(worker_id, first_name, last_name) %>% drop_na %>%  
  mutate(Name = paste(substr(first_name, 1, 1), last_name)) %>% 
  select(worker_id, Name) %>% arrange(worker_id) %>%
  filter(worker_id %in% id_filter)

# calculate hit assignments and per worker assignment status
mysum <- function(x) sum(x, na.rm = TRUE)
hit_status <- hits %>% group_by(hit_id, worker_id) %>%
  count(status) %>% spread(key = "status", value = "n") %>% 
  select(names(.)[-length(names(.))]) %>% ungroup
assn_status <- hit_status %>% select(-hit_id) %>% group_by(worker_id) %>% 
  summarize_all(mysum) %>% filter(worker_id %in% workers$worker_id) %>% drop_na

# count assignable hits
assignable <- lapply(workers$worker_id, function(x) {  # x <- 120
  unassignable <- hit_status %>% group_by(hit_id) %>% count() %>% 
    filter(n == 4) %>% pull(hit_id)
  mapped <- hit_status %>% filter(worker_id == x) %>% pull(hit_id)
  assignable_hits <- hit_status %>% 
    filter(!hit_id %in% c(unassignable, mapped)) %>% drop_na(hit_id) %>% 
    distinct(hit_id) %>% count %>% pull
  tibble(worker_id = x, Assignable = assignable_hits + notyet_assigned)
  # tibble(worker_id = x, Assignable = assignable_hits)
}) %>% do.call(rbind, .) %>% arrange(worker_id)

# report out 
cat("\n")
left_join(assn_status %>% drop_na, assignable, by = "worker_id") %>% 
  left_join(., workers) %>% select(worker_id, Name, !!names(.))
cat(paste(assign_remain, "assignments remain in total"))
cat("\n\n")

a <- DBI::dbDisconnect(con)
a <- lapply(DBI::dbListConnections(RPostgreSQL::PostgreSQL()),DBI::dbDisconnect)
rm(list = ls())
  
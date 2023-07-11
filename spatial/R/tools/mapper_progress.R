#! /usr/bin/Rscript
# diagnostic plots for worker assignment progress and accuracy
suppressMessages(library(rmapaccuracy))
suppressMessages(library(dplyr))
suppressMessages(library(sf))
# suppressMessages(library(data.table))
suppressMessages(library(ggplot2))
suppressMessages(library(grid))
suppressMessages(library(gridExtra))
suppressMessages(library(cowplot))

# arguments
args <- commandArgs(TRUE)
instance <- args[1]
password <- args[2]
if(length(args) == 2) {
  worker_min <- 0   # lowest worker_id
  run <- "max"
} else if(length(args) == 3) {
  worker_min <- as.numeric(args[3])
  runno <- "max"
} else if(length(args) == 4) {
  runno <- as.numeric(args[4])
}
# instance <- "labeller"
widl <- 60

# host <- paste0(instance, ".crowdmapper.org")
# # coninfo <- mapper_connect(host = host, user = "postgis")
# con <- coninfo$con
# # con <- DBI::dbConnect(RPostgreSQL::PostgreSQL(), host = host, 
# #                       dbname = "Africa", user = "mapper", 
# #                       password = dinfo$password)$con
dbase <- "Africa"
host <- paste0(instance, ".crowdmapper.org")
upw <- list("user" = "postgis", "password" = password)
con <- DBI::dbConnect(RPostgreSQL::PostgreSQL(), host = host, 
                      dbname = "Africa", user = upw$user, 
                      password = upw$password)


# time stamp for plots
tstamp <- format(Sys.time(), "%Y-%m-%d_%H%M%S")
fig_path <- here::here("spatial/notebooks/figures/mappers/diagnostics")
if(!dir.exists(fig_path)) dir.create(fig_path)

# read in data
assignments <- tbl(con, "assignment_data") %>%
  filter(!is.null(completion_time)) %>% collect()
hits <- tbl(con, "hit_data") %>% collect()
kml_data <- tbl(con, "kml_data") %>% collect()

maxrun <- tbl(con, "incoming_names") %>% select(run) %>% 
  summarize(max(run, na.rm = TRUE)) %>% pull()
incoming_names <- tbl(con, "incoming_names") %>% 
  filter(run == !!ifelse(runno == "max", maxrun, runno)) %>% collect()
which_iter <- max(incoming_names$iteration)  # which iteration are we on

assign <- assignments %>%  # merge assignments
  left_join(., hits, by = "hit_id") %>% full_join(., kml_data, by = "name") %>% 
  arrange(desc(completion_time)) #%>% data.table(.)
ct <- kml_data %>% filter(kml_type == "F") %>% count(.) %>% pull()
i_ct <- incoming_names %>% filter(iteration == which_iter) %>% count()

# plot mapped count
p1 <- kml_data %>% filter(kml_type == "F") %>% group_by(mapped_count) %>% 
  count() %>%
  ggplot(., aes(factor(mapped_count), n, fill = factor(mapped_count))) + 
  geom_col() + xlab("Mapped count") + scale_fill_brewer() + ylim(0, ct) +
  labs(fill = "Count") + ggtitle("Overall Progress") + 
  theme(axis.text = element_text(size = 12), #legend.position = "none",
        plot.title = element_text(hjust = 0.5, size = 12), 
        axis.title = element_text(size = rel(1.8)))

p1a <- right_join(kml_data, incoming_names %>% filter(iteration == which_iter), 
          by = "name") %>% group_by(mapped_count) %>% count() %>%
  ggplot(., aes(factor(mapped_count), n, fill = factor(mapped_count))) + 
  geom_col() + xlab("Mapped count") + scale_fill_brewer() + ylim(0, i_ct$n) +
  labs(fill = "Count") + ggtitle(paste("Progress on Iteration", which_iter)) + 
  theme(axis.text = element_text(size = 12), 
        plot.title = element_text(hjust = 0.5, size = 12),
        axis.title = element_text(size = rel(1.8)))

# plot assignment status by worker
p2 <- assign %>% filter(kml_type == "F") %>% group_by(status, worker_id) %>% 
  filter(worker_id > worker_min) %>% 
  ggplot(.) + 
  geom_bar(aes(x = factor(worker_id), fill = status), position = "dodge") +
  xlab("Worker ID") + ylim(0, ct) + 
  theme(axis.text = element_text(size = 12), 
        axis.title = element_text(size = rel(1.8)))

# N sites mapped
# assign %>% filter(worker_id %in% 48:50) %>% 
wid <- assign %>% filter(!is.na(worker_id) & worker_id > worker_min) %>% 
  distinct(worker_id) %>% pull()
p3 <- assign %>% filter(worker_id %in% wid) %>% 
  filter(!status %in% c("Returned", "Abandoned")) %>% 
  group_by(kml_type, worker_id) %>% #distinct(name) %>% 
  ggplot(.) + 
  geom_bar(aes(x = factor(worker_id), fill = kml_type), position = "dodge") +
  xlab("Worker ID") + ylim(0, ct) + 
  labs(fill = "Map Type") + 
  theme(axis.text = element_text(size = 12), 
        axis.title = element_text(size = rel(1.8)))

# score box plots
mu_score <- assign %>% filter(worker_id %in% wid & kml_type == "Q") %>%
  filter(!status %in% c("Returned", "Abandoned")) %>% 
  group_by(worker_id) %>% summarize(mu = mean(score)) %>% 
  mutate(worker_id = factor(worker_id))
p4 <- assign %>% filter(worker_id %in% wid & kml_type == "Q") %>%
  filter(!status %in% c("Returned", "Abandoned")) %>% 
  mutate(worker_id = factor(worker_id)) %>% 
  ggplot(aes(x = worker_id, y = score, fill = worker_id)) + geom_boxplot() + 
  geom_point(aes(x = worker_id, y = mu), shape = 4, size = 2, data = mu_score) +
  geom_hline(yintercept = 0.4, colour = 'purple', lwd = 1) + 
  geom_hline(yintercept = 0.6, colour = 'blue2', lwd = 1) + 
  xlab("Worker ID") + ylim(0, 1) + 
  labs(fill = "Worker ID") + 
  theme(axis.text = element_text(size = 12), 
        axis.title = element_text(size = rel(1.8)))

# # score by day by worker
p5 <- assign %>% filter(worker_id %in% wid & kml_type == "Q") %>%
  filter(!status %in% c("Returned", "Abandoned")) %>%
  group_by(worker_id = factor(worker_id),
           day = lubridate::as_date(completion_time)) %>%
  # summarize(mu = mean(score), n = length(score)) %>%
  ggplot(.) +
  # geom_smooth(aes(x = day, y = mu, se = FALSE, weight = n), method='lm') +
  geom_smooth(aes(x = day, y = score, se = FALSE), method='lm') +
  geom_point(aes(x = day, y = score)) + ylim(0, 1) + 
  facet_wrap(~ worker_id, nrow = 2) + 
  theme(axis.text = element_text(size = 12),
        axis.text.x = element_text(angle = 90),
        axis.title = element_text(size = rel(1.8)))

png(paste0(fig_path, "/", instance, "_", "mapping_status_", tstamp, ".png"), 
    height = 900, width = 1100)
title1 <- textGrob(paste0("Instance: ", instance), 
                   gp = gpar(fontsize = 20,font = 8))
grid.arrange(grobs = list(p1, p1a, p2, p3, p4, p5), ncol = 2, size = 3, 
             top = title1)
dev.off()

a <- DBI::dbDisconnect(con)
rm(list = ls())


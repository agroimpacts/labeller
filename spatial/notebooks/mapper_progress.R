#! /usr/bin/Rscript
# diagnostic plots for worker assignment progress and accuracy
suppressMessages(library(rmapaccuracy))
suppressMessages(library(dplyr))
suppressMessages(library(sf))
suppressMessages(library(data.table))
suppressMessages(library(ggplot2))
suppressMessages(library(grid))
suppressMessages(library(gridExtra))

# arguments
args <- commandArgs(TRUE)
instance <- args[1]
if(length(args) == 1) {
  dbase <- "Africa"  # which database?
} else if(length(args) == 2) {
  dbase <- args[2]  # which database? Africa or AfricaSandbox
}
widl <- 60

host <- paste0(instance, ".crowdmapper.org")
coninfo <- mapper_connect(host)
afcon <- DBI::dbConnect(RPostgreSQL::PostgreSQL(), host = host, 
                        dbname = "Africa", user = coninfo$dinfo$user, 
                        password = coninfo$dinfo$password)
if(dbase == "Africa") con <- afcon
if(dbase == "AfricaSandbox") con <- coninfo$con

# time stamp for plots
tstamp <- format(Sys.time(), "%Y-%m-%d_%H%M%S")
fig_path <- "spatial/notebooks/figures/mappers/diagnostics"


# read in data
assignments <- tbl(con, "assignment_data") %>%
  filter(!is.null(completion_time)) %>% collect()
hits <- tbl(con, "hit_data") %>% collect()
kml_data <- tbl(con, "kml_data") %>% collect()
incoming_names <- tbl(con, "incoming_names") %>% collect()
which_iter <- max(incoming_names$iteration)  # which iteration are we on

assign <- assignments %>%  # merge assignments
  left_join(., hits, by = "hit_id") %>% full_join(., kml_data, by = "name") %>% 
  arrange(desc(completion_time)) %>% data.table(.)
ct <- kml_data %>% filter(kml_type == "F") %>% count(.) %>% pull()
i_ct <- incoming_names %>% filter(iteration == which_iter) %>% count()

# plot mapped count
p1 <- kml_data %>% filter(kml_type == "F") %>% group_by(mapped_count) %>% 
  count() %>%
  ggplot(., aes(factor(mapped_count), n, fill = factor(mapped_count))) + 
  geom_col() + xlab("Mapped count") + scale_fill_brewer() + ylim(0, ct) +
  labs(fill = "Count") + 
  ggtitle("Overall Progress") + 
  theme(axis.text = element_text(size = 12), #legend.position = "none",
        plot.title = element_text(hjust = 0.5, size = 12), 
        axis.title = element_text(size = rel(1.8)))

p1a <- right_join(kml_data, incoming_names %>% filter(iteration == which_iter), 
          by = "name") %>% group_by(mapped_count) %>% count() %>%
  ggplot(., aes(factor(mapped_count), n, fill = factor(mapped_count))) + 
  geom_col() + xlab("Mapped count") + scale_fill_brewer() + ylim(0, i_ct$n) +
  labs(fill = "Count") + 
  ggtitle(paste("Progress on Iteration", which_iter)) + 
  theme(axis.text = element_text(size = 12), 
        plot.title = element_text(hjust = 0.5, size = 12),
        axis.title = element_text(size = rel(1.8)))

# png(paste0(fig_path, "/", instance, "_mapped_count_", tstamp, ".png"), 
#     height = 500, width = 500)
# print(p)
# dev.off()

# plot assignment status by worker
p2 <- assign %>% filter(kml_type == "F") %>% group_by(status, worker_id) %>% 
  ggplot(.) + 
  geom_bar(aes(x = factor(worker_id), fill = status), position = "dodge") +
  xlab("Worker ID") + ylim(0, ct) + 
  theme(axis.text = element_text(size = 12), 
        axis.title = element_text(size = rel(1.8)))
# png(paste0(fig_path, "/", instance, "_", "status_by_worker_", tstamp,".png"), 
#     height = 500, width = 500)
# print(p)
# dev.off()

# plots
# assign %>% filter(worker_id %in% 48:50) %>% 
#   filter(!status %in% c("Returned", "Abandoned")) %>% 
#   group_by(kml_type, worker_id) %>% distinct(name) %>% count()

# N sites mapped
# assign %>% filter(worker_id %in% 48:50) %>% 
wid <- assign %>% filter(!is.na(worker_id) & worker_id > widl) %>% 
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
# png(paste0(fig_path, "/", instance, "_", "maps_per_worker_", tstamp, ".png"), 
#     height = 500, width = 500)
# print(p)
# dev.off()

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
# png(paste0(fig_path, "/", instance, "_", "worker_accuracy_", tstamp, ".png"), 
#     height = 500, width = 500)
# print(p)
# dev.off()

# # score by day by worker
p5 <- assign %>% filter(worker_id %in% wid[wid < 81] & kml_type == "Q") %>%
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
# png(paste0(fig_path, "/", instance, "_", "worker_accuracy_day_", tstamp, ".png"), height = 300, 
#     width = 500)
# print(p)
# dev.off()

png(paste0(fig_path, "/", instance, "_", "mapping_status_", tstamp, ".png"), 
    height = 900, width = 900)
title1 <- textGrob(paste0("Instance: ", instance), 
                   gp = gpar(fontsize = 20,font = 8))
grid.arrange(grobs = list(p1, p1a, p2, p3, p4, p5), ncol = 2, size = 3, 
             top = title1)
dev.off()

DBI::dbDisconnect(con)
DBI::dbDisconnect(afcon)
rm(list = ls())

# # number of distinct assignments per worker
# assign %>% filter(worker_id > 59) %>% 
#   filter(kml_type == "F") %>% group_by(name) %>% count() %>% 
#   filter(n > 1) %>% nrow()
# assign %>% filter(kml_type == "F") %>% group_by(name, worker_id) %>% count() %>% 
#   filter(n > 1) %>% group_by(worker_id) %>% count()
# 
# assign %>% filter(worker_id == 48 & name == "GH0009542") %>% 
#   select(c(1:4, 6, 9))
# assign %>% filter(worker_id == 49 & name == "GH0022229") %>% 
#   select(c(1:4, 6, 9))
# assign %>% filter(worker_id == 50 & name == "GH0086596") %>% 
#   select(c(1:4, 6, 9))

# assign %>% filter(worker_id %in% c("48", "49", "50") & kml_type == "F")  %>% 
#   mutate(day = lubridate::day(completion_time)) %>% 
#   group_by(worker_id, day) %>% count() %>% 
#   ggplot(.) + geom_point(aes(day, n, colour = factor(worker_id)))

# assign %>% group_by(worker_id)

# # score over time
# assign %>% filter(worker_id == 62 & kml_type == "Q") %>% 
#   ggplot(.) + geom_point(aes(x = completion_time, y = score))
# 
# assign %>% filter(kml_type == "F") %>% 
#   group_by(worker_id) %>% count(.)
# kml_data %>% filter(kml_type == "F") %>% count(.)
# 
# assign %>% filter(worker_id == 50)  %>% filter(kml_type == "Q") %>% pull(score)
# assign %>% filter(kml_type == "Q" & is.na(score))


# 
# 
# # how many mappable hits are left to do 
# which(!(kml_data %>% filter(kml_type == "F") %>% distinct(name) %>% 
#     pull(name)) %in% 
#   (assign %>% filter(worker_id %in% 50 & kml_type == "F") %>% 
#      distinct(name) %>% pull(name))) 
# 
# kml_names <- (kml_data %>% filter(kml_type == "F") %>% distinct(name) %>% 
#                 pull(name))
# kml_names[!kml_names %in% 
#             (assign %>% filter(worker_id %in% 49 & kml_type == "F") 
#              %>% distinct(name) %>% pull(name))]
# 
# # !(hits %>% filter(max_assignments == 2) %>% pull(name)) %in% 
# #   (assign %>% filter(worker_id %in% 48 & kml_type == "F") 
# #    %>% distinct(name) %>% pull(name))
#   
# # hits %>% left_join(., kml_data, by = "name") %>% group_by(kml_type) %>% 
# #   count(mapped_count)
# 
# kml_data %>% filter(kml_type == "F") %>% group_by(mapped_count) %>% 
#   count()
# 
# hits %>% filter(name %in%  
#                   (kml_data %>% filter(kml_type == "F") %>% pull(name))) %>% 
#   group_by(max_assignments) %>% count()
# 
# 
# # kml_data %>% filter(name == "ZA0317782")
# scenes <- tbl(con, "scenes_data") %>% collect()
# aoicsv <- fread("~/Desktop/probability/f_pool_ghana_aoi4_test_RA.csv")
# scenes %>% 
#   filter(global_row %in% unique(aoicsv$row) & 
#            global_col %in% unique(aoicsv$col)) %>% 
#   distinct(tms_url) %>% fwrite("~/Desktop/aoi_tms.csv")
#   
# tms <- "https://tiles.rasterfoundry.com/tiles/11dcf154-f6fb-4ed2-a5de-6cc73140c219/{z}/{x}/{y}/?mapToken=20aee214-28c9-4585-8ca8-b0b7434ff3d0"
# scenes %>% 
#   filter(cell_id %in% (scenes %>% filter(tms_url == tms) %>% pull(cell_id))) %>% 
#   filter(season == "OS") %>% distinct(tms_url) %>% pull()
# 
# # qnames <- kml_data %>% filter(kml_type == "Q") %>% pull(name)
# # qgrid_id <- tbl(con, "master_grid") %>% filter(name %in% qnames) %>% 
# #   select(id, name) %>% collect()
# # scenes %>% filter(cell_id %in% qgrid_id$id) %>% select(scene_id, tms_url) %>% 
# #   fwrite(., file = "spatial/data/reference/spatialcollective_q_tmsurl.csv")
# scenes %>% filter(cell_id %in% qgrid_id$id & season == "GS") %>% 
#   select(scene_id, tms_url)
# 
# 
# # assignments %>% filter(worker_id == 49) %>% 
# #   left_join(., hits, by = "hit_id") %>% left_join(., kml_data, by = "name") %>% 
# #   filter(kml_type == "F") %>% arrange(desc(completion_time))
# 
# fassign <- assignments %>% 
#   left_join(., hits, by = "hit_id") %>% left_join(., kml_data, by = "name") %>% 
#   filter(kml_type == "F") %>% arrange(desc(completion_time)) %>% data.table(.)
# 
# assign[worker_id == 48, .N, by = kml_type]
# assign[, .N, by = .(worker_id, kml_type)][order(-worker_id)]
# 
# # fassign[hit_id == unique(hit_id)[18], ]
# 
# # fnames_49 <- fassign[worker_id == 49, .N, by = name][, name]
# # fassign[(name %in% fnames_49) & worker_id == 50, ]
# # fnames_49 %in% fassign[is.na(delete_time), unique(name)]
# # fassign[(hit_id %in% !unique(hit_id)) & (worker_id != 50)]
# # fassign[, unique(hit_id)]
# # fassign[, 1:4, with = FALSE]
# # 
# # hits %>% filter(is.na(delete_time)) %>% group_by(name) %>% count()

library(dplyr)


params <- yaml::yaml.load_file("common/config.yaml")
dinfo <- params$labeller
# host <- "labellertrainsouthnl.crowdmapper.org"
host_root <- "labellertc"
host <- glue::glue("{host_root}.crowdmapper.org")
# host <- "ec2-3-236-28-176.compute-1.amazonaws.com"

con <- DBI::dbConnect(RPostgreSQL::PostgreSQL(), host = host, 
                      dbname = "Africa", user = dinfo$db_username, 
                      password = dinfo$db_password)

invites <- tbl(con, "user_invites") %>% collect()

tokens <- invites %>% filter(!is.na(token)) %>% dplyr::select(email, token)
# URL <- glue::glue("https://{host}/", 
URL <- glue::glue("https://{host_root}.crowdmapper.org/api/",
                  "webapp/user/register?token=")

tokens %>% mutate(invite = paste(URL, token)) %>% 
  dplyr::select(email, invite) %>% 
  readr::write_csv(
    file = here::here(glue::glue("spatial/notebooks/{host_root}_invites.csv"))
  )


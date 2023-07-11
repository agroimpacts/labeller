#' Find correct root path and database name 
#' @return Root path and database name in named vector 
#' @note The function arguments currently default to Africa*, so expect 
#' these to change with project upgrades
#' @export
get_db_name <- function() {
  info <- Sys.info()
  euser <- unname(info["effective_user"])
  server_name <- info["nodename"]
  if(euser == "mapper") {
  #if(euser == "coloury") { # for debug
    sandbox <- FALSE
    uname <- "mapper"
  } else {
    sandbox <- TRUE
    uname <- euser
    # server_name <- "mapper.crowdmapper.org"
    serv_spl <- strsplit(server_name, "\\.")[[1]]
    server_name <- paste0(serv_spl[[1]], "-sandbox.", 
                          paste0(serv_spl[2:length(serv_spl)], collapse = "."))
  }
  
  # Project root
  home <- Sys.getenv("HOME")
  if(!home %in% c("/home/mapper", "/home/sandbox")) {
    cwd <- strsplit(getwd(), "/")[[1]]
    project_root <- paste(cwd[1:grep("labeller", cwd)], collapse = "/")
  } else {
    project_root <- file.path(home, "labeller")  
  }
  
  
  # Parse config
  common_path <- file.path(project_root, "common")
  params <- yaml::yaml.load_file(file.path(common_path, 'config.yaml'))

  # DB Names
  if(sandbox == TRUE) {
    db_name <- params$labeller$db_sandbox_name
  } else {
    db_name <- params$labeller$db_production_name
  }
  
  # # credentials
  # params <- yaml::yaml.load_file(file.path(project.root, 'common/config.yaml'))
  olist <- list("db_name" = db_name, "project_root" = project_root,
                "server_name" = server_name,
                "user" = params$labeller$db_username, 
                "password" = params$labeller$db_password)
  return(olist)
}

#' Find correct root path and database name 
#' @param host NULL is running on crowdmapper, else crowdmapper.org for remote
#' @param user NULL (effective user) or override with manually supplied name
#' @return Database connection, root path, and database name in list
#' @details If you want to log into, say, the mapper user on a running instance
#' from a local machine, set the user argument to "mapper".
#' @note The function arguments currently default to SouthAfrica*, so expect 
#' these to change with project upgrades. 
#' @import DBI
#' @export
mapper_connect <- function(host = NULL, user = NULL) {
  dinfo <- get_db_name()  # pull working environment
  # common_path <- file.path(dinfo["project.root"], "common")
  # params <- yaml::yaml.load_file(file.path(common_path, 'config.yaml'))
  if(!is.null(user)) {
    if(user == "mapper") dinfo$db_name <- "Africa"
  }
  
  # Paths and connections
  con <- DBI::dbConnect(RPostgreSQL::PostgreSQL(), host = host, 
                        dbname = dinfo$db_name,   
                        user = dinfo$user, 
                        password = dinfo$password)
  return(list("con" = con, "dinfo" = dinfo))
}

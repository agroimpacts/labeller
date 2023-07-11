#' Control the output of label maps, risk maps, and heat maps 
#' @param kmlid 
#' @param kml.usage the use of kml, could be 'train, 'validate' or 'holdout';
#' This parameter will determine the directory of S3 folder to store consensus 
#' maps.
#' @param riskthres the threshold to select 'risk' pixels
#' @param host NULL or "crowdmapper.org", if testing from remote location
#' @param mode the method for generating consensus: 'consensus', 'high' or 'low'.
#' 'high' or 'low' means that using the highest or the lowest score worker maps 
#' @param qsite Q ir F site?  Default is FALSE
#' @return Sticks conflict/risk percentage pixels into database (kml_data) and
#' writes rasterized labels to S3 bucket.
#' @importFrom raster ncell
#' @export
consensus_map_creation <- function(kmlid, kml.usage, mode, output.riskmap, diam, 
                                   host, qsite = FALSE) {
  
  coninfo <- mapper_connect(host = host)
  
  # read config.yaml
  common_path <- file.path(coninfo$dinfo["project_root"], "common")
  params <- yaml::yaml.load_file(file.path(common_path, 'config.yaml'))
  # prjstr <- as.character(tbl(coninfo$con, "spatial_ref_sys") %>% 
  #                          filter(srid == prjsrid) %>% 
  #                          select(proj4text) %>% collect())
  gcsstr <- "+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"
  
  # query hitid
  # hit.sql <- paste0("select hit_id from hit_data where name = '", kmlid, "'")
  # hitid <- (DBI::dbGetQuery(coninfo$con, hit.sql))$hit_id
  
  # query mtype
  # mtype.sql <- paste0("select kml_type from kml_data where name = '",kmlid, "'")
  # mtype <- (DBI::dbGetQuery(coninfo$con, mtype.sql))$kml_type
  
  # query mappedcount
  mappedcount.sql <- paste0("select mapped_count from kml_data where name = '",
                            kmlid, "'")
  mappedcount <- as.numeric(
    (DBI::dbGetQuery(coninfo$con, mappedcount.sql))$mapped_count
  )

  # query assignmentid flagged as 'approved'
  assignment.sql <- paste0("select assignment_id from assignment_data",
                           " INNER JOIN hit_data USING (hit_id)",
                           " where name ='", kmlid, 
                           "' and status = 'Approved'", 
                           " order by assignment_id")  
  
  assignmentid <- (DBI::dbGetQuery(coninfo$con, assignment.sql))$assignment_id
                           
  
  assignmentid <- unlist(assignmentid)
  
  # read grid polygon
  xy.tabs <- data.table(tbl(coninfo$con, "master_grid") %>% 
                          filter(name == kmlid) %>% 
                          dplyr::select(x, y, name) %>% collect())
  # read grid geometry, and keep gcs
  grid.poly <- point_to_gridpoly(xy = xy.tabs, w = diam, NewCRSobj = gcsstr, 
                                 OldCRSobj = gcsstr)
  grid.poly <- st_geometry(grid.poly)  # retain geometry only
  
  # lklh_field: p(user=field|groundtruth=field)
  # lklh_nofield: p(user=no field|groundtruth=no field)
  # Read user fields, field and no field likelihood from database into sf object
  bayes.polys <- lapply(assignmentid, function(x) {
    # workerid
    workerid.sql <- paste0("select worker_id from assignment_data", 
                           " where assignment_id ='", x, 
                           "' order by assignment_id")
    workerid <- (DBI::dbGetQuery(coninfo$con, workerid.sql))$worker_id
      
    # read all scored assignments including 'Approved' and 'Rejected'
    # for calculating history field and no field likelihood of worker i
    
    ############################# assignment history #########################
    histassignid.sql <- paste0("select assignment_id from", 
                               " assignment_data where worker_id = '", 
                               workerid, "'",
                               " and (status = 'Approved' OR status = ",
                               "'Rejected') and score IS NOT NULL")
    historyassignmentid <- suppressWarnings(
      DBI::dbGetQuery(coninfo$con, histassignid.sql)$assignment_id)
    
    if (is.null(historyassignmentid)){
      userhistories <- NA
    } else {
      # query all valid likelihood and score from history assignments
      userhistories <- lapply(c(1:length(historyassignmentid)), function(x){
        
        # query likelihood and scores
        likelihood.sql <- paste0("select new_score, field_skill, nofield_skill",
                                 " from accuracy_data  where assignment_id='", 
                                 historyassignmentid[x], "'") 
        measurements <- suppressWarnings(DBI::dbGetQuery(coninfo$con, 
                                                         likelihood.sql))
        
        # field_skill and nofield_skill are alias of max.field.lklh 
        # and max.nofield.lklh 
        if (nrow(measurements) != 0) {
          c('ml.field' = as.numeric(measurements$field_skill), 
            'ml.nofield' = as.numeric(measurements$nofield_skill), 
            'score.hist' = as.numeric(measurements$new_score))
        } else {
          NA
        }
      })
      
    }
    
    #########################qual assignment history #########################
    qual_histassignid.sql <- paste0(
      "select assignment_id from qual_assignment_data where worker_id = '", 
      workerid, "' and (status = 'Approved' OR status = ",
      "'Rejected') and score IS NOT NULL"
    )
    qual_historyassignmentid <- suppressWarnings(
      DBI::dbGetQuery(coninfo$con, qual_histassignid.sql)$assignment_id)
    
    # check if any qual history assignmentid
    if (is.null(qual_historyassignmentid)) {
      qual_userhistories <- NA
    } else {
        # read all valid likelihood and score from history qual_assignments
       qual_userhistories <- lapply(c(1:length(qual_historyassignmentid)), 
                                    function(x) {
            try.sql <- paste0(
              "select try from qual_accuracy_data where assignment_id='",
              qual_historyassignmentid[x], "'"
            )
            trys <- suppressWarnings(DBI::dbGetQuery(coninfo$con, try.sql))
              
            if (nrow(trys) == 0) {
              likelihood.sql <- paste0(
                "select new_score, field_skill, nofield_skill",
                " from qual_accuracy_data where assignment_id='",
                qual_historyassignmentid[x], "'"
              ) 
            } else {
              # query likelihood and scores
              likelihood.sql <- paste0(
                "select new_score, field_skill, nofield_skill",
                " from qual_accuracy_data where assignment_id='",
                qual_historyassignmentid[x], "' and try='", max(trys),"'"
              ) 
            }                            
            measurements <- suppressWarnings(DBI::dbGetQuery(coninfo$con, 
                                                             likelihood.sql))
              
            # field_skill and nofield_skill are alias of max.field.lklh 
            # and max.nofield.lklh 
            if (nrow(measurements) != 0){
              c('ml.field' = as.numeric(measurements$field_skill), 
                'ml.nofield' = as.numeric(measurements$nofield_skill), 
                'score.hist' = as.numeric(measurements$new_score))
            }
            else{
                NA
            }
      })
    }
    
    
    ##########################################################################
    # combine regular assignment hisotry for the user and delete NA values
    if(length(userhistories[!is.na(userhistories)]) != 0) {
      userhistories <- data.frame(
        do.call(rbind, userhistories[!is.na(userhistories)])
      )
    } else {
      userhistories <- data.frame(
        'ml.field' = NA, 'ml.nofield' = NA, 'score.hist' = NA
      )
    }
    
    # combine qual assignment hisotry for the user
    if(length(qual_userhistories[!is.na(qual_userhistories)]) != 0) {
      qual_userhistories <- data.frame(
        do.call(rbind, qual_userhistories[!is.na(qual_userhistories)])
      )
    } else {
      qual_userhistories <- data.frame('ml.field' = NA, 
                                       'ml.nofield' = NA, 
                                       'score.hist' = NA)
    }
    
     
    # calculating mean max likelihood and score from qual and non-qual history
    ml.field <- mean(rbind(userhistories, qual_userhistories)$ml.field, 
                     na.rm = TRUE)
    ml.nofield <- mean(rbind(userhistories, qual_userhistories)$ml.nofield, 
                       na.rm = TRUE)
    score.hist <- mean(rbind(userhistories, qual_userhistories)$score.hist, 
                       na.rm = TRUE)

    if(params$labeller$mapping_category1 == 'field') {
        # read'field-group' polygons
        user.sql <- paste0("select name, geom_clean ",
                           "FROM user_maps INNER JOIN categories ", 
                           "USING (category) where assignment_id='",  
                           x, "' ", "AND categ_group ='field'")
        user.polys <- suppressWarnings(
          DBI::dbGetQuery(coninfo$con, gsub(", geom_clean", "", user.sql))
        )
        
        # read user polygons for the unsure category 1
        user.sql.unsure <- paste0("SELECT name, geom_clean FROM ",
                                  "user_maps where assignment_id = ", "'", x, 
                                  "' AND category='unsure1' order by name")
        
        user.polys.unsure <- suppressWarnings(
          DBI::dbGetQuery(coninfo$con, 
                          gsub(", geom_clean", "", user.sql.unsure))
          )
        
        user.hasfields <- ifelse(nrow(user.polys) > 0, "Y", "N")
        user.unsure.hasfields <- ifelse(nrow(user.polys.unsure) > 0, "Y", "N")
        
        # if user maps have field polygons
        if(user.hasfields == "Y") {
          user.polys <- suppressWarnings(st_read(coninfo$con, query = user.sql))
          
          # select only polygons
          user.polys <- user.polys %>% filter(st_is(. , "POLYGON"))
          
          # union user polygons
          user.poly <- suppressWarnings(suppressMessages(
            st_buffer(st_buffer(user.polys, 0.0001), -0.0001)))
          
          user.poly <- suppressWarnings(suppressMessages(st_buffer(
            st_buffer(st_union(user.poly), 0.0001), -0.0001)))
          
          # if for F sites, we need to first intersection user maps by grid 
          # to retain those within-grid parts for calculation
          if(qsite == FALSE) {
            user.poly <- suppressWarnings(
              suppressMessages(st_intersection(user.poly, grid.poly))
            )
            user.poly <- suppressWarnings(
              suppressMessages(st_buffer(user.poly, 0))
            )
          }
          
          if(length(user.poly) == 0){
            geometry.user = st_polygon()
          } else {
            geometry.user = user.poly
          }
        }
        else {
          # if users do not map field, set geometry as empty polygon
          geometry.user = st_polygon()
        }  
        
        # if user unsure maps have field polygons
        if(user.unsure.hasfields == "Y") {
          user.polys.unsure <- suppressWarnings(
            st_read(coninfo$con, query = user.sql.unsure)
          )
          
          # select only polygons
          user.polys.unsure <- user.polys.unsure %>% 
            filter(st_is(. , "POLYGON"))
          
          # union user unsure polygons
          user.poly.unsure <- suppressWarnings(suppressMessages(
            st_buffer(st_buffer(user.polys.unsure, 0.0001), -0.0001)))
          
          user.poly.unsure <- suppressWarnings(suppressMessages(
            st_buffer(st_buffer(st_union(user.poly.unsure), 0.0001), -0.0001)))
          
          # if for F sites, we need to first intersection user maps by grid 
          # to remain those within-grid parts for calculation
          if(qsite == FALSE) {
            user.poly.unsure <- suppressWarnings(
              suppressMessages(st_intersection(user.poly.unsure, grid.poly))
            )
            user.poly.unsure <- suppressWarnings(
              suppressMessages(st_buffer(user.poly.unsure, 0))
            )
          }
          if(length(user.poly.unsure) == 0) {
            geometry.user.unsure = st_polygon()
          } else {
            geometry.user.unsure = user.poly.unsure
          }
          
        } else {
          # if users do not map field, set geometry as empty polygon
          geometry.user.unsure = st_polygon()
        } 
    } else { # for specific mapping crop type such as tree crops 
      user.sql <- paste0("select name, geom_clean ",
                         "FROM user_maps WHERE (assignment_id='", 
                         x, "') AND (category = '",
                         params$labeller$mapping_category1,"' OR category = '",
                         params$labeller$mapping_category2,"' OR category = '",
                         params$labeller$mapping_category3,"')")
      user.polys <- suppressWarnings(DBI::dbGetQuery(coninfo$con, 
                                                     gsub(", geom_clean", 
                                                          "", user.sql)))
      user.hasfields <- ifelse(nrow(user.polys) > 0, "Y", "N")
      if(user.hasfields == "Y") {
        user.polys <- suppressWarnings(st_read(coninfo$con, query = user.sql))
        
        # select only polygons
        user.polys <- user.polys %>% filter(st_is(. , "POLYGON"))
        
        # union user polygons
        user.poly <- suppressWarnings(suppressMessages(
          st_buffer(st_buffer(user.polys, 0.0001), -0.0001)))
        
        user.poly <- suppressWarnings(suppressMessages(
          st_buffer(st_buffer(st_union(user.poly), 0.0001), -0.0001)))
        
        # if for F sites, we need to first intersection user maps by grid 
        # to retain those within-grid parts for calculation
        if(qsite == FALSE) {
          user.poly <- suppressWarnings(
            suppressMessages(st_intersection(user.poly, grid.poly))
          )
          user.poly <- suppressWarnings(
            suppressMessages(st_buffer(user.poly, 0))
          )
        }
        
        if(length(user.poly) == 0){
          geometry.user = st_polygon()
        }else{
          geometry.user = user.poly
        }
      }
      else {
        # if users do not map field, set geometry as empty polygon
        geometry.user = st_polygon()
      }
      geometry.user.unsure = st_polygon()
    }
    
   
    
    # we give 0.5 as posterior probability to unsure, meaning that the user
    # thinks it has only 50% to be a field
    # bayes.poly will consist two sf rows, the first is that the surely-labeled
    # fields, and the second is that unsure fields
    bayes.poly <- st_sf('posterior.field' = c(1, 0.5), 
                        'max.field.lklh' = c(ml.field, ml.field), 
                        'max.nofield.lklh' = c(ml.nofield, ml.nofield) , 
                        'prior'= c(score.hist, score.hist), 
                        geometry = c(st_sfc(geometry.user), 
                                     st_sfc(geometry.user.unsure)))
    
    # set crs
    st_crs(bayes.poly) <- gcsstr
    
    bayes.poly
   
  })
  
  bayes.polys <- suppressWarnings(do.call(rbind, bayes.polys))
  
  if ((nrow(bayes.polys) == 0) || (is.null(bayes.polys) == TRUE)) {
    stop("There is no any valid assignment for creating consensus maps")
  }
  
  # count the number of user maps that has field polygons
  count.hasuserpolymap <- length(
    which(st_is_empty(bayes.polys[, "geometry"]) == FALSE)
  )
  
  # if no any user map polygons for this grid or if for qsite, 
  # use the grid extent as the raster extent
  if ((qsite == FALSE) || (count.hasuserpolymap == 0)) {
    rasterextent <- grid.poly
  } else {
    # for Q sites, use the maximum combined boundary of all polygons and master 
    # grid as the raster extent
    bb.grid <- st_bbox(grid.poly)
    bb.polys <- st_bbox(st_union(bayes.polys))
    new.bbbox <- st_bbox(c(xmin = min(bb.polys$xmin,bb.grid$xmin), 
                           xmax = max(bb.polys$xmax,bb.grid$xmax), 
                           ymax = max(bb.polys$ymax,bb.grid$ymax), 
                           ymin = min(bb.polys$ymin,bb.grid$ymin)), 
                         crs = gcsstr)
    rasterextent <- st_as_sfc(new.bbbox)
  }
  
  # Threshold here for determine field pixels in heat maps (not threshold for 
  # risk pixels )
  
  if(mode == 'high') {
    tmp <- bayes.polys %>% 
      filter(posterior.field == 1) %>% 
      na.omit()
    bayes.polys <- tmp %>% filter(prior==max(tmp$prior))
  } else if (mode == 'low') {
    tmp <- bayes.polys %>% 
      filter(posterior.field == 1) %>% 
      na.omit()
    bayes.polys <- tmp %>% filter(prior==min(tmp$prior))
  }
    
  # using 0.50000001 can avoid identifying unsure polygon when only single user
  # or using mode to generate consensus maps
  bayesoutput <- bayes_model_averaging(
    bayes.polys = bayes.polys, rasterextent = rasterextent, 
    threshold = 0.5000001
  )
  
  # call risky pixel threshold from configuration table
  riskthreshold.sql <- paste0("SELECT value ",
                              "FROM configuration WHERE ",
                              "key='Consensus_RiskyPixelThreshold'")
  
  riskpixelthres <- as.numeric(dbFetch(
    DBI::dbSendQuery(coninfo$con, riskthreshold.sql))$value)
  
  riskpixelpercentage <- round(
    ncell(bayesoutput$riskmap[bayesoutput$riskmap > riskpixelthres]) /
      (nrow(bayesoutput$riskmap) * ncol(bayesoutput$riskmap)), 2
  )
  
  # insert risk pixel percentage into kml_data table
  risk.sql <- paste0("update kml_data set consensus_conflict = '", 
                     riskpixelpercentage, "' where name = '", kmlid, "'")
  dbSendQuery(coninfo$con, risk.sql) 
  
  ###################### S3 bucket output ###############
  xy_tabs <- tbl(coninfo$con, "master_grid") %>% 
    filter(name == kmlid) %>% 
    dplyr::select(x, y) %>% collect()
  
  
  rowcol <- rowcol_from_xy(xy_tabs$x, xy_tabs$y, offset = -1)
  
  S3BucketDir.sql <- paste0("SELECT value FROM configuration WHERE ",
                            "key='S3BucketDir'")

  bucketname <- dbFetch(DBI::dbSendQuery(coninfo$con, S3BucketDir.sql))$value
  # read  user polygons that are not unsure
  # provider.sql <- paste0("SELECT provider FROM",
  #                    " scene_data WHERE name = '", kmlid, "'")
  # 
  # # provide could be 'planet' or 'wv2'
  # provider <- suppressWarnings(DBI::dbGetQuery(coninfo$con, 
  #                                              provider.sql))
  
  # set provider as planet, and will change once provider table is complete
  # provider <- "planet"
  
  #bucketname <- unlist(strsplit(s3.dst.train, '/'))[1]
  
  # s3.dst <- paste0(":activemapper/sources/train/")  
  s3.filename <- paste0(kmlid, '_', rowcol[1, 'col'], '_', rowcol[1, 'row'])
  s3_upload(coninfo$dinfo["project_root"], bucketname, 
            bayesoutput$labelmap, 
            params$labeller$consensus_directory,
            s3.filename)
  
  if(output.riskmap == TRUE) { 
    s3.filename <- paste(kmlid + "_risk")
    s3_upload(coninfo$dinfo["project_root"], bucketname, 
              bayesoutput$riskmap, 
              params$labeller$consensus_riskmap_dir,
              s3.filename)
  }
   
  #######################################################
  
  garbage <- DBI::dbDisconnect(coninfo$con)
  
  cat(riskpixelpercentage)
}
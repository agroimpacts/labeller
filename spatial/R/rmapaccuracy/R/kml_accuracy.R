#' Main function for running worker accuracy assessment
#' @param mtype "qa" or "tr" for qaqc or training types
#' @param diam diameter for master grids
#' @param prjsrid EPSG identifier for projected coordinate system
#' @param count.acc.wt Weighting given to field count error
#' @param in.acc.wt Weighting for in grid map discrepancy
#' @param out.acc.wt Weighting for out of grid map discrepancy
#' @param new.in.acc.wt Weighting for in grid map in new score
#' @param new.out.acc.wt Weighting for out of grid map in new score
#' @param frag.acc.wt Weighting for fragmentation accuracy
#' @param edge.acc.wt Weighting for edge accuracy
#' @param edge.buf buffer for edge accuracy
#' @param acc.switch in grid error metric: 1 = overall accuracy; 2 = TSS
#' @param comments For testing, can turn off (F) or on (T) print statements
#' @param write.acc.db Write error metrics into accuracy_data table ("T" or "F") 
#' @param draw.maps Draw maps showing output error components ("T" or "F") 
#' @param pngout Write maps to png file, TRUE (default) or FALSE (to screen)
#' @param test "Y" or "N" for offline testing mode (see Details)
#' @param host NULL or "crowdmapper.org", if testing from remote location
#' @details For the test argument, it can be set to "Y" if one wants to test 
#' only a single kmlid. In this case, the function code will pull the 
#' entire assignment_data and hit_data tables from the database to find the 
#' right assignment ids to test. This option must be set to "N" when in  
#' production. test.root allows one to simply the run the function to see if it 
#' is located in the correct working environment.
#' @import sf
#' @import dplyr
#' @importFrom data.table data.table 
#' @export
kml_accuracy <- function(mtype, diam, prjsrid, kmlid, assignmentid, tryid,
                         count.acc.wt, in.acc.wt, out.acc.wt, new.in.acc.wt, 
                         new.out.acc.wt, frag.acc.wt, edge.acc.wt, cate.acc.wt, 
                         edge.buf, acc.switch, comments, write.acc.db, 
                         draw.maps, pngout = TRUE, test, test.root, 
                         host = NULL) {
  
  ## Extract connections and reading in of spatial data
  # Paths and connections
  coninfo <- mapper_connect(host = host)
  
  prjstr <- as.character(tbl(coninfo$con, "spatial_ref_sys") %>% 
                           filter(srid == prjsrid) %>% 
                           dplyr::select(proj4text) %>% collect())
  
  gcsstr <- "+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"
    
  # Collect QAQC fields (if there are any; if not then "N" value will be 
  # returned). This should work for both training and test sites
  qaqc.sql <- paste0("SELECT gid, category, geom_clean FROM qaqcfields ",
                     "INNER JOIN categories USING (category) ",
                     "WHERE name=", "'", kmlid, "' AND categ_group ='field'")
  qaqc.polys <- DBI::dbGetQuery(coninfo$con, gsub(", geom_clean", "", qaqc.sql))
  qaqc.hasfields <- ifelse(nrow(qaqc.polys) > 0, "Y", "N") 
  if(qaqc.hasfields == "Y") {
    qaqc.polys <- suppressWarnings(st_read(coninfo$con, query = qaqc.sql))
    qaqc.polys <- st_transform(qaqc.polys, crs =  prjstr)
    qaqc.polys <- st_buffer(qaqc.polys, 0)
  } 

  # Read in 'field' polygons
  if(mtype == "tr") {  # Training case
    user.sql <- paste0("SELECT name, try, category, geom_clean ",
                       "FROM qual_user_maps INNER JOIN categories ", 
                       "USING (category) where assignment_id=",  "' ", 
                       assignmentid, "'", " AND try='",  tryid, "' ",
                       "AND categ_group ='field'")
  } else if(mtype == "qa") {  # Test case
    user.sql <- paste0("select name, category, geom_clean ",
                       "FROM user_maps INNER JOIN categories ", 
                       "USING (category) where assignment_id='",  
                       assignmentid, "' ",
                       "AND categ_group ='field'")
  }
  
  # test if user fields exist
  user.polys <- DBI::dbGetQuery(coninfo$con, gsub(", geom_clean", "", user.sql))
  user.hasfields <- ifelse(nrow(user.polys) > 0, "Y", "N") 
  if(user.hasfields == "Y") {  # Read in user fields if there are any
    # In old versions invoked cleaning algorithm here (since removed)
    user.polys <- suppressWarnings(st_read(coninfo$con, query = user.sql))
    
    # select only polygons
    user.polys <- user.polys %>% filter(st_is(. , "POLYGON"))
    
    if(nrow(user.polys) > 0){
      user.polys <- st_transform(user.polys, crs = prjstr)
    }
    else{
      user.hasfields <- "N" # change user.hasfield to N because no rows
    }
    
  } ###
  
  # Accuracy checks begin
  # Case 1: A null qaqc site recorded as null by the observer; score set to 1
  if((qaqc.hasfields == "N") & (user.hasfields == "N")) {
    if(comments == "T") print("Case 1: No QAQC or User fields")
    acc.out <- c("new_score" = 1, "old_score" = 1, "count_acc" = 1, 
                 "frag_acc" = 1, "edge_acc" = 1, "in_acc" = 1, 
                 "out_acc" = 1, "cate_acc" = 1, "user_count" = 0, 
                 "field_skill" = 1, "nofield_skill" = 1)
    acc.out <- list("acc.out" = acc.out)
  } else {
    # Pick up grid cell from qaqc table, for background location, as it will be 
    # needed for the other 3 cases  ### Extract this to separate function
    xy_tabs <- data.table(tbl(coninfo$con, "master_grid") %>% 
                            filter(name == kmlid) %>% 
                            dplyr::select(x, y, name) %>% collect())
                            #dplyr::select(x, y, name) %>% collect())
    
    grid.poly <- point_to_gridpoly(xy = xy_tabs, w = diam, NewCRSobj = prjstr, 
                                   OldCRSobj = gcsstr)
    grid.poly <- st_geometry(grid.poly)  # retain geometry only
  }  ###
  
  # Case 2: A null qaqc site but user mapped field(s)
  if((qaqc.hasfields == "N") & (user.hasfields == "Y")) {
    if(comments == "T") print("Case 2: No QAQC fields, but User fields") 
    acc.out <- case2_accuracy(grid.poly, user.polys, in.acc.wt, out.acc.wt, 
                              count.acc.wt, new.in.acc.wt, new.out.acc.wt, 
                              frag.acc.wt, edge.acc.wt, cate.acc.wt)
  }

  #  Case 3. QAQC has fields, User has no fields
  if(qaqc.hasfields == "Y" & user.hasfields == "N") {
    if(comments == "T") print("Case 3: QAQC fields but no User fields")
    acc.out <- case3_accuracy(grid.poly, qaqc.polys, in.acc.wt, out.acc.wt, 
                              count.acc.wt, new.in.acc.wt, new.out.acc.wt, 
                              frag.acc.wt, edge.acc.wt, cate.acc.wt, acc.switch)
  }
  
  # Case 4. QAQC has fields, User has fields
  if(qaqc.hasfields == "Y" & user.hasfields == "Y") {
    if(comments == "T") print("Case 4: QAQC fields and User fields")
      
    # read the first 'Fieldcategory.num' CategCode,
    # and pass it to case4_accuracy 
    catecode.sql <- paste0("SELECT category ",
                           "FROM categories WHERE categ_group='field' ", 
                           "AND NOT category='unsure2'")
    cate.code <- DBI::dbGetQuery(coninfo$con, catecode.sql)$category
    
    acc.out <- case4_accuracy(grid.poly, user.polys, qaqc.polys, count.acc.wt,
                              in.acc.wt, out.acc.wt, new.in.acc.wt, 
                              new.out.acc.wt, frag.acc.wt, edge.acc.wt, 
                              cate.acc.wt, edge.buf, cate.code,
                              comments, acc.switch)
  }
  
  ### Extract to separate function
  if(write.acc.db == "T") {
    if(mtype == "qa") {
      acc.sql <- paste0("insert into accuracy_data (assignment_id, new_score,",
                        " old_score, count_acc, fragmentation_acc, edge_acc, ", 
                        "ingrid_acc, outgrid_acc, category_acc, ", 
                        "num_userpolygons, field_skill,",
                        " nofield_skill) values ('", assignmentid, "', ", 
                        paste(acc.out$acc.out, collapse = ", "), ")")
    } else if(mtype == "tr") {
      acc.sql <- paste0("insert into qual_accuracy_data (assignment_id,", 
                        "new_score, old_score, count_acc, fragmentation_acc,",
                        "edge_acc, ingrid_acc, outgrid_acc, category_acc, ", 
                        "num_userpolygons, field_skill, nofield_skill, try)",
                        " values ('", assignmentid, "', ", 
                        paste(acc.out$acc.out, collapse = ", "), ", ", tryid, ")")
    }
    ret <- DBI::dbSendQuery(coninfo$con, acc.sql)
  } ###

  ### Extract out of function. Put in KMLAccuracyCheck
  # Map results according to error class
  if(draw.maps == "T") {
    maps <- acc.out$maps
    accuracy_plots(acc.out = acc.out$acc.out, grid.poly = maps$gpol, 
                   qaqc.poly = maps$qpol, user.poly = maps$upol,
                   inres = maps$inres, user.poly.out = maps$upolo, 
                   qaqc.poly.out = maps$qpolo, tpo = maps$tpo,fpo = maps$fpo, 
                   fno = maps$fno, proj.root = coninfo$dinfo$project_root, 
                   pngout = pngout)
  } ### 
  
  # Close connection to prevent too many from being open
  garbage <- DBI::dbDisconnect(coninfo$con)
  
  # Return error metrics
  if(comments == "T") {
    cat(acc.out$acc.out)  # All metrics if comments are on (testing only)
  } else {
    cat(unname(acc.out$acc.out[1]))  # First metric if in production
  }
}


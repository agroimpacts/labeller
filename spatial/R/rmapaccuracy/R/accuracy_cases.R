#' Function to handle missing objects or empty geometry sf objects & make NULL 
#' @param x A string naming the map object to check
#' @param env Environment variable
#' @details Used internally by case*_accuracy to check if objects exists, have 
#' geometries, and convert to NULL if they don't
#' @keywords internal
checkexists <- function(x, env) {
  if(exists(x, envir = env)) {
    a <- get(x, envir = env)
    # a <- eval(parse(text = x))
    if(length(a) > 0) o <- a
    if(length(a) == 0) o <- NULL
  } else {
    o <- NULL
  }
  return(o)
}

#' Case 2 accuracy metric
#' @param grid.poly Polygon of sampling grid
#' @param user.polys User's field boundary polygons
#' @param count.acc.wt Weighting given to field count accuracy
#' @param in.acc.wt Weighting for in grid map discrepancy
#' @param out.acc.wt Weighting for out of grid map discrepancy
#' @param new.in.acc.wt Weighting for in grid map in new score
#' @param new.out.acc.wt Weighting for out of grid map in new score
#' @param frag.acc.wt Weighting for fragmentation accuracy
#' @param edge.acc.wt Weighting for edge accuracy
#' @details Accuracy assessment for case when worker maps fields but none exist
#' @keywords internal
case2_accuracy <- function(grid.poly, user.polys, in.acc.wt, 
                           out.acc.wt, count.acc.wt, new.in.acc.wt, 
                           new.out.acc.wt, frag.acc.wt, edge.acc.wt, 
                           cate.acc.wt){
  
  user.nfields <- nrow(user.polys)  # n fields, for original count accuracy
  user.poly <- st_union(user.polys)  # union for area accuracys
  
  # area of overlap inside grid (hack for now because of Linux rounding issue)
  user.poly.in <- st_buffer(st_buffer(st_intersection(grid.poly, user.poly),
                                      0.0001), -0.0001)  
  
  if(length(user.poly.in) > 0) {  # if user has fields inside
    inres <- map_accuracy(maps = user.poly.in, truth = NULL, region = grid.poly)
  } else if(length(user.poly.in) == 0) {  # if user has no field inside
    inres <- map_accuracy(maps = NULL, truth = NULL, region = grid.poly)
  }
  # tss.acc <- inres[[1]][2]
  in.acc <- unname(inres[[1]][acc.switch])
  
  # Accuracy measures
  count.acc <- 0  # zero if QAQC has no fields but user maps even 1 field
  frag.acc <- 0  # user gets no credit if mapped where no fields exists
  edge.acc <- 0   
  cate.acc <- 0 # categorical accuracy is zero
  
  # Secondary metric - Sensitivity of results outside of kml grid
  user.poly.out <- st_buffer(st_buffer(st_difference(user.poly, grid.poly),
                                       0.00001), -0.00001)
  if(length(user.poly.out) == 0) {
    out.acc <- 1  # If user finds no fields outside of box, gets credit
    out.acc.old <- 1
  } else {# If user maps outside of box when no fields exist
    # out_region is the maximum bounding box of user, grid and qaqc polygons
    out_region <- st_difference(st_sf(geom = st_as_sfc(st_bbox(c(user.poly, 
                                                                 grid.poly)))), 
                                      grid.poly)
    outres <- map_accuracy(maps = user.poly.out, truth = NULL, 
                           region = out_region)
    out.acc <- unname(outres[[1]][acc.switch])
    out.acc.old <- 0
  }
  
  # likelihood(user_i = field|groundtruth = field), 
  # user maps field but none of groundtruth
  tflisti <- list("tp" = inres$tp, "tn" = inres$tn, 
                  "fp" = inres$fp, "fn" = inres$fn)
  areasi <- sapply(tflisti, function(x) {  # calculate tn and fp area
    ifelse(!is.null(x) & is.object(x) & length(x) > 0, st_area(x), 0)
  })
  lklh_field <- 0  
  # likelihood(user_i = no field|groundtruth = no field)
  lklh_nofield <- unname(areasi['tn']) / 
                   (unname(areasi['tn']) + unname(areasi['fp']))
  
  # Combine accuracy metrics
  old.score <- count.acc * count.acc.wt + in.acc * 
    in.acc.wt + out.acc.old * out.acc.wt 
  new.score <- in.acc * new.in.acc.wt + 
    out.acc * new.out.acc.wt + frag.acc * frag.acc.wt + edge.acc * edge.acc.wt
    + cate.acc * cate.acc.wt
  user.fldcount <- user.nfields
  
  # output accuracy metrics
  acc.out <- c("new_score" = new.score, "old_score" = old.score,
               "count_acc" = count.acc, 
               "frag_acc" = frag.acc, "edge_acc" = edge.acc, 
               "in_acc" = in.acc, "out_acc" = out.acc,
               "cate_acc" = cate.acc, "user_count" = user.fldcount, 
               "field_skill" = lklh_field, "nofield_skill" = lklh_nofield)
  # output maps
  env <- environment()  # get environment
  maps <- list("gpol" = grid.poly, "qpol" = NULL, "upol" = user.poly, 
               "inres" = inres, "upolout" = checkexists("user.poly.out", env), 
               "qpolout" = NULL, "tpo" = NULL, 
               "fpo" = checkexists("user.poly.out", env), "fno" = NULL)
  return(list("acc.out" = acc.out, "maps" = maps))
}

#' Case 3 accuracy metric
#' @param grid.poly Polygon of sampling grid
#' @param qaqc.polys QAQC polygons
#' @param count.acc.wt Weighting given to field count accuracy
#' @param in.acc.wt Weighting for in grid map discrepancy
#' @param out.acc.wt Weighting for out of grid map discrepancy
#' @param new.in.acc.wt Weighting for in grid map in new score
#' @param new.out.acc.wt Weighting for out of grid map in new score
#' @param frag.acc.wt Weighting for fragmentation accuracy
#' @param edge.acc.wt Weighting for edge accuracy
#' @param acc.switch 1 for conventional accuracy, 2 for TSS
#' @details Accuracy assessment for case when worker doesn't map fields but 
#' they do exist. Note that the TSS version of accuracy is still retainined 
#' here, but is no longer used because if return NULL values in certain cases. 
#' @keywords internal
case3_accuracy <- function(grid.poly, qaqc.polys, in.acc.wt, out.acc.wt, 
                           count.acc.wt, new.in.acc.wt, new.out.acc.wt, 
                           frag.acc.wt, edge.acc.wt, cate.acc.wt, 
                           acc.switch = 1) {
  
  qaqc.poly <- st_union(qaqc.polys)  # union for area accuracys

  # Mapped area differences inside the target grid cell
  qaqc.poly.in <- st_buffer(st_buffer(st_intersection(grid.poly, qaqc.poly),
                                      0.0001), -0.0001)  
  qaqc.poly.out <- st_buffer(st_buffer(st_difference(qaqc.poly, grid.poly),
                                       0.0001), -0.0001)
  inres <- map_accuracy(maps = NULL, truth = qaqc.poly.in, region = grid.poly)
  
  # Combine accuracy metric
  # tss.acc <- inres[[1]][2]
  # Accuracy measures
  count.acc <- 0  # if QAQC has fields but user maps none
  frag.acc <- 0 
  edge.acc <- 0 # miss qaqc fields, give zero for frag and edge acc
  cate.acc <- 0
  
  # Secondary metric - Sensitivity of results outside of kml grid
  if(length(qaqc.poly.out) == 0) {
    out.acc <- 1  # If no qaqc fields outside of box, gets credit
    out.acc.old <- 1
  } else {# If there exits qaqc fields outside of box when user map no fields
    out_region <- st_difference(st_sf(geom = st_as_sfc(st_bbox(c(qaqc.poly, 
                                                                 grid.poly)))), 
                                grid.poly)
    outres <- map_accuracy(maps = NULL, truth = qaqc.poly.out, 
                           region = out_region)
    out.acc <- unname(outres[[1]][acc.switch])
    out.acc.old <- 0
  }
  
  in.acc <- unname(inres[[1]][acc.switch])
  old.score <- count.acc * count.acc.wt + in.acc * 
    in.acc.wt + out.acc.old * out.acc.wt
  new.score <- in.acc * new.in.acc.wt + out.acc * new.out.acc.wt +
    frag.acc * frag.acc.wt + edge.acc * edge.acc.wt + cate.acc * cate.acc.wt
  user.fldcount <- 0
  
  
  # p(user_i = field|groundtruth = field)
  lklh_field <- 0 # user did not map field but has ground truth
  # p(user_i = no field|groundtruth = no field)
  lklh_nofield <- 1 # because user map all area as no field
  
  # output accuracy metrics
  # field_skill and nofield_skill are alias of max_field_lklh 
  # (p(user_i = field|groundtruth = field))
  # and max_nofield_lklh (p(user_i = no field|groundtruth = no field))
  acc.out <- c("new_score" = new.score, "old_score" = old.score,
               "count_acc" = count.acc, "frag_acc" = frag.acc, 
               "edge_acc" = edge.acc, 
               "in_acc" = in.acc, "out_acc" = out.acc, 
               "cate_acc" = cate.acc, "user_count" = user.fldcount, 
               "field_skill" = lklh_field, "nofield_skill" = lklh_nofield)
  # output maps
  env <- environment()  # get environment
  maps <- list("gpol" = grid.poly, "qpol" = qaqc.poly, "upol" = NULL, 
               "inres" = inres, "upolout" = NULL, 
               "qpolout" = checkexists("qaqc.poly.out", env), 
               "tpo" = NULL, "fpo" = NULL, 
               "fno" = checkexists("qaqc.poly.out", env)) # fno = qpolout
  return(list("acc.out" = acc.out, "maps" = maps))
}

#' Case 4 accuracy metric
#' @param grid.poly Polygon of sampling grid
#' @param user.polys User's field boundary polygons
#' @param qaqc.polys QAQC polygons
#' @param count.acc.wt Weighting given to field count accuracy
#' @param in.acc.wt Weighting for in grid map discrepancy
#' @param out.acc.wt Weighting for out of grid map discrepancy
#' @param new.in.acc.wt Weighting for in grid map in new score
#' @param new.out.acc.wt Weighting for out of grid map in new score
#' @param frag.acc.wt Weighting for fragmentation accuracy
#' @param edge.acc.wt Weighting for edge accuracy
#' @param edge.buf buffer for edge accuracy
#' @param comments Should comments be printed, "T" or "F" (default)? 
#' @param acc.switch 1 for conventional accuracy, 2 for TSS
#' @param cate.code the category codes reads from database
#' @details Accuracy assessment for case when worker maps fields where they  
#' they do exist. Note that the TSS version of accuracy is still retainined 
#' here, but is no longer used because if return NULL values in certain cases. 
#' @keywords internal
case4_accuracy <- function(grid.poly, user.polys, qaqc.polys, count.acc.wt, 
                           in.acc.wt, out.acc.wt, new.in.acc.wt, 
                           new.out.acc.wt, frag.acc.wt, edge.acc.wt, cate.acc.wt,
                           edge.buf, cate.code, comments = "F", acc.switch = 1) {
  
  # using hack function to make polys valid
  user.polys <- st_buffer(user.polys,0)
  qaqc.polys <- st_buffer(qaqc.polys,0)
  # prep polygons
  user.nfields <- nrow(user.polys)  # n fields, for original count accuracy
  user.poly <- st_union(user.polys)  # union for area accuracys
  qaqc.nfields <- nrow(qaqc.polys)  # n fields, for original count accuracy
  qaqc.poly <- st_union(qaqc.polys)  # union for area accuracys
  

  # Mapped area differences inside the target grid cell
  user.poly.in <- st_buffer(st_buffer(st_intersection(grid.poly, user.poly),
                                      0.0001), -0.0001)  # u maps in cell
  qaqc.poly.in <- st_buffer(st_buffer(st_intersection(grid.poly, qaqc.poly),
                                      0.0001), -0.0001)  # q maps in cell
  user.poly.out <- st_buffer(st_buffer(st_difference(user.poly, grid.poly),
                                       0.0001), -0.0001)  # u maps outside
  qaqc.poly.out <- st_buffer(st_buffer(st_difference(qaqc.poly, grid.poly),
                                       0.0001), -0.0001)  # q maps outside
  
  # Accuracy measures
  # original count accuracy
  cden <- ifelse(qaqc.nfields >= user.nfields, qaqc.nfields, user.nfields)
  cnu1 <- ifelse(qaqc.nfields >= user.nfields, qaqc.nfields, user.nfields)
  cnu2 <- ifelse(qaqc.nfields >= user.nfields, user.nfields, qaqc.nfields)
  count.acc <- 1 - (cnu1 - cnu2) / cden  # Percent agreement
  
  # Accuracy in the box. 2 possible cases. Normal, user has fields inside 
  # box. Abnormal, for some reason user only mapped outside of box. Inside
  # accuracy collapses to same as Case 3 inside accuracy.
  if(length(user.poly.in) > 0) {  # if user has fields inside
    inres <- map_accuracy(maps = user.poly.in, truth = qaqc.poly.in, 
                          region = grid.poly)  # accuracy metric
  } else if(length(user.poly.in) == 0) {  
    inres <- map_accuracy(maps = NULL, truth = qaqc.poly.in, region = grid.poly)
  }
  
  # Combine accuracy metrics
  # geometric accuracy assessment
  # buf is set as 3 planet pixels      
  geores <- geometric_accuracy(qaqc.polys, user.polys, edge.buf) 
  # tss.acc <- inres[[1]][2]
  frag.acc <- unname(geores[1])
  edge.acc <- unname(geores[2])  
  in.acc <- unname(inres[[1]][acc.switch])
  cate.acc <- categorical_accuracy(qaqc.polys, user.polys, cate.code)
  
  # Secondary metric - Sensitivity of results outside of kml grid
  if(length(user.poly.out) == 0 & length(qaqc.poly.out) == 0) {
    if(comments == "T") print("No QAQC or User fields outside of grid")
    out.acc <- 1  # perfect if neither u nor q map outside
    out.acc.old <- 1
  } else if(length(user.poly.out) > 0 & length(qaqc.poly.out) > 0) {
    if(comments == "T") print("Both QAQC and User fields outside of grid")
    ##### still keep old out accuracy for comparison
    tpo <- st_intersection(qaqc.poly.out, user.poly.out)  # tp outside
    fpo <- st_difference(user.poly.out, qaqc.poly.out)  # fp outside
    fno <- st_difference(qaqc.poly.out, user.poly.out)  # fn outside
    tflisto <- c("tpo", "fpo", "fno")
    areaso <- sapply(tflisto, function(x) {  # calculate tp and fp area
      xo <- get(x)
      ifelse(!is.null(xo) & is.object(xo) & length(xo) > 0, st_area(xo), 0)
    })
    out.acc.old <- unname(areaso[1]) / (unname(areaso[1]) + unname(areaso[3]))  
    ######## new calculation
    out_region <- st_difference(st_sf(geom = st_as_sfc(st_bbox(c(user.poly, 
                                                                 grid.poly,
                                                                 qaqc.poly)))), 
                                grid.poly)
    outres <- map_accuracy(maps = user.poly.out, truth = qaqc.poly.out, 
                           region = out_region)
    out.acc <- unname(outres[[1]][acc.switch])
    
  } else if (length(user.poly.out) == 0 & length(qaqc.poly.out) > 0){
    if(comments == "T") {
      print(" QAQC fields outside of grid, but no user fields")
    }
    out_region <- st_difference(st_as_sfc(st_bbox(c(qaqc.poly, grid.poly))), 
                                grid.poly)
    outres <- map_accuracy(maps = NULL, truth = qaqc.poly.out, 
                           region = out_region)
    out.acc <- unname(outres[[1]][acc.switch])
    out.acc.old <- 0
  } else {
    if(comments == "T") {
      print(" no QAQC fields outside of grid, but has user fields")
    }
    out_region <- st_difference(st_as_sfc(st_bbox(c(user.poly, grid.poly))), 
                                grid.poly)
    outres <- map_accuracy(maps = user.poly.out, truth = NULL, 
                           region = out_region)
    out.acc <- unname(outres[[1]][acc.switch])
    out.acc.old <- 0
  }
  
  old.score <- count.acc * count.acc.wt + in.acc * in.acc.wt + 
    out.acc.old * out.acc.wt 
  new.score <- in.acc * new.in.acc.wt + out.acc * new.out.acc.wt + 
    frag.acc * frag.acc.wt + edge.acc * edge.acc.wt + cate.acc * cate.acc.wt
  user.fldcount <- user.nfields
  
  
  tflisti <- list("tp" = inres$tp, "tn" = inres$tn, 
                  "fp" = inres$fp, "fn" = inres$fn)
  areasi <- sapply(tflisti, function(x) {  # calculate tp and fp area
    ifelse(!is.null(x) & is.object(x) & length(x) > 0, st_area(x), 0)
  })
  
  # likelihood(user_i = field|groundtruth = field)
  lklh_field <- unname(areasi['tp']) / 
    (unname(areasi['tp']) + unname(areasi['fn']))  
  # likelihood(user_i = no field|groundtruth = no field)
  lklh_nofield <- unname(areasi['tn']) / 
    (unname(areasi['tn']) + unname(areasi['fp']))
  
  # output accuracy metrics
  acc.out <- c("new_score" = new.score, "old_score" = old.score,
               "count_acc" = count.acc, 
               "frag_acc" = frag.acc, "edge_acc" = edge.acc, 
                "in_acc" = in.acc, "out_acc" = out.acc, 
               "cate_acc" = cate.acc, "user_count" = user.fldcount, 
               "field_skill" = lklh_field, "nofield_skill" = lklh_nofield)
  
  # output maps
  env <- environment()  # get environment
  maps <- list("gpol" = grid.poly, "qpol" = qaqc.poly, "upol" = user.poly, 
               "inres" = inres, "upolo" = checkexists("user.poly.out", env),  
               "qpolo" = checkexists("qaqc.poly.out", env), 
               "tpo" = checkexists("tpo", env), "fpo" = checkexists("fpo", env), "fno" = checkexists("fno", env))
  return(list("acc.out" = acc.out, "maps" = maps))
}


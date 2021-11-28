#' Creates polygon grid box from point
#' @param xy A data.frame containing x and y coordinates and name of grid point
#' @param w A value in meters specifiying 1/2 the diameter of the grid polygon
#' @param OldCRSobj The crs for the input polygon
#' @param NewCRSobj crs to transform polygon to
#' @details This function is created for use by KMLgenerate, which uses it to 
#' convert grid points to polygons. 
#' @export
point_to_gridpoly <- function(xy, w, OldCRSobj, NewCRSobj) {
  dw <- list("x" = c(-w, w, w, -w, -w), "y" = c(w, w, -w, -w, w))
  pols <- do.call(rbind, lapply(1:nrow(xy), function(i) {  # i <- 1
    xs <- unlist(sapply(dw$x, function(x) unname(xy[i, "x"] + x)))
    ys <- unlist(sapply(dw$y, function(x) unname(xy[i, "y"] + x)))
    p1 <- list(t(sapply(1:length(xs), function(i) c(xs[i], ys[i]))))
    ## sf, sfc, sfg are three basic classes used to repreesent simple featurtes in sf package 
    ## see https://cran.r-project.org/web/packages/sf/vignettes/sf1.html
    ## create a geometry (sfg) from a list of points, e.g., point, polygon, multipolygon
    pol <- st_polygon(p1)
    ## create a sfc, which is a list of sfg
    poldf <- st_sfc(pol)
    ## create a sf, a table which contains feature atributes and feature geometries (sfc)
    ## .() is actually just an alias to ‘list()’. It returns a data table, whereas not using ‘.()’ only returns a vector
    polsf <- st_sf(xy[i, .(name)], geom = poldf)
    st_crs(polsf) <- OldCRSobj # first set GCS
    polsf <- st_transform(polsf, crs = NewCRSobj) # then transform into PRS
    polsf
  }))
  return (pols)
}

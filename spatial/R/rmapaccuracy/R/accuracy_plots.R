#' Plotting function for kml_accuracy
#' @param acc.out Vector of accuracy terms
#' @param grid.poly sf polygon object of sampling grid 
#' @param qaqc.poly sf polygon object of q polygon (assuming it exists)
#' @param user.poly sf polygon object of user maps (assuming it exists)
#' @param inres Output list from map_accuracy
#' @param user.poly.out sf polygon for portion of user map outside of grid
#' @param qaqc.poly.out sf polygon for portion of q map outside of grid
#' @param tpo sf polygon of correct user maps outside of grid (if exists) 
#' @param fpo sf polygon of false positive user maps outside of grid (if exists) 
#' @param fno sf polygon of false negative area outside of grid (if exists) 
#' @param proj.root Project directory path (use dinfo["project.root"])
#' @param pngout Output plot to png? (default: TRUE)
#' @details Not currently functional, but intended to provide replacement for 
#' plotting code in kml_accuracy
#' @keywords internal
accuracy_plots <- function(acc.out, grid.poly, qaqc.poly, user.poly, inres, 
                           user.poly.out, qaqc.poly.out, tpo, fpo, fno, proj.root, 
                           pngout = TRUE) {

  if(!is.null(grid.poly)) bbr1 <- st_bbox(grid.poly)
  if(!is.null(qaqc.poly)) bbr2 <- st_bbox(qaqc.poly)
  if(!is.null(user.poly)) bbr3 <- st_bbox(user.poly)
  
  cx <- 1.5 
  lbbrls <- ls(pattern = "^bbr")
  if(length(lbbrls) > 0) {
    xr <- range(sapply(1:length(lbbrls), function(x) get(lbbrls[x])[c(1,3)]))
    yr <- range(sapply(1:length(lbbrls), function(x) get(lbbrls[x])[c(2,4)]))
    vals <- rbind(xr, yr)
    
    if(!is.null(grid.poly)) {
      tm <- format(Sys.time(), "%Y%m%d%H%M%OS2")
      if(pngout == TRUE) {
        pngname <- paste0(proj.root, "/spatial/R/Error_records/", 
                          kmlid, "_", assignmentid, "_", tm, ".png")
        png(pngname, height = 700, width = 700, antialias = "none")
      }
      plot(st_geometry(grid.poly), xlim = vals[1, ], ylim = vals[2, ])
      objchk <- sapply(2:5, function(x) is.object(inres[[x]]))
      mpi <- names(acc.out)
      #plotpos <- c(0.15, 0.4, 0.65, 0.90)
      cols <- c("green4", "red4", "blue4", "grey30")
      for(i in 1:4) {
        if(objchk[i] == "TRUE") {
          plot(st_geometry(inres[[i + 1]]), add = TRUE, col = cols[i])
        }
        if(!is.null(user.poly.out)) {
          plot(st_geometry(user.poly.out), add = TRUE, col = "grey")
        }
        if(!is.null(qaqc.poly.out)) {
          plot(st_geometry(qaqc.poly.out), add = TRUE, col = "pink")
        }
        if(!is.null(tpo)) {
          plot(tpo, col = "green1", add = TRUE)
        }
        if(!is.null(fpo)) {
          plot(fpo, col = "red1", add = TRUE)
        }
        if(!is.null(fno)) {
          plot(fno, col = "blue1", add = TRUE)
        }
      }
      for(i in 1:7) {
        mtext(round(acc.out[i], 3), side = 3, line = -1, adj = 1 * (i - 1) / 5 
                , cex = cx)
        mtext(mpi[i], side = 3, line = 0.5, adj = 1 * (i - 1) / 5
                , cex = cx)
      }
      mtext(paste0(kmlid, "_", assignmentid), side = 1, cex = cx)
      legend(x = "right", legend = c("TP", "FP", "FN", "TN"), pch = 15, 
             bty = "n", col = cols, pt.cex = 3, cex = cx)
      if(pngout == TRUE) garbage <- dev.off()  # Suppress dev.off message
    }  
  }
}

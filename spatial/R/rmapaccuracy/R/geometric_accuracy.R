#' Calculate fragmentation accuracy and edge accuracy 
#' @param qaqc.polys qaqc polygons
#' @param user.polys user-map polygons
#' @param buf buffer width for edge accuracy
#' @details This function targets on how the geometry of qaqc polygons are 
#' mapped by user polygons, which should be complementary to the in-grid and 
#' outgrid thematic accuracy. 
#' @keywords internal
geometric_accuracy <- function(qaqc.polys, user.polys, buf) {
  match.num <- 0 # the number of matched polygons
  acc.edge.sum <- 0 # accumulated edge accuracy
  for(s in 1:nrow(qaqc.polys)) {  # s <- 1
    for(t in 1:nrow(user.polys)) {  # t <- 1
      qaqc.single <- st_geometry(qaqc.polys[s, ])
      user.single <- st_buffer(st_geometry(user.polys[t, ]),0)
      tmp <- st_intersection(qaqc.single, user.single)
      if (length(tmp) > 0) {
        # two critera for matched polygons
        if (as.numeric(st_area(tmp) / st_area(qaqc.single)) > 0.5 &
            as.numeric(st_area(tmp) / st_area(user.single)) > 0.5) {
          match.num <- match.num + 1 
          boundary.qaqc.single <- st_difference(st_buffer(qaqc.single, buf),
                                                st_buffer(qaqc.single, -buf))
          boundary.user.single <- st_difference(st_buffer(user.single, 0.1),
                                                st_buffer(user.single, -0.1))
          # edge accuracy is equal to the intersect length divided by the 
          # perimeter of the qaqc polygon
          intersect <- st_intersection(boundary.qaqc.single, boundary.user.single)
          intersect_area <- ifelse(length(intersect) > 0, 
                                    st_area(intersect),
                                    0)
          
          intersect_ratio <- intersect_area / st_area(boundary.qaqc.single)
          acc.edge.single <- as.numeric(intersect_ratio)
          acc.edge.sum <- acc.edge.sum + acc.edge.single
          break
        }
      }
    }
  }
  if(match.num == 0){
    edge_acc <- 0
    frag_acc <- 0
  }
  else {
    edge_acc <- as.numeric(acc.edge.sum / match.num) 
    # using the number of qaqc not the maximum between qaqc and user is because 
    # extra user polys (false alarms) are factored into thematic accuracy
    frag_acc <- as.numeric(match.num / nrow(qaqc.polys)) 
  }
  # return(list("fragmentaccuracy" = frag_acc, "edgeaccuracy" = edge_acc))
  return(c("fragmentaccuracy" = frag_acc, "edgeaccuracy" = edge_acc))
}

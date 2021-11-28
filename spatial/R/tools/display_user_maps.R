# display_user_maps.R
library(leaflet)
display_user_maps <- function(gpoly, user_polys, os_url, gs_url, categories) {
  
  # set up parameters for displaying raster foundry overlays
  falseparm <- "&redBand=3&greenBand=2&blueBand=1"
  xyz <- list("OS" = os_url, "GS" = gs_url)
  xyz <- c(xyz, lapply(xyz, function(x) paste0(x, falseparm)))
  names(xyz)[3:4] <- paste0(names(xyz)[3:4], "F")
  xyz <- xyz[c("OS", "OSF", "GS", "GSF")]
  
  # plotting options
  slist <- list("color" = "white")
  label_opts <- labelOptions(
    noHide = TRUE, style = slist, direction = 'top', textOnly = TRUE
  )
  
  # plots
  xy <- suppressWarnings(st_coordinates(st_centroid(gpoly))) %>% data.frame
  m <- leaflet() %>% addProviderTiles("Esri.WorldImagery") %>%
    setView(xy$X, xy$Y, zoom = 15)
  for(i in 1:length(xyz)) m <- m %>% addTiles(xyz[[i]], group = names(xyz)[i])
  m <- m %>% addPolygons(data = gpoly, fill = FALSE, color = "white", 
                         group = "Cell", weight = 2)
  if(!is.null(user_polys)) {
    cols <- c("yellow", "cyan", "orange", "pink", "purple", "white", "green3")
    cols <- cols[which(categories$category %in% user_polys$category)]
    pal <- colorFactor(cols, domain = categories$category)
    m <- m %>% addPolygons(data = user_polys, fillOpacity = 0, 
                           #fillColor = ~pal(category), 
                           color = ~pal(category), #color = "grey", 
                           group = "Maps", weight = 2)
  } else {
    m <- m
  }
  m <- m %>% 
    # addLabelOnlyMarkers(xy$X, xy$Y, label = gpoly$name,
    #                     labelOptions = label_opts) %>%
    addLayersControl(overlayGroups = c("Cell", "Maps", names(xyz)),
                     options = layersControlOptions(collapsed = FALSE,
                                                    autoZIndex = FALSE))
  m
}

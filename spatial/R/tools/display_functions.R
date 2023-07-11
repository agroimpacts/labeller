# display_user_maps.R
library(leaflet)
display_imagery <- function(gpoly, user_maps = NULL, qaqc_maps = NULL, os_url, 
                            gs_url, categories) {
  
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
  if(!is.null(user_maps)) {
    cols <- c("yellow", "cyan", "orange", "pink", "purple", "white", "green3")
    cols <- cols[which(categories$category %in% user_maps$category)]
    pal <- colorFactor(cols, domain = categories$category)
    m <- m %>% addPolygons(data = user_maps, fillOpacity = 0.7, 
                           fillColor = "blue",#~pal(category), 
                           # color = ~pal(category), #color = "grey", 
                           group = "User", weight = 2)
  } else {
    m <- m
  }
  if(!is.null(qaqc_maps)) {
    cols <- c("yellow", "cyan", "orange", "pink", "purple", "white", "green3")
    cols <- cols[which(categories$category %in% qaqc_maps$category)]
    pal <- colorFactor(cols, domain = categories$category)
    m <- m %>% addPolygons(data = qaqc_maps, fillOpacity = 0.5, 
                           fillColor = ~pal(category),
                           # color = ~pal(category), 
                           color = "grey",
                           group = "Reference", weight = 1)
  } else {
    m <- m
  }
  m <- m %>% 
    # addLabelOnlyMarkers(xy$X, xy$Y, label = gpoly$name,
    #                     labelOptions = label_opts) %>%
    addLayersControl(overlayGroups = c("Cell", "User", "Reference", names(xyz)),
                     options = layersControlOptions(collapsed = FALSE,
                                                    autoZIndex = FALSE))
  m
}

# rmapaccuracy function here to allow usage independent of package
point_to_gridpoly <- function(xy, w, OldCRSobj, NewCRSobj) {
  dw <- list("x" = c(-w, w, w, -w, -w), "y" = c(w, w, -w, -w, w))
  pols <- do.call(rbind, lapply(1:nrow(xy), function(i) {  # i <- 1
    xs <- unlist(sapply(dw$x, function(x) unname(xy[i, "x"] + x)))
    ys <- unlist(sapply(dw$y, function(x) unname(xy[i, "y"] + x)))
    p1 <- list(t(sapply(1:length(xs), function(i) c(xs[i], ys[i]))))
    ## create a geometry (sfg) from points, e.g., point, polygon, multipolygon
    pol <- st_polygon(p1)
    ## create a sfc, which is a list of sfg
    poldf <- st_sfc(pol)
    polsf <- st_sf(xy[i, .(name)], geom = poldf)
    st_crs(polsf) <- OldCRSobj # first set GCS
    polsf <- st_transform(polsf, crs = NewCRSobj) # then transform into PRS
    polsf
  }))
  return (pols)
}


display_tiles_fields <- function(fields = NULL, gs_url, probr) {
  
  # set up parameters for displaying raster foundry overlays
  falseparm <- "&redBand=3&greenBand=2&blueBand=1"
  xyz <- list("Planet" = gs_url)
  xyz <- c(xyz, lapply(xyz, function(x) paste0(x, falseparm)))
  names(xyz)[2] <- paste(names(xyz)[2], "False")
  xyz <- xyz[c("Planet", "Planet False")]
  
  xy <- st_coordinates(
    st_centroid(st_as_sf(as(extent(probr), "SpatialPolygons")))
  )
  pal <- colorQuantile("Greys", reverse = TRUE, domain = c(0, 100))
  
  flood <- paste0("https://storage.googleapis.com/nrtdev-data/2020-01-31/", 
                  "Combined/publicSats_Nov-Dec2019/{z}/{x}/{y}.png")
  
  m <- leaflet() %>% addProviderTiles("Esri.WorldImagery") %>%
    setView(xy[1], xy[2], zoom = 12)
  m <- m %>% addTiles(flood, group = "Flood")
  for(i in 1:length(xyz)) m <- m %>% addTiles(xyz[[i]], group = names(xyz)[i])
  m <- m %>% addRasterImage(probr, colors = pal, group = "Probability")
  m <- m %>% addPolygons(data = fields, fillOpacity = 0.7, 
                         color = "transparent",
                         fillColor = "yellow",
                         group = "Fields", weight = 2)
  m <- m %>% 
    addLayersControl(
      overlayGroups = c("Fields", "Probability", "Planet", "Planet False", 
                        "Flood"),
      options = layersControlOptions(collapsed = FALSE, autoZIndex = FALSE)
    )
  m
  
  # # plotting options
  # slist <- list("color" = "white")
  # label_opts <- labelOptions(
  #   noHide = TRUE, style = slist, direction = 'top', textOnly = TRUE
  # )
}


# ## Create rmarkdown document
# outfile <- paste0(worker_sub_paths[1], "/worker_", worker, "_", tstamp, ".Rmd")
# head_text <- c(paste0("title: 'Labels: mapper ", worker, "'\n"), 
#                "output: html_document\n", "---\n")
# chunk_text <- c("```{r, echo=FALSE, message=FALSE, warning=FALSE}\n", "```\n")
# 
# # write presentation header  
# cat("---\n", file = outfile)
# for(i in head_text) cat(i, file = outfile, append = TRUE)
# 
# nl <- function(x) paste0(x, "\n")
# # write presentation body
# for(i in 1:length(dat)) {
#   # if first slide, write in echo = FALSE statement to source function and 
#   # data
#   if(i == 1) {
#     cat(chunk_text[1], file = outfile, append = TRUE)
#     cat("library(leaflet)\n", file = outfile, append = TRUE)
#     cat("library(dplyr)\n", file = outfile, append = TRUE)
#     cat("library(sf)\n", file = outfile, append = TRUE)
#     cat(paste0("source('", display_func_path, "')\n"), file = outfile, 
#         append = TRUE)
#     cat(paste0("load('", dat_file, "')\n"), file = outfile, 
#         append = TRUE)
#     cat(chunk_text[2], file = outfile, append = TRUE)
#   }
#   for(j in 1:nrow(dat[[i]]$grid)) {  # i <- 1; j <- 1
#     d <- dat[[i]]
#     gname <- d$grid %>% slice(j) %>% pull(name)
#     cat(chunk_text[1], file = outfile, append = TRUE)
#     cat_strings <- c(
#       nl(glue("d <- dat[[{i}]]")),
#       nl(glue("gpoly <- d$grid %>% slice({j})")), 
#       nl(glue("gname <- gpoly %>% pull(name)")), 
#       nl(glue("if(!is.null(d$user)) user_maps <- d$user %>%", 
#               "filter(name == gname)")),
#       nl(glue("if(is.null(d$user)) user_maps <- NULL")),
#       nl(glue("os_url <- d$tms %>% filter(name == gname & season == 'OS') ", 
#               "%>% pull(tms_url)")),
#       nl(glue("gs_url <- d$tms %>% filter(name == gname & season == 'GS') ",
#               "%>% pull(tms_url)"))
#     )
#     for(k in cat_strings) cat(k, file = outfile, append = TRUE)
#     cat(chunk_text[2], file = outfile, append = TRUE)
#     cat("\n", file = outfile, append = TRUE)
#     
#     cat(nl(glue("## Labeller {gsub('i', '', names(dat)[i])} Cell {gname}")), 
#         file = outfile, append = TRUE)
#     cat(chunk_text[1], file = outfile, append = TRUE)
#     cat(nl(glue(
#       "display_imagery(gpoly, user_maps, os_url, gs_url, d$cats)")
#     ), file = outfile, append = TRUE)
#     cat(chunk_text[2], file = outfile, append = TRUE)
#     
#     # cat("---\n", file = outfile, append = TRUE)
#     cat("\n", file = outfile, append = TRUE)
#   }
# }
# 
# # render markdown, both html (for interactive viewing) and pdf (for annotating)
# rmarkdown::render(outfile, output_file = gsub(".Rmd", ".html", outfile))
# # replace writeout to html, writes more slowly
# BrailleR::FindReplace(outfile, "output: html_document", "output: pdf_document")
# rmarkdown::render(outfile, output_file = gsub(".Rmd", ".pdf", outfile))

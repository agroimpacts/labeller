#' Bayesian Model Averaging P(theta|D) = ∑ weight * mapper posterior probability
#' @description Core codes for Bayesian Model Averaging 
#' P(theta|D) = ∑ weight * mapper posterior probability
#' @param bayes.poly a sf object has five columns: 
#' (1)posterior.field a are mapper posterior probability, meaning that
#' mappers' opinion for the possibility of field (we set 1 for sure category, 
#' and 0.5 for unsure);  
#' (3)max.field.lklh, (4) max.nofield.lklh, namely the producer's accuracy, which means
#' that given its label as field or no field, the maximum likelihood to be the 
#' mapper i; (5) score
#' Weight = max.nofield.lklh (or max.field.lklh) * score
#' @param rasterextent the extent for the output
#' @param threshold the threshold for P(theta|D) to determine the label of pixels
#' as field or no field
#' @return A list of three rasters--heat map, risk map, and consensus map
#' @importFrom fasterize fasterize
#' @importFrom raster raster overlay setValues extent reclassify
#' @export 
bayes_model_averaging <- function(bayes.polys, rasterextent, threshold) {

  gcsstr <- "+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"
  
  posterior.field.rst <- raster(extent(as_Spatial(rasterextent)),
  # stupid method: the centroid r doesn't allow coercing sfc to spatial
  # bb <- st_bbox(rasterextent)
  # posterior.field.rst <- raster(extent(bb['xmin'], bb['xmax'], bb['ymin'], bb['ymax']),
                                resolution = 0.005 / 200, crs = gcsstr)  ### HC
  
  # consensus = sum(weights * posterior.field.rst)/sum(weight)
  # read and process user polygons using a recursive way in order to save memory
  posterior.acc <- NULL
  weight.acc <- NULL
  for (t in 1:nrow(bayes.polys)) {
    # empty geometry means that user label all map extent as no field, 
    # posterior.field.rst = '0'
    if(is.na(bayes.polys$prior[t]) == FALSE){ # don't process prior probablity/score is na
      if (st_is_empty(bayes.polys[t, "geometry"])) {
        posterior.field.val <- rep(0,
                                   ncol(posterior.field.rst) * 
                                     nrow(posterior.field.rst))
        posterior.field.rst <- setValues(posterior.field.rst, posterior.field.val)
        
        # maximum likelihood matrix would be a matrix with a single value
        max.nofield.lklh.val <- rep(bayes.polys[t,]$max.nofield.lklh,
                                    ncol(posterior.field.rst) * 
                                      nrow(posterior.field.rst))
        user.max.lklh <- setValues(posterior.field.rst, max.nofield.lklh.val)
        
      }
      else {
        # polygon: 1 or 0.5
        # bkgd: 0
        posterior.field.rst <- fasterize(bayes.polys[t, ], posterior.field.rst, 
                                         field = "posterior.field", 
                                         background = 0)
        user.max.lklh <- fasterize(bayes.polys[t, ], posterior.field.rst, 
                                   field =  "max.field.lklh", 
                                   background = bayes.polys[t,]$max.nofield.lklh)
      }
      
      weight <- user.max.lklh * bayes.polys[t,]$prior
      if (is.null(posterior.acc)) {
        weight.acc <- weight 
        posterior.acc <- overlay(posterior.field.rst, weight, 
                                 fun = function(x, y) (x * y))
        
      } else {
        # only count weight for posterior probably = 1
        if(bayes.polys[t,]$posterior.field == 1){
          weight.acc <- weight.acc + weight 
        }
        posterior.acc <- posterior.acc + overlay(posterior.field.rst, weight, 
                                                 fun = function(x, y) (x * y)) 
      }
    }
  } 
  
  heat.map <- overlay(posterior.acc, weight.acc,
                      fun = function(x, y) {return(x / y)})
  
  label.map <- reclassify(heat.map, c(-Inf, threshold, 0, threshold, Inf, 1)) 
  
  # risks maps is to assign non-field (1-label.map) as heat.map values, and 
  # asssign field as 1-heat.map
  risk.map <- overlay(heat.map, label.map, 
                      fun = function(r1, r2) {r1 *(1 - r2) + (1 - r1) * r2})
  
  return(list("labelmap" = label.map, "heatmap" = heat.map, 
              "riskmap" = risk.map))
}
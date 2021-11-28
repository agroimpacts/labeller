#' Upload spatial objects to S3 bucket
#' @param proj.root 
#' @param bucketname the name of S3 bucket
#' @param local.object local spatial objects, and it has to be RasterLayer or sf
#' objects
#' @param s3.dst the folder directory of s3 bucket for putting local objects
#' @param s3.filename the name of local.object saved in s3
#' @importFrom aws.s3 put_object
#' @importFrom raster writeRaster
s3_upload <- function(proj.root, bucketname, local.object, s3.dst, s3.filename){
  ## if sp class
  if (class(local.object)[1] == "RasterLayer"){
    tm <- format(Sys.time(), "%Y%m%d%H%M%OS2")
    
    # Set up AWS keys and region here.
    common_path <- file.path(proj.root, "common")
    params <- yaml::yaml.load_file(file.path(common_path, 'config.yaml'))
    Sys.setenv("AWS_ACCESS_KEY_ID" = params$learner$aws_access,
               "AWS_SECRET_ACCESS_KEY" = params$learner$aws_secret,
               "AWS_DEFAULT_REGION" = params$learner$aws_region)
    
    # create a local temp file
    localfile <- paste0(proj.root, "/spatial/R/tmp_consensus_map/", 
                        s3.filename, "_", tm, ".tif")
    
    writeRaster(local.object, localfile, datatype='INT1U', overwrite = TRUE)
    
    # putlocal temp file in the bucket.
    put_object(file = localfile, object = paste0(s3.dst, s3.filename, ".tif"), 
               bucket = bucketname)
    
    # delete temporal file
    file.remove(localfile)
  }
  else if (class(polygon_sf)[1] == "sf"){
    ## this function is coded in case that we need to upload vector in future 
    ## such as segmentation procedure
    ############ will code it up soon once finalize rasterlayer function ###### 
  }
  else stop("It allows only RasterLayer or sf objects to be uploaded into S3", 
            call. = FALSE)
}

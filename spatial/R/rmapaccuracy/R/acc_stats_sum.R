#' Calculate binary classification accuracy
#' @param tp True positives
#' @param fp False positives
#' @param tn True negatives
#' @param fn False negatives
#' @return Classification accuracy and the True Skill Statistic
#' @keywords internal
# accStatsSum <- function(tp, fp, tn, fn) {
acc_stats_sum <- function(tp, fp, tn, fn) {
  agree <- tp / sum(tp, fn)  # Simple agreement class 1
  if(is.na(agree)) agree <- 0  # Set to 0 if NA
  accuracy <- sum(tp, tn) / sum(tp, tn, fp, fn)
  #TSS <- agree + (tn / (fp + tn)) - 1  # Sens + specificity - 1
  TSS <- (agree + (tn / (fp + tn))) / 2  # TSS compressed to 0-1
  r1 <- round(accuracy, 2)
  r2 <- round(TSS, 2)
  out <- c(r1, r2)
  names(out) <- c("accuracy", "TSS")          
  return(out)
}


% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/accuracy_plots.R
\name{accuracy_plots}
\alias{accuracy_plots}
\title{Plotting function for kml_accuracy}
\usage{
accuracy_plots(acc.out, grid.poly, qaqc.poly, user.poly, inres,
  user.poly.out, qaqc.poly.out, tpo, fpo, fno, proj.root, pngout = TRUE)
}
\arguments{
\item{acc.out}{Vector of accuracy terms}

\item{grid.poly}{sf polygon object of sampling grid}

\item{qaqc.poly}{sf polygon object of q polygon (assuming it exists)}

\item{user.poly}{sf polygon object of user maps (assuming it exists)}

\item{inres}{Output list from map_accuracy}

\item{user.poly.out}{sf polygon for portion of user map outside of grid}

\item{qaqc.poly.out}{sf polygon for portion of q map outside of grid}

\item{tpo}{sf polygon of correct user maps outside of grid (if exists)}

\item{fpo}{sf polygon of false positive user maps outside of grid (if exists)}

\item{fno}{sf polygon of false negative area outside of grid (if exists)}

\item{proj.root}{Project directory path (use dinfo["project.root"])}

\item{pngout}{Output plot to png? (default: TRUE)}
}
\description{
Plotting function for kml_accuracy
}
\details{
Not currently functional, but intended to provide replacement for 
plotting code in kml_accuracy
}
\keyword{internal}

% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/mlsdistcomp.R
\docType{class}
\name{MRSDistCompBase}
\alias{MRSDistCompBase}
\title{Base class that parameterizes all database and other common
functions for the MRSDistCompMetamodel classes}
\format{\code{\link{R6Class}} object.}
\usage{
MRSDistCompBase
}
\value{
Object of \code{\link{R6Class}} with methods for communication with backend MRSDistComp database.
}
\description{
Base class that parameterizes all database and other common
functions for the MRSDistCompMetamodel classes
}
\section{Methods}{


\describe{
  \item{\code{new()}}{This method is used to create an object of this class. This initializes a new ODBC connection to the target database.}
  \item{\code{finalize(name,clientid,tenantid,isenabled=1,validfrom=NULL,validto=NULL)}}{This method creates a new Participant or collaborating party that will interact with the current deployment.}
  \item{\code{create(...,tablename)}}{Parameterized function that creates an SQL record in the specified tablename. The key/values in the varargs is used for the column names/values respectively.}
  \item{\code{read(...,tablename)}}{Parameterized function that reads SQL records from the specified tablename. The key/values in the varargs are used as AND-ed where filters in the query.}
  \item{\code{delete(...,tablename)}}{Parameterized function that deletes SQL record(s) in the specified tablename. The key/values in the varargs are used as AND-ed where filters in the query.}}
}

\examples{
MRSDistCompBase$new()
}
\keyword{datasets}

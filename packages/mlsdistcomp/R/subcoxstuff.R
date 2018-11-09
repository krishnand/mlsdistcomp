#' Distributed Computing with R
#'
#' \code{subcoxworker} is a collection of methods that extend 
#' \code{coxworker}, to work with \code{mlsdistcomp}.  
#' \code{coxworker is part of \code{distcomp}, which fits models to data that may be
#' distributed at various sites and \code{mlsdistcomp} creates a 
#' network of cloud applications to implement this.

MlsCoxWorker <- R6Class("MlsCoxWorker",
                    inherit = CoxWorker,
                    public = list(
                      getFitter = function() private$fitter )
                        )


MlsCoxMaster <- R6Class("MlsCoxMaster",
                         inherit = CoxMaster,
                         private = list(
                            mapFn = function(site, beta) {
                                payload <- list(objectId = site$instanceId,
                                                method = "logLik",
                                                beta = beta)
                                q <- POST(.makeOpencpuURL(urlPrefix=site$url, fn="executeMethod"),
                                        body = toJSON(payload),
                                        add_headers("Content-Type" = "application/json"),
                                        config=getConfig()$sslConfig
                                        )
                                ## Should really examine result here.
                                .deSerialize(q)
                            },
                            mapFnMRS = function(site, jobid, beta) {

                              print(sprintf("Executing mapFnMRS for site '%s' with the following payload...",
                                            as.character(site$url)))
                              payload <- list(projectname = as.character(private$defnId),
                                              jobid = as.character(jobid),
                                              method = "logLik",
                                              methodparams = toJSON(list("beta"=beta)))
                              q <- POST(url=site$url,
                                   body = payload,
                                   add_headers("Content-Type" = "application/json", "Authorization" = as.character(site$token)),
                                   encode = "json")

                              print("Finished executing mapFnMRS iteration...Parsing results")
                              resultJSON <- jsonlite::fromJSON(content(q, "text"))
                              logLikResultList = as.list(resultJSON$outputParameters$Result)
                              print(logLikResultList, row.names = FALSE)
                              return(logLikResultList)
                             },
                             result = list(),
                             debug = FALSE
                         ),
                         public = list(
                            runMRS = function(jobId) {
                             'Run estimation'
                             dry_run <- private$dry_run
                             debug <- private$debug
                             defn <- private$defn
                             if (debug) {
                                 print("run(): checking worker object creation")
                             }
                             if (dry_run) {
                                 ## Workers have already been created and passed
                                 sites <- private$sites
                                 pVals <- sapply(sites, function(x) x$worker$getP())
                             } else {
                                 ## Create an instance Id
                                 instanceId <- generateId(object=list(Sys.time(), self))

                                ## Augment each site with object instance ids
                                private$sites <- sites <- lapply(private$sites,
                                                                function(x) list(name = x$name,
                                                                                url = x$url,
                                                                                localhost = x$localhost,
                                                                                dataFileName = x$dataFileName,
                                                                                instanceId = if (x$localhost) x$name else instanceId,
                                                                                token = x$token,
                                                                                jobId = jobId))
                                 ## Create instance objects
                                 sitesOK <- sapply(sites,
                                                   function(x) {
                                                       payload <- if (is.null(x$dataFileName)) {
                                                                      list(defnId = defn$id, instanceId = x$instanceId)
                                                                  } else {
                                                                      list(defnId = defn$id, instanceId = x$instanceId,
                                                                           dataFileName = x$dataFileName)
                                                                  }
                                                       q <- POST(url = .makeOpencpuURL(urlPrefix=x$url, fn="createInstanceObject"),
                                                                 body = toJSON(payload),
                                                                 add_headers("Content-Type" = "application/json"),
                                                                 config=getConfig()$sslConfig
                                                                 )
                                                       .deSerialize(q)
                                                   })

                                 ## I am not checking the value of p here; I do it later below
                                 if (!all(sitesOK)) {
                                     warning("run():  Some sites did not respond successfully!")
                                     private$sites <- sites <- sites[which(sitesOK)]  ## Only use sites that created objects successfully.
                                 }
                                ## stop if no sites
                                debug <- private$debug
                                if (debug) {
                                    print("runMRS(): checking p.")
                                }
                                pVals <- sapply(sites,
                                                function(x) {
                                                    payload <- list(projectname = as.character(private$defnId),
                                                                jobid = as.character(jobId),
                                                                method="getP",
                                                                methodparams = toJSON(list()))
                                                    print(sprintf("runMRS: Calling ProcessJob for site '%s' ", as.character(x$url)))
                                                    print(sprintf("runMRS: Auth header '%s' ", as.character(x$token)))
                                                    print(payload, row.names = FALSE)

                                                    q <- POST(url = x$url,
                                                            body = payload,
                                                            add_headers("Content-Type" = "application/json",
                                                                        "Authorization" = as.character(x$token)),
                                                            encode = "json")
                                                    resultJSON <- jsonlite::fromJSON(content(q, "text"))
                                                    pVal = as.numeric(resultJSON$outputParameters$Result[1])
                                                    print(sprintf("runMRS: GetP Return value is '%d'", pVal))
                                                    return(pVal)
                                                })
                                print("Printing pVals...")
                                if (debug) {
                                print(pVals)
                                }
                                if (any(pVals != pVals[1])) {
                                stop("run(): Heterogeneous sites! Stopping!")
                                }
                                p <- pVals[1]
                                if (debug) {
                                print(paste("p is ", p))
                                }

                                ## DO Newton-Raphson
                                control <- coxph.control()
                                prevBeta <- beta <- rep(0, p)
                                m <- prevloglik <- self$logLik(beta, jobid = jobId, MRSContext = TRUE)
                                iter <- 0
                                returnCode <- 0
                                repeat {
                                beta <- beta - solve(attr(m, "hessian")) %*% attr(m, "gradient")
                                iter <- iter + 1
                                m <- self$logLik(beta, jobid = jobId, MRSContext = TRUE)
                                if (abs(m - prevloglik) < control$eps) {
                                    break
                                }
                                if (iter >= control$iter.max) {
                                    returnCode <- 1
                                    break
                                }
                                prevBeta <- beta
                                prevloglik <- m
                                if (debug) {
                                    print(beta)
                                }
                                }
                                private$result <- result <- list(beta = beta,
                                                                var = -solve(attr(m, "hessian")),
                                                                gradient = attr(m, "gradient"),
                                                                iter = iter,
                                                                returnCode = returnCode)

                                print("runMRS: Returning result..")
                                return(result)
                             }
                            }
                         ))
)
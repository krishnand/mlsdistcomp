#!/usr/bin/env RScript

# These packages to have be installed
# for the bootstrapper to work

print('Starting bootstrap routine...')

print('Loading mrsdeploy...')
library(mrsdeploy)

print('Loading distcomp...')
library(distcomp)

print('Loading mlsdistcomp...')
library(mlsdistcomp)


##############################
#
# FUNCTIONS
#
##############################

#' Create a login session for Machine Learning Server
#' A valid MLS session is required for this function to succeeed.
#'
#' @param url url of the Machine Learning Server to connect to
#' @param username username to connect as
#' @param password password for the login user
#'
#' @return
#' @export
#'
#' @examples
mlsLogin <- function(url,
                    username,
                    password) {
  require(mrsdeploy)
  print('Executing mrsdeploy::remoteLogin...')
  mrsdeploy::remoteLogin(url,
                         username=username,
                         password=password,
                         session = FALSE)
  print('mrsdeploy::remoteLogin done')
}

#' Register services with Machine Learning Server
#' A valid MLS session is required for this function to succeeed.
#'
#' @param profile Profile of the site. Expected "Central" or "Participant".
#'
#' @return None
#' @export
#'
#' @examples
#' register('Central')
register <- function(profile,scriptpath){

  require(mrsdeploy)

  # The model parameter requires the full path to the
  # mlsdistcomp.R file. We compute this and pass it to
  # the functions below.

  if(profile == "Central" || profile == "central"){
    print('Registering central services')
    register_central_webservices(scriptpath)
  } else {
    print('Registering participant services')
    register_participant_webservices(scriptpath)
  }
}

#' Unregister all MLS web services
#'
#' @param profile Profile of the site. Expected "Central" or "Participant".
#'
#' @return None
#' @export
#'
#' @examples
#' unregister('Central')
unregister <- function(profile){
  require(mrsdeploy)

  if(profile == "Central" || profile == "central") {

    print('Unregistering central services')

    deleteService("RegisterComputations", "v1")
    deleteService("GetParticipants", "v1")
    deleteService("RegisterParticipant", "v1")
    deleteService("GetSchemas", "v1")
    deleteService("RegisterSchema", "v1")
    deleteService("GetComputationProjects", "v1")
    deleteService("ProposeComputation", "v1")
    deleteService("EnrollInProject", "v1")
    deleteService("GetProjectParticipants", "v1")
    deleteService("TriggerJob", "v1")
    deleteService("GetJobInfo", "v1")
    deleteService("GetProjectJobs", "v1")

  } else{

    print('Unregistering participant services')

    deleteService("RegisterComputations", "v1")
    deleteService("RegisterMaster", "v1")
    deleteService("AckSchemaRegistration", "v1")
    deleteService("GetDataSources", "v1")
    deleteService("CreateCSVDataSource", "v1")
    deleteService("AckProposeComputation", "v1")
    deleteService("ProcessJob", "v1")
  }
}

register_central_webservices <- function(mlsdistcomppath) {

  #' Function that registers computations from distcomp package
  #' into the mlsdistcomp backend.
  #'
  #' @return
  #' @export
  #'
  #' @examples
  registerComputations <- function() {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    computationObj <- Computation$new()
    resultList <- computationObj$registerAllComputations()
    computationObj$finalize()
    Result <- paste0("The following computations were registered: ", print(resultList, row.names = FALSE))
    return(Result)
  }

  api_registerComputations <- publishService(
    "RegisterComputations",
    code = registerComputations,
    model = mlsdistcomppath,
    inputs = list(),
    outputs = list(Result = "character"),
    v = "v1"
  )

  getParticipants <- function() {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    participantObj <- Participant$new()
    participants = participantObj$getParticipants()
    Result = apply(participants, 1, list)
    participantObj$finalize()
    return(Result)
  }

  api_getParticipants <- publishService(
    "GetParticipants",
    code = getParticipants,
    model = mlsdistcomppath,
    inputs = list(),
    outputs = list(Result = "data.frame"),
    v = "v1"
  )

  #
  # Participant::RegisterParticipant
  #
  registerParticipant <- function(name, clientid, tenantid, url, clientsecret) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    participantObj <- Participant$new()
    participants = participantObj$getParticipants()

    # Delete the participant if it exists.
    if(!is.null(participants) && nrow(participants) > 0){
      print("Participant exists. Removing...")
      participantObj$deleteParticipants(as.character(name))
    }

    print(sprintf("Re-registering participant '%s'...", name))
    Id <- participantObj$registerParticipant(name,
                                             clientid,
                                             tenantid,
                                             url,
                                             clientsecret)
    participantObj$finalize()
    print("Participant registration was successful.")
    return(Id)
  }

  api_registerParticipant <- publishService(
    "RegisterParticipant",
    code = registerParticipant,
    model = mlsdistcomppath,
    inputs = list(name = "character",
                  clientid = "character",
                  tenantid = "character",
                  url = "character",
                  clientsecret = "character"),
    outputs = list(Id = "character"),
    v = "v1"
  )

  #
  # DataCatalog::GetSchemas
  #
  getSchemas <- function(schemaname) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    dataCatalogObj <- DataCatalog$new()
    if(is.null(schemaname) || schemaname == ""){
      schemas = dataCatalogObj$getSchemaByName()
    }
    else{
      schemas = dataCatalogObj$getSchemaByName(schemaname)
    }
    Result = apply(schemas, 1, list)
    dataCatalogObj$finalize()
    return(Result)
  }

  api_getSchemas <- publishService(
    "GetSchemas",
    code = getSchemas,
    model = mlsdistcomppath,
    inputs = list(schemaname = "character"),
    outputs = list(Result = "data.frame"),
    v = "v1"
  )

  #
  # DataCatalog::RegisterSchema
  #
  registerSchema <- function(schemaname, schemadesc, schema, broadcast) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    Result = NULL
    # Verify if schema exists for the computation
    dataCatalogObj <- DataCatalog$new()
    dataCatalogDataFrame = dataCatalogObj$getSchemaByName(schemaname)
    if(nrow(dataCatalogDataFrame) != 0){
      stop(sprintf("Schema '%s' defined already. Define schema with a different name.", schemaname))
    }

    schemadf <- as.data.frame(fromJSON(schema))
    id <- dataCatalogObj$registerSchema(schemaname,
                                        schemadesc,
                                        schemadf)
    dataCatalogObj$finalize()
    Result = sprintf("Schema '%s' registered successfully.", schemaname)

    if(as.logical(broadcast)) {

      # Refresh all participant tokens. No ROI with optimizing this.
      print("Refreshing participant access tokens...")
      participantsObj = Participant$new()
      participantsObj$refreshAADToken()
      participantsObj$finalize()

      # Broadcast schema to all sites
      workerendpoint= 'AckSchemaRegistration/v1'
      Result = sprintf("Schema '%s' successfully registered across all sites.", schemaname)
      status = dataCatalogObj$broadcastSchemaInfo(schemaname,
                                                  schemadesc,
                                                  schema,
                                                  workerendpoint)
      if(!status){
        Result = "One or more sites could not register the schema. Please review and update."
      }
    }
    return(Result)
  }

  api_registerSchema <- publishService(
    "RegisterSchema",
    code = registerSchema,
    model = mlsdistcomppath,
    inputs = list(schemaname = "character",
                  schemadesc = "character",
                  schema = "character",
                  broadcast = "logical"),
    outputs = list(Result = "character"),
    v = "v1"
  )

  #
  # ComputationInfo::GetComputationProjects
  #
  getComputationProjects <- function(projectname) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    computationInfoObj <- ComputationInfo$new()
    if(projectname != ""){
      computationProjects = ComputationInfoObj$getComputationInfoByName(projectname)
    }else {
      computationProjects = computationInfoObj$getAllComputationInfo()
    }
    Result = apply(computationProjects, 1, list)
    computationInfoObj$finalize()
    return(Result)
  }

  api_getgetComputationProjects <- publishService(
    "GetComputationProjects",
    code = getComputationProjects,
    model = mlsdistcomppath,
    inputs = list(projectname = "character"),
    outputs = list(Result = "data.frame"),
    v = "v1"
  )

  #
  # ComputationInfo: Propose new project and broadcast to all participants.
  #
  proposeComputation <- function(projectname,
                                 projectdesc,
                                 formula,
                                 schemaname,
                                 computationtype,
                                 broadcast) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    # Verify if computation type exists
    computationObj <- Computation$new()
    computationsDataFrame = computationObj$getComputations()
    computationObj$finalize()
    if(nrow(computationsDataFrame) == 0){
      stop("No computation types were found in the MASTER. Computations must be defined before proceeding.")
    }

    if(!any(computationsDataFrame$Name==computationtype)){
      stop(sprintf("Computation type with name '%s' NOT found. Use appropriate computation type before proceeding.", computationtype))
    }

    # Verify if schema exists for the computation
    schemaObj <- DataCatalog$new()
    schemaDataFrame = schemaObj$getSchemaByName(schemaname)
    schemaObj$finalize()
    if(nrow(schemaDataFrame) == 0){
      stop(sprintf("Schema '%s' not defined. Define schema before proposing a new computation.", schemaname))
    }

    # Create computation at Master
    computationInfoObj <- ComputationInfo$new()
    computationInfoDataFrame = computationInfoObj$getComputationInfoByName(projectname)
    if(nrow(computationInfoDataFrame) > 0){
      stop(sprintf("Computation project '%s' is already defined. Please propose computation with a different name.", projectname))
    }

    id = computationInfoObj$createComputationInfo(projectname,
                                                  projectdesc,
                                                  formula,
                                                  schemaname,
                                                  computationtype)
    computationInfoObj$finalize()
    Result = sprintf("Computation project created successfully in MASTER with identifier '%s'", id)

    if(as.logical(broadcast)) {

      # Refresh all participant tokens. No ROI with optimizing this.
      print("Refreshing participant access tokens...")
      participantsObj = Participant$new()
      participantsObj$refreshAADToken()
      participantsObj$finalize()

      # Broadcast computation to all sites
      workerendpoint= 'AckProposeComputation/v1'
      Result = sprintf("Computation proposal '%s' successfully setup across all sites.", projectname)
      computationInfoObj = ComputationInfo$new()
      status = computationInfoObj$broadcastComputationInfo(projectname,
                                                           projectdesc,
                                                           formula,
                                                           schemaname,
                                                           computationtype,
                                                           workerendpoint)
      computationInfoObj$finalize()
      if(!status){
        Result = "One or more sites could not accept proposed computation. Please review and update."
      }
    }
    return(Result)
  }

  api_proposeComputation <- publishService(
    "ProposeComputation",
    code = proposeComputation,
    model = mlsdistcomppath,
    inputs = list(projectname = "character",
                  projectdesc = "character",
                  formula = "character",
                  schemaname = "character",
                  computationtype = "character",
                  broadcast = "logical"),
    outputs = list(Result = "character"),
    v = "v1"
  )

  #
  # Service to enroll a participant in a project
  #
  enrollInProject <- function(projectname,
                              participantname,
                              operation) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    # Verify project exists
    computationInfoObj <- ComputationInfo$new()
    computationInfoDataFrame = computationInfoObj$getComputationInfoByName(projectname)
    if(is.null(computationInfoDataFrame) || nrow(computationInfoDataFrame) == 0){
      stop(sprintf("Computation project '%s' is NOT defined. Specify a valid projectname or create one before proceeding.", projectname))
    }
    computationInfoObj$finalize()

    # Enroll or unenroll participant in project
    projectParticipantsObj <- ComputationInfoParticipants$new()
    projectParticipantsDataFrame = projectParticipantsObj$getParticipantsOfAProject(projectname)
    if(is.null(projectParticipantsDataFrame) || nrow(projectParticipantsDataFrame) == 0){

      if(operation == "Enroll" || operation == "enroll") {
        sprintf("Project '%s' has no participants. Adding '%s'...", projectname, participantname)
        projectParticipantsObj$create(projectname, participantname)
        sprintf("Participant '%s' successfully enrolled in project '%s'.", participantname, projectname)
      }

    } else {

      sprintf("Project '%s' has participants. Check if participant '%s' is already enrolled...", projectname, participantname)
      participantProjectDataFrame = projectParticipantsDataFrame[projectParticipantsDataFrame$participantname==participantname, ]
      if(!is.null(participantProjectDataFrame) && nrow(participantProjectDataFrame) == 1) {

        if(operation == "Enroll" || operation == "enroll") {
          sprintf("Participant '%s' is already enrolled in project '%s'.", participantname, projectname)
        } else {
          sprintf("Unenrolling participant '%s' from project '%s'.", participantname, projectname)
          projectParticipantsObj$deleteProjectParticipant(projectname, participantname)
        }

      } else {

        if(operation == "Enroll" || operation == "enroll") {
          projectParticipantsObj$create(projectname, participantname)
          sprintf("Participant '%s' successfully enrolled in project '%s'.", participantname, projectname)
        } else {

          sprintf("Unenrolling all participants from project '%s'.", projectname)
          projectParticipantsObj$deleteProjectParticipant(projectname, NULL)

        }
      }
    }
    projectParticipantsObj$finalize()
  }

  api_enrollInProject <- publishService(
    "EnrollInProject",
    code = enrollInProject,
    model = mlsdistcomppath,
    inputs = list(projectname = "character",
                  participantname = "character",
                  operation = "character"),
    v = "v1"
  )

  #
  # ComputationInfoParticipant::GetProjectParticipants
  #
  getProjectParticipants <- function(projectname) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    computationInfoParticipantsObj <- ComputationInfoParticipants$new()
    if(is.null(projectname) || projectname == ""){
      projectParticipants = computationInfoParticipantsObj$getAllComputationInfoParticipants()
    }
    else {
      projectParticipants = ComputationInfoParticipantsObj$getParticipantsOfAProject(projectname)
    }

    Result = apply(projectParticipants, 1, list)
    computationInfoParticipantsObj$finalize()
    return(Result)
  }

  api_getProjectParticipants <- publishService(
    "GetProjectParticipants",
    code = getProjectParticipants,
    model = mlsdistcomppath,
    inputs = list(projectname = "character"),
    outputs = list(Result = "data.frame"),
    v = "v1"
  )


  #
  # ComputationInfoJob::TriggerJob
  #
  triggerJob <- function(projectname, jobid) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    # Refresh all participant tokens. No ROI with optimizing this.
    print("Refreshing participant access tokens...")
    participantsObj = Participant$new()
    participantsObj$refreshAADToken()
    participantsObj$finalize()

    # DEFAULTING!!!!.. Expected to be same for all worker nodes or this must be parameterized into
    # participants if they want to expose different processing endpoints.
    workerendpointname <- 'ProcessJob/v1'

    computationInfoJobObj <- ComputationInfoJob$new()
    Result <- computationInfoJobObj$triggerJob(projectname, jobid, workerendpointname)
    computationInfoJobObj$finalize()
    return(Result)
  }

  api_triggerJob <- publishService(
    "TriggerJob",
    code = triggerJob,
    model = mlsdistcomppath,
    inputs = list(projectname = "character",
                  jobid = "character"),
    outputs = list(Result = "character"),
    v = "v1"
  )


  #
  # ComputationInfoJob::GetJobInfo
  #
  getJobInfo <- function(jobid) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    computationInfoJobObj <- ComputationInfoJob$new()
    Result <- computationInfoJobObj$getJobById(jobid)

    # Removing logtxt and operation columns
    dropcols <- c("LogTxt","Operation")

    computationInfoJobObj$finalize()
    return(Result[ , !(names(Result) %in% dropcols)])
  }

  api_getJobInfo <- publishService(
    "GetJobInfo",
    code = getJobInfo,
    model = mlsdistcomppath,
    inputs = list(jobid = "character"),
    outputs = list(Result = "data.frame"),
    v = "v1"
  )

  #
  # ComputationInfoJob::GetProjectJobs
  #
  getProjectJobs <- function(projectname) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    computationInfoJobObj <- ComputationInfoJob$new()
    if(is.null(projectname) || projectname == ""){
      computationInfoJobs <- computationInfoJobObj$getJobsForProject(NULL)
    }
    else {
      computationInfoJobs <- computationInfoJobObj$getJobsForProject(projectname)
    }
    Result = apply(computationInfoJobs, 1, list)
    computationInfoJobObj$finalize()
    return(Result)
  }

  api_getProjectJobs <- publishService(
    "GetProjectJobs",
    code = getProjectJobs,
    model = mlsdistcomppath,
    inputs = list(projectname = "character"),
    outputs = list(Result = "data.frame"),
    v = "v1"
  )

  # Invoke register computations to register all available
  # computation types in the SQL backend
  registerComputations()
}

register_participant_webservices <- function(mlsdistcomppath){

  #' Function that registers computations from distcomp package
  #' into the mlsdistcomp backend.
  #'
  #' @return
  #' @export
  #'
  #' @examples
  registerComputations <- function() {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    computationObj <- Computation$new()
    resultList <- computationObj$registerAllComputations()
    computationObj$finalize()
    Result <- paste0("The following computations were registered: ", print(resultList, row.names = FALSE))
    return(Result)
  }

  api_registerComputations <- publishService(
    "RegisterComputations",
    code = registerComputations,
    model = mlsdistcomppath,
    inputs = list(),
    outputs = list(Result = "character"),
    v = "v1"
  )

  registerMaster <- function(name, clientid, tenantid, url, clientsecret) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    participantObj <- Participant$new()
    participants = participantObj$getParticipants()

    # Only one Participant record exists on site - that of master.
    # Check and delete if any.
    if(!is.null(participants) && nrow(participants) > 0){

      participantObj$deleteParticipants()
    }

    # Re-register the master
    Id <- participantObj$registerParticipant(name,
                                             clientid,
                                             tenantid,
                                             url,
                                             clientsecret)

    participantObj$finalize()

    return(Id)
  }

  api_registerMaster <- publishService(
    "RegisterMaster",
    code = registerMaster,
    model = mlsdistcomppath,
    inputs = list(name = "character",
                  clientid = "character",
                  tenantid = "character",
                  url = "character",
                  clientsecret = "character"),
    outputs = list(Id = "character"),
    v = "v1"
  )


  processJob <- function(projectname, jobid, method, methodparams) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    require(rlist)
    library(distcomp)
    library(mlsdistcomp)

    resultNumeric = NA
    resultList = list()
    resultType = NULL

    computationInfoJobObj <- ComputationInfoJob$new()
    print("Invoke ProcessJob")
    resultDataFrame <- computationInfoJobObj$processJob(jobid, projectname, method, methodparams)
    computationInfoJobObj$finalize()
    return(Result=resultDataFrame)
  }

  api_processJob <- publishService(
    "ProcessJob",
    code = processJob,
    model = mlsdistcomppath,
    inputs = list(projectname = "character",
                  jobid = "character",
                  method = "character",
                  methodparams = "character"),
    outputs = list(Result = "data.frame"),
    v = "v1"
  )


  #
  #
  #
  ackProposeComputation <- function(sitename,
                                    projectname,
                                    projectdesc,
                                    formula,
                                    schemaname,
                                    computationtype) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    # Verify if computation type exists
    computationObj <- Computation$new()
    computationsDataFrame = computationObj$getComputations()
    computationObj$finalize()
    if(nrow(computationsDataFrame) == 0){
      stop(sprintf("No computation types were found in the site '%s'. Define computations before proceeding.", sitename))
    }

    if(!any(computationsDataFrame$Name==computationtype)){
      stop(sprintf("Computation type with name '%s' NOT found at site '%s'.", computationtype, sitename))
    }

    # Verify if schema exists for the computation
    schemaObj <- DataCatalog$new()
    schemaDataFrame = schemaObj$getSchemaByName(schemaname)
    schemaObj$finalize()
    if(nrow(schemaDataFrame) == 0){
      stop(sprintf("Schema '%s' not defined at site. Define schema before proposing a computation.", schemaname))
    }

    # Create computation at Site
    ComputationInfoObj <- ComputationInfo$new()
    computationInfoDataFrame = ComputationInfoObj$getComputationInfoByName(projectname)
    if(nrow(computationInfoDataFrame) > 0){
      stop(sprintf("Computation project '%s' is already defined. Proposing computation with a different name.", projectname))
    }

    id <- ComputationInfoObj$createComputationInfo(projectname,
                                                   projectdesc,
                                                   formula,
                                                   schemaname,
                                                   computationtype)
    Result <- sprintf("Computation broadcast to site '%s' was successful. Proposed computation registered on site with id '%s'", sitename, id)
    ComputationInfoObj$finalize()
    return(Result)
  }

  api_ackProposeComputation <- publishService(
    "AckProposeComputation",
    code = ackProposeComputation,
    model = mlsdistcomppath,
    inputs = list(sitename = "character",
                  projectname = "character",
                  projectdesc = "character",
                  formula = "character",
                  schemaname = "character",
                  computationtype = "character"),
    outputs = list(Result = "character"),
    v = "v1"
  )

  #
  #
  #
  ackSchemaRegistration <- function(sitename,
                                    schemaname,
                                    schemadesc,
                                    schema) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    # Verify if computation type exists
    computationObj <- Computation$new()
    computationsDataFrame = computationObj$getComputations()
    computationObj$finalize()
    if(nrow(computationsDataFrame) == 0){
      stop(sprintf("No computation types were found in the site '%s'. Define computations before proceeding.", sitename))
    }

    Result = NULL
    # Verify if schema exists for the computation
    dataCatalogObj <- DataCatalog$new()
    dataCatalogDataFrame = dataCatalogObj$getSchemaByName(schemaname)
    if(nrow(dataCatalogDataFrame) != 0){
      stop(sprintf("Schema '%s' is already defined at site '%s'", schemaname, sitename))
    }

    schemadf <- as.data.frame(fromJSON(schema))
    id <- dataCatalogObj$registerSchema(schemaname,
                                        schemadesc,
                                        schemadf)
    dataCatalogObj$finalize()
    Result <- sprintf("Schema '%s' broadcast to site '%s' was successful. Registered on site with id '%s'.", schemaname, sitename, id)
    return(Result)
  }

  api_ackSchemaRegistration <- publishService(
    "AckSchemaRegistration",
    code = ackSchemaRegistration,
    model = mlsdistcomppath,
    inputs = list(sitename = "character",
                  schemaname = "character",
                  schemadesc = "character",
                  schema = "character"),
    outputs = list(Result = "character"),
    v = "v1"
  )

  #
  # Web service to create a new CSV data source
  #
  createDataSource <- function(schemaname,
                               datasourcename,
                               datasourcedesc,
                               datasourcelocation) {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    #
    # Verify if schema of the data source exists
    #
    dataCatlogObj <- DataCatalog$new()
    schemas = dataCatlogObj$getSchemaByName(as.character(schemaname))
    dataCatlogObj$finalize()
    if(is.null(schemas) || nrow(schemas) == 0){
      stop(sprintf("Schema with name '%s' does not exist. Data source can only be configured for existing schemas.", schemaname))
    }

    #
    # Define a CSV data source
    #
    dataSourcesObj <- DataSources$new()
    currentDSDataFrame = dataSourcesObj$getDataSourcesByName(as.character(datasourcename))
    if(!is.null(currentDSDataFrame) && nrow(currentDSDataFrame) > 0){
      stop(sprintf("Datasource with name '%s' already exists.Specify a unique name for the data source.", datasourcename))
    }
    newCSVDSDataFrame <- dataSourcesObj$createCSVDataSource(datasourcename,
                                                            datasourcedesc,
                                                            schemaname,
                                                            datasourcelocation,
                                                            ",")
    dataSourcesObj$finalize()
    if(!is.null(newCSVDSDataFrame)) {
      Result <- sprintf("Data source creation '%s' for schema '%s' was successful.", datasourcename, schemaname)
    }
    return(Result)
  }

  api_createDataSource <- publishService(
    "CreateCSVDataSource",
    code = createDataSource,
    model = mlsdistcomppath,
    inputs = list(schemaname = "character",
                  datasourcename = "character",
                  datasourcedesc = "character",
                  datasourcelocation = "character"),
    outputs = list(Result = "character"),
    v = "v1"
  )

  #
  # Web service to get all data sources
  #
  getDataSources <- function() {
    require(stringr)
    require(uuid)
    require(lubridate)
    require(httr)
    require(jsonlite)
    require(curl)
    require(RODBC)
    require(R6)
    library(distcomp)
    library(mlsdistcomp)

    #
    # Get all data sources
    #
    dataSourcesObj <- DataSources$new()
    dataSources = dataSourcesObj$getDataSourcesByName()
    Result = apply(dataSources, 1, list)
    dataSourcesObj$finalize()
    return(Result)
  }

  api_getDataSources <- publishService(
    "GetDataSources",
    code = getDataSources,
    model = mlsdistcomppath,
    inputs = list(),
    outputs = list(Result = "data.frame"),
    v = "v1"
  )

  # Register all computation types in the distcomp package with
  # the SQL backend
  registerComputations()

}

##############################
#
# MAIN
#
##############################
print('Inspecting and printing args...')
args = commandArgs(trailingOnly=TRUE)
print(args)

if (length(args)<5) {
  stop("Expected at least 5 arguments.", call.=FALSE)
} else if (length(args)>=5) {

  profile <- args[1]
  url <- args[2]
  user <- args[3]
  pwd <- args[4]
  mlsdistcomppath <<- args[5]
  if(length(args)==6){
    fn <- args[6]
  } else{
    fn <- 'register'
  }

  print('Calling mlslogin..')
  mlsLogin(url=url, username=user, password=pwd)

  if(fn == 'Register' || fn == 'register') {
    do.call(fn, list(as.character(profile),as.character(mlsdistcomppath)))
  } else if(fn == 'Unregister' || fn == 'unregister') {
    do.call(fn, list(as.character(profile)))
  } else {
    sprintf("Function %s is unknown", fn)
  }

  print('Completed bootstrap routine.')
}

# Load all libraries needed
library(stringr)
library(uuid)
library(lubridate)
library(httr)
library(jsonlite)
library(curl)
library(RODBC)
library(R6)
library(rlist)
library(distcomp)

#' Base class that parameterizes all database and other common
#' functions for the MRSDistCompMetamodel classes
#'
#' @docType class
#' @importFrom R6 R6Class
#' @importFrom lubridate now
#' @importFrom uuid UUIDgenerate
#' @importFrom RODBC sqlQuery
#' @export
#' @return Object of \code{\link{R6Class}} with methods for communication with backend MRSDistComp database.
#' @format \code{\link{R6Class}} object.
#' @examples
#' MRSDistCompBase$new()
#' @section Methods:
#'
#' \describe{
#'   \item{\code{new()}}{This method is used to create an object of this class. This initializes a new ODBC connection to the target database.}
#'   \item{\code{finalize(name,clientid,tenantid,isenabled=1,validfrom=NULL,validto=NULL)}}{This method creates a new Participant or collaborating party that will interact with the current deployment.}
#'   \item{\code{create(...,tablename)}}{Parameterized function that creates an SQL record in the specified tablename. The key/values in the varargs is used for the column names/values respectively.}
#'   \item{\code{read(...,tablename)}}{Parameterized function that reads SQL records from the specified tablename. The key/values in the varargs are used as AND-ed where filters in the query.}
#'   \item{\code{delete(...,tablename)}}{Parameterized function that deletes SQL record(s) in the specified tablename. The key/values in the varargs are used as AND-ed where filters in the query.}}
MRSDistCompBase <- R6Class(
  "MRSDistCompBase",
  public = list (
    computeContext = list(),
    token_cache_filepath = NULL,
    initialize = function() {

      # Initialize global context/vars
      private$init_global_context()

      # Read secrets file
      db_info_df <- read.csv(file=private$db_info_filepath, header=TRUE, sep=",")
      if(nrow(db_info_df) != 1) stop('Database info csv has no valid content')
      private$connStr <- sprintf(private$connStrFormat,
          as.character(db_info_df$SQL_SERVERNAME),
          as.character(db_info_df$SQL_DBNAME),
          as.character(db_info_df$SQL_USER),
          as.character(db_info_df$SQL_USERPWD))

      # Create db connection
      private$create_dbconnection()

      # If data folder does not exist, create it
      ifelse(!dir.exists(file.path(self$computeContext$datafolder)), dir.create(self$computeContext$datafolder), FALSE)

      # Return self
      invisible(self)
    },
    finalize = function() {
      if (!is.null(private$dbhandle)) {
        odbcClose(private$dbhandle)
      }
      odbcCloseAll()
    },
    create = function(..., tablename) {
      varargs <- list(...)
      cols <- list()
      colvals <- list()

      for (i in seq_along(varargs)) {
        cols = c(cols, names(varargs)[i])
        colvals = c(colvals, varargs[[i]])
      }

      # Generic sql insert
      createStmt <-
        sprintf("insert into %s (%s) values(%s)",
                tablename,
                paste0(cols, collapse = ","),
                paste0("'", paste0(colvals, sep = "", collapse = "','"), "'"))

      tryCatch(sqlQuery(private$dbhandle, createStmt),
               warning=function(w){print("FAIL! (warning)");return(NA)},
               error=function(e){print(paste("ERROR:",geterrmessage()));return(NA)})

    },
    read = function(queryFilter, tablename) {
      # Generic sql read
      if (is.null(queryFilter)) {
        queryFilter <- "1=1"
      }
      readStmt <- sprintf("select * from %s where %s",
                          tablename,
                          queryFilter)
      data <- sqlQuery(private$dbhandle, readStmt, errors = TRUE)
      return(data)

    },
    update = function(setStmt, filterStmt, tablename) {


      # Update stmt
      updateStmt <- sprintf("update %s set %s where %s",
                            tablename,
                            setStmt,
                            filterStmt)

      tryCatch(sqlQuery(private$dbhandle, updateStmt),
               warning=function(w){print("FAIL! (warning)");return(NA)},
               error=function(e){print(paste("ERROR:",geterrmessage()));return(NA)})

    },
    delete = function(deleteFilter, tablename) {
      # Generic sql read
      if (is.null(deleteFilter)) {
        deleteFilter <- "1=1"
      }
      deleteStmt <-
        sprintf("delete from %s where %s",
                tablename,
                deleteFilter)

      tryCatch(sqlQuery(private$dbhandle, deleteStmt),
               warning=function(w){print("FAIL! (warning)");return(NA)},
               error=function(e){print(paste("ERROR:",geterrmessage()));return(NA)})
    },
    getAADToken = function(sitename,
                           tenantId,
                           clientId,
                           clientSecret,
                           authority = 'https://login.windows.net',
                           useTokensFromCache=FALSE){

      authorizationHeader = NULL

      # NOTE: The current MRS config uses simply the same app as both the
      # resource and client. This id is represented by the ClientId.
      # Using the same value hence for "resourceId"
      resourceId = clientId
      requestURI = paste0(authority, "/", tenantId, "/oauth2/token")

      h <- new_handle()
      handle_setform(h,
                     "grant_type"="client_credentials",
                     "resource"=as.character(resourceId),
                     "client_id"=as.character(clientId),
                     "client_secret"=as.character(clientSecret)
      )

      req <- curl_fetch_memory(requestURI, handle = h)
      res <- fromJSON(rawToChar(req$content))
      accessToken = res$access_token
      authorizationHeader = paste0("Bearer ", accessToken)

      # Create cache file if it does not exist
      if(!file.exists(self$token_cache_filepath)){

        tokendf <- data.frame(siteid=character(), token=character(), stringsAsFactors = FALSE)
        write.table(tokendf,
                    file=self$token_cache_filepath,
                    append = FALSE,
                    row.names = FALSE,
                    col.names = TRUE,
                    quote = TRUE,
                    sep = ",")
      }

      # Check if token exists for site
      tokencachedf = as.data.frame(read.table(file=self$token_cache_filepath, header=TRUE, sep=",", stringsAsFactors = FALSE))
      sitedf = subset(tokencachedf, tokencachedf$siteid == sitename)

      # Token does not exist for site. Append new token row.
      if(is.null(sitedf) || nrow(sitedf) == 0) {

        currentSite <- list(siteid=sitename, token=authorizationHeader)
        write.table(as.data.frame(currentSite, stringsAsFactors = FALSE),
                    file = self$token_cache_filepath,
                    append = TRUE,
                    row.names = FALSE,
                    col.names = FALSE,
                    quote = TRUE,
                    sep = ",")
      }
      else {

        tokencachedf[tokencachedf$siteid == as.character(sitename), "token"] <- as.character(authorizationHeader)
        write.table(tokencachedf,
                    file = self$token_cache_filepath,
                    append = FALSE,
                    row.names = FALSE,
                    col.names = TRUE,
                    quote = TRUE,
                    sep = ",")
      }

      return(authorizationHeader)
    },
    getAADTokenFromCache = function(sitename){
      if(!file.exists(self$token_cache_filepath)){
        stop(sprintf("Token cache file '%s' not found", self$token_cache_filepath))
      }

      tokencachedf = read.table(file=self$token_cache_filepath, header=TRUE, sep=",")
      sitedf = subset(tokencachedf, siteid == sitename)
      if(is.null(sitedf) || nrow(sitedf) == 0) {
        stop(sprintf("Token not found for site '%s'. Refresh site token before proceeding.", sitename))
      }
      return(sitedf$token)
    }
  ),
  private = list(
    connStrFormat = NULL,
    connStr = NULL,
    dbhandle = NULL,
    datafolder_linux = '/var/lib/mlsdistcomp',
    datafolder_windows = 'C:/ProgramData/mlsdistcomp',
    db_info_filename = 'mlsdbsecrets.csv',
    db_info_filepath = NULL,
    token_cache_filename = 'mlstokencache.csv',
    get_new_connection = function() {
      if(is.null(private$dbhandle)) {
        odbcClose(private$dbhandle)
        private$dbhandle = NULL
      }
      private$create_dbconnection()
      return(private$dbhandle)
    },
    create_dbconnection = function() {
      # Get db handle
      private$dbhandle <- odbcDriverConnect(private$connStr,  rows_at_time = 1)
      odbcSetAutoCommit(private$dbhandle, autoCommit = TRUE)
    },
    init_global_context = function() {

      # Initialize global vars for use
      if (.Platform$OS.type == "windows") {
        self$computeContext$datafolder = private$datafolder_windows
        private$db_info_filepath = paste0(private$datafolder_windows,'/',private$db_info_filename)
        self$token_cache_filepath = paste0(self$computeContext$datafolder, '/', private$token_cache_filename)
        private$connStrFormat = 'driver={SQL Server};server=%s;database=%s;uid=%s;pwd=%s'
      } else if (Sys.info()["sysname"] == "Darwin") {
        "mac"
      } else if (.Platform$OS.type == "unix") {
        self$computeContext$datafolder = private$datafolder_linux
        private$db_info_filepath = paste0(private$datafolder_linux,'/',private$db_info_filename)
        self$token_cache_filepath = paste0(self$computeContext$datafolder, '/', private$token_cache_filename)
        # !!!/etc/odbcinst.ini on Ubuntu DSVM defines this default driver!!!
        private$connStrFormat = 'driver={ODBC Driver 13 for SQL Server};server=%s;database=%s;uid=%s;pwd=%s'
      } else {
        stop("Unknown OS")
      }
    }
  )
)


#' Class that manages all Participants or collaborators in
#' the MRSDistComp application.
#'
#' @docType class
#' @importFrom R6 R6Class
#' @importFrom lubridate now
#' @importFrom uuid UUIDgenerate
#' @importFrom RODBC sqlQuery
#' @export
#' @return Object of \code{\link{R6Class}} with methods for communication with backend MRSDistComp database.
#' @format \code{\link{R6Class}} object.
#' @examples
#' Participant$new()
#' @field Id Unique identifier for the participant.
#' @field Name Name of the participant.
#' @field ClientId Application Id of the participant's Azure Active Directory Application.
#' @field TenantId Azure Active Directory Tenant name of the participant.
#' @field ClientSecret Client secret of the participant's Azure Active Directory Application.
#' @field Url Base Url of the MRS deployment. FOr e.g., https://mrsdistcomp1.westus.app.microsoft.com:12800/api.
#' @field IsEnabled Specifies if the participant is valid or enabled to be able to perform any operations.
#' @field ValidFrom Date since when the participant is active.
#' @field ValidTo Date till when the participant is active.Past date invalidates participant.
#' @section Methods:
#' \describe{
#'   \item{\code{new()}}{This method is used to create object of this class.}
#'   \item{\code{registerParticipant(name,clientid,tenantid,url,token,isenabled=1,validfrom=NULL,validto=NULL)}}{This method creates a new Participant or collaborating party that will interact with the current deployment.}
#'   \item{\code{getParticipants(nameFilter = NULL)}}{This method gets a list of all participants whose name is like the one specified by the nameFilter query. Passing NULL will fetch all Participants in the system.}}
#'   \item{\code{getParticipantById(id)}}{This method gets a Participant by Id.}}
Participant <- R6Class(
  "Participants",
  inherit = MRSDistCompBase,
  public = list(
    Id = NULL,
    Name = NULL,
    ClientId = NULL,
    TenantId = NULL,
    URL = NULL,
    ClientSecret = NULL,
    IsEnabled = 1,
    ValidFrom = (lubridate::now(tzone = "GMT")),
    ValidTo = (lubridate::now(tzone = "GMT") + dyears(1)),
    registerParticipant = function(name,
                                   clientid,
                                   tenantid,
                                   url,
                                   clientsecret=NULL,
                                   isenabled = 1,
                                   validfrom = NULL,
                                   validto = NULL) {

      # Create "this" object
      self$Id <- uuid::UUIDgenerate()
      self$Name <- name
      self$ClientId <- clientid
      self$TenantId <- tenantid
      self$URL <- url
      self$ClientSecret <- clientsecret
      self$IsEnabled <- isenabled
      if (!is.null(validfrom)) {
        self$ValidFrom <- validfrom
      }
      if (!is.null(validto)) {
        self$ValidTo <- validto
      }

      #Pass to the RODBC base class to create
      #the participant in the backend
      super$create(
        Id = self$Id,
        Name = self$Name,
        ClientId = self$ClientId,
        TenantId = self$TenantId,
        URL = self$URL,
        ClientSecret = self$ClientSecret,
        IsEnabled = self$IsEnabled,
        ValidFrom = as.character(self$ValidFrom),
        ValidTo = as.character(self$ValidTo),
        tablename = 'Participants'
      )

      #Return the local object back to the caller
      return(self$Id)
    },
    refreshToken = function(username = "admin",
                            password = "Welcome1234!")
    {
      participantsObj <- Participant$new()
      participantsDataFrame <- participantsObj$getParticipants()
      participantsDataFrame$URL <- gsub("*/api","/login", participantsDataFrame$URL)

      loginStatus = TRUE
      for(i in 1:nrow(participantsDataFrame)) {

        participant <- participantsDataFrame[i,]
        requestBody = list(username = username,
                           password = password)
        response <- POST(url = participant$URL,
                         add_headers("Content-Type" = "application/json"),
                         body = requestBody,
                         encode = "json")
        authorization = paste0("Bearer ", content(response)$access_token)
        setStmt = sprintf("Token = '%s'", authorization)
        filterStmt = sprintf("Name = '%s'", participant$Name)

        super$update(
          setStmt = setStmt,
          filterStmt = filterStmt,
          tablename = 'Participants'
        )

        loginStatus <- all(loginStatus, response$status == 200)
      }
      return(loginStatus)
    },
    refreshAADToken = function()
    {
      participantsObj <- Participant$new()
      participantsDataFrame <- participantsObj$getParticipants()

      loginStatus = TRUE
      for(i in 1:nrow(participantsDataFrame)) {

        participant <- participantsDataFrame[i,]

        accessToken = super$getAADToken(participant$Name,
                                        participant$TenantId,
                                        participant$ClientId,
                                        participant$ClientSecret)

        loginStatus <- all(loginStatus, !is.null(accessToken))
      }
      return(loginStatus)
    },
    getParticipants = function(nameFilter = NULL) {
      query <- NULL
      if (!is.null(nameFilter)) {
        query <- sprintf("Name = '%s'", id)
      }
      return(super$read(queryFilter = query, tablename =
                          "Participants"))
    },
    getParticipantById = function(id) {
      query <- sprintf("Id = '%s'", id)
      return(super$read(queryFilter = query,
                        tablename = "Participants"))
    },
    deleteParticipants = function(nameFilter = NULL) {
      query <- nameFilter
      if (!is.null(nameFilter)) {
        query <- sprintf("Name = '%s'", nameFilter)
      }
      super$delete(deleteFilter = query, tablename = "Participants")
    }
  )
)


#' Class that manages data catalog or entities
#' in the MRSDistComp application.
#'
#' @docType class
#' @importFrom R6 R6Class
#' @importFrom lubridate now
#' @importFrom uuid UUIDgenerate
#' @importFrom RODBC sqlQuery
#' @export
#' @return Object of \code{\link{R6Class}} with methods for communication with backend MRSDistComp database.
#' @format \code{\link{R6Class}} object.
#' @examples
#' DataCatalog$new()
#' @field Id Unique identifier for the DataCatalog
#' @field Name Unique name for a schema that will be used in a computation
#' @field Description Description for the schema
#' @field Version Version of the Schema. Name is currently the only primary key. Version can be set to any value.
#' @field Schema Actual schema content. This is currently a serialized 'exemplar' data frame (i.e., an empty data frame).
#' @section Methods:
#'
#' \describe{
#'   \item{\code{new()}}{This method is used to create object of this class.}
#'   \item{\code{registerSchema(name,description,version,schema=NULL)}}{This method creates a new DataCatalog or entity schema. Pass in a empty data frame for schema column.}
#'   \item{\code{getSchemaByName(nameFilter=NULL,versionFilter=NULL)}}{This method gets the list of all schemas or datacatalog items by name.}}
#'   \item{\code{getSchemaById(id)}}{This method gets a DataCatalog item by Id.}}
DataCatalog <- R6Class(
  "DataCatalog",
  inherit = MRSDistCompBase,
  public = list(
    Id = NULL,
    Name = NULL,
    Description = NULL,
    Version = NULL,
    Schema = NULL,
    registerSchema = function(name,
                              description,
                              schema,
                              version = "1.0.0.0") {

      # Check if schema is of type data.frame
      #stopifnot(is.data.frame(schema))

      # Serialize empty data frame as the schema. Note that
      # raw data cannot be saved so convert it to 'character' str.
      # to unserialize do:
      #  - rawSerializedSchemaStr <- as.raw(as.hexmode(serializedSchemaStr))
      #  - doublySerializedSchema <- unserialize(rawSerializedSchemaStr)
      #  - all.equal(doublySerializedSchema, serializedSchema)
      #serializedSchemaStr = (serialize(schemadfempty, NULL))

      ## NOTE: The toJSON / fromJSON loses coltype precision
      ## so the - sapply(exemplarSchema, class) == sapply(dfdeser, class)
      ## fails.
      schemadf <- as.data.frame(schema)
      schemadfempty <- schemadf[1,]
      serializedSchemaStr = toJSON(schemadfempty)

      self$Id <- uuid::UUIDgenerate()
      self$Name <- name
      self$Description <- description
      self$Version <- version
      self$Schema <- serializedSchemaStr

      # Super call to create the Schema entry in the database
      super$create(
        Id = self$Id,
        Name = self$Name,
        Description = self$Description,
        Version = self$Version,
        SchemaJSON = self$Schema,
        tablename = 'DataCatalog'
      )
      return(self$Id)
    },
    broadcastSchemaInfo = function(schemaname,
                                   schemadesc,
                                   schema,
                                   workerendpoint) {
      participantsObj <- Participant$new()
      participantsDataFrame <- participantsObj$getParticipants()
      participantsDataFrame$URL <- gsub("*$",paste0("/", workerendpoint), participantsDataFrame$URL)

      broadcastStatus = TRUE
      for(i in 1:nrow(participantsDataFrame)) {

        participant <- participantsDataFrame[i,]

        print(sprintf("Fetching AAD token from cache for participant '%s'", as.character(participant$Name)))
        authorizationHeader = super$getAADTokenFromCache(as.character(participant$Name))

        print(sprintf("Sending schema to '%s'", as.character(participant$Name)))
        requestBody = list(sitename = as.character(participant$Name),
                           schemaname = schemaname,
                           schemadesc = schemadesc,
                           schema = schema)
        response = NULL
        tryCatch({
          response <- POST(url = participant$URL,
                           add_headers("Authorization" = as.character(authorizationHeader), "Content-Type" = "application/json"),
                           body = requestBody,
                           encode = "json")
          print(sprintf("Schema broadcast status to site '%s' is '%s'", as.character(participant$Name), response))
        }, error = function(e) {
          print(paste('Error broadcasting schema:', e))
        })
        broadcastStatus <- all(broadcastStatus, response$status == 200)
      }
      return(broadcastStatus)
    },
    getSchemaByName = function(nameFilter = NULL) {
      query <- NULL
      if (!is.null(nameFilter)) {
        query <- sprintf("Name like '%s'", nameFilter)
      }
      return(super$read(queryFilter = query,
                        tablename = "DataCatalog"))
    },
    getSchemaById = function(id) {

      query <- sprintf("Id = '%s'", id)
      return(super$read(queryFilter = query,
                        tablename = "DataCatalog"))
    }
  )
)

#' Class that manages Computation in the MRSDistComp application.
#' It registers all existing computations in the distcomp package
#' available on a specific site for use in model definitions
#'
#' @docType class
#' @importFrom R6 R6Class
#' @importFrom lubridate now
#' @importFrom uuid UUIDgenerate
#' @importFrom RODBC sqlQuery
#' @importFrom distcomp availableComputations
#' @export
#' @return Object of \code{\link{R6Class}} with methods for communication with backend MRSDistComp database.
#' @format \code{\link{R6Class}} object.
#' @examples
#' Computation$new()
#' @field Id Unique identifier for the Computation
#' @section Methods:
#'
#' \describe{
#'   \item{\code{new()}}{This method is used to create object of this class.}
#'   \item{\code{registerAllComputations()}}{This method parses the distcomp::availableComputations() list and registers all available computations.}
#'   \item{\code{getComputations()}}{This method gets a list of all computations from the database.}
Computation <- R6Class(
  "Computation",
  inherit = MRSDistCompBase,
  public = list(
    Id = NULL,
    Name = NULL,
    Description = NULL,
    registerAllComputations = function() {
      i = 0
      computationList <- list()
      for (i in 1:length(distcomp::availableComputations())){

        Id <- uuid::UUIDgenerate()
        obj <- distcomp::availableComputations()[[i]]
        computationName = str_replace_all(obj$desc, " ","")
        computationDesc = obj$desc

        computations = self$getComputations(computationName)
        if(is.null(computations) || nrow(computations) == 0){

          # Super call
          super$create(
            Id = Id,
            Name = computationName,
            Description = computationDesc,
            tablename = "Computation"
          )
          computationList[[length(computationList)+1]] <- computationName
        }

      }
      return(computationList)
    },
    getComputations = function(nameFilter = NULL) {
      query <- NULL
      if (!is.null(nameFilter)) {
        query <- sprintf("Name like '%s'", nameFilter)
      }
      return(super$read(queryFilter = query,
                        tablename = "Computation"))
    }
  )
)

#' Class that defines a formula for a distributed computation "project".
#' This enforces two demands - that the formula fields are bound by a schema (DataCatalog) and
#' that the actual "model fitting" be performed using a specific type of learner
#' that is included in the "distcomp" package such as - Stratified Cox or RankKSVD.
#'
#' @docType class
#' @importFrom R6 R6Class
#' @importFrom lubridate now
#' @importFrom uuid UUIDgenerate
#' @importFrom RODBC sqlQuery
#' @export
#' @return Object of \code{\link{R6Class}} with methods for communication with backend MRSDistComp database.
#' @format \code{\link{R6Class}} object.
#' @examples
#' ComputationInfo$new()
#' @field Id Unique identifier for a ComputationInfo object.
#' @field Name Name of the ComputationInfo object.
#' @field Formula Formula of the ComputationInfo. Expected to be R code.
#' @field DataCatalog Schema for the ComputationInfo. The DataCatalog is an empty column based on a sample data frame provided by the customer.
#' @field ComputationType Type of computation this ComputationInfo uses Must be one of the supported computations in the "distcomp" package.
#' @field IsEnabled Specify whether the ComputationInfo is enabled or disabled. Temporarily disable to control access and execution.
#' @section Methods:
#'
#' \describe{
#'   \item{\code{new()}}{This method is used to create object of the ComputationInfo class.}
#'   \item{\code{createComputationInfo(name,formula,datacatalog,computationtype,isenabled=1,validfrom=NULL,validto=NULL)}}{This method creates a new ComputationInfo in the database. Returns Id of the newly created ComputationInfo.}
#'   \item{\code{getAllComputationInfo()}}{This method gets the list of all models.}
#'   \item{\code{getComputationInfoByName(nameFilter=NULL)}}{This method gets the list of all models by name.Empty nameFilter returns all computationinfo objects.}}
ComputationInfo <- R6Class(
  "ComputationInfo",
  inherit = MRSDistCompBase,
  public = list(
    Id = NULL,
    ProjectName = NULL,
    ProjectDescription = NULL,
    Formula = NULL,
    DataCatalog = NULL,
    ComputationType = NULL,
    IsEnabled = 1,
    ValidFrom = (lubridate::now(tzone = "GMT")),
    ValidTo = (lubridate::now(tzone = "GMT") + dyears(1)),
    createComputationInfo = function(projectname,
                                     projectdesc,
                                     formula,
                                     datacatalogname,
                                     computationname,
                                     isenabled = 1,
                                     validfrom = NULL,
                                     validto = NULL) {
      self$Id <- uuid::UUIDgenerate()
      self$ProjectName <- projectname
      self$ProjectDescription <- projectdesc
      self$Formula <- formula
      self$DataCatalog <- datacatalogname
      self$ComputationType <- computationname
      self$IsEnabled <- isenabled
      if (!is.null(validfrom)) {
        self$ValidFrom <- validfrom
      }
      if (!is.null(validto)) {
        self$ValidTo <- validto
      }

      # Super call
      super$create(
        Id = self$Id,
        ProjectName = self$ProjectName,
        ProjectDescription = self$ProjectDescription,
        Formula = self$Formula,
        DataCatalog = self$DataCatalog,
        ComputationType = self$ComputationType,
        IsEnabled = self$IsEnabled,
        ValidFrom = as.character(self$ValidFrom),
        ValidTo = as.character(self$ValidTo),
        tablename = "ComputationInfo"
      )

      return(self$Id)
    },
    broadcastComputationInfo = function(projectname,
                                        projectdesc,
                                        formula,
                                        datacatalogname,
                                        computationtype,
                                        workerendpoint) {
      participantsObj <- Participant$new()
      participantsDataFrame <- participantsObj$getParticipants()
      participantsDataFrame$URL <- gsub("*$",paste0("/", workerendpoint), participantsDataFrame$URL)

      broadcastStatus = TRUE
      for(i in 1:nrow(participantsDataFrame)) {

        participant <- participantsDataFrame[i,]

        print(sprintf("Fetching AAD token from cache for participant '%s'", as.character(participant$Name)))
        authorizationHeader = super$getAADTokenFromCache(as.character(participant$Name))

        print(sprintf("Sending computation proposal to '%s'", as.character(participant$Name)))
        requestBody = list(sitename = as.character(participant$Name),
                           projectname = projectname,
                           projectdesc = projectdesc,
                           formula = formula,
                           schemaname = datacatalogname,
                           computationtype = computationtype)
        response = NULL
        tryCatch({
          response <- POST(url = participant$URL,
                           add_headers("Authorization" = as.character(authorizationHeader), "Content-Type" = "application/json"),
                           body = requestBody,
                           encode = "json")
          print(sprintf("Proposal acknowledgement status at site '%s' is '%s'", as.character(participant$Name), response))
        }, error = function(e) {
          print(paste('Error broadcasting computation project to site:', e))
        })
        broadcastStatus <- all(broadcastStatus, response$status == 200)
      }
      return(broadcastStatus)
    },
    getAllComputationInfo = function() {
      query <- NULL
      return(super$read(queryFilter = query, tablename = "ComputationInfo"))
    },
    getComputationInfoByName = function(nameFilter) {
      query <- NULL

      if (!is.null(nameFilter)) {
        query <- sprintf("ProjectName like '%s'", nameFilter)
      }
      return(super$read(queryFilter = query, tablename = "ComputationInfo"))
    }
  )
)


#' Relationship class that manages the participants in computation projects.
#' A participant can be in one or more computation projects and there can be
#' any number of computation projects defined in the system.
#'
#' @docType class
#' @importFrom R6 R6Class
#' @importFrom lubridate now
#' @importFrom uuid UUIDgenerate
#' @importFrom RODBC sqlQuery
#' @export
#' @return Object of \code{\link{R6Class}} with methods for communication with backend MRSDistComp database.
#' @format \code{\link{R6Class}} object.
#' @examples
#' ComputationInfoParticipants$new()
#' @field Id Unique identifier for a ComputationInfoParticipant object
#' @field ComputationInfoName Name of the Computation project
#' @field ParticipantName Name of the participant or site.
#' @field IsEnabled Specify whether the ComputationInfoParticipant is enabled or disabled. Use this flag to control who participates in a specific Computation project.
#' @section Methods:
#'
#' \describe{
#'   \item{\code{new()}}{This method is used to create object of the Model class.}
#'   \item{\code{create(id,computationinfoname,participantname,isenabled=1)}}{This method creates a new ModelParticipant that links a participant or Site with a Model.}
#'   \item{\code{getAllComputationInfoParticipants()}}{This method gets the list of all ComputationInfoParticipants records.}
#'   \item{\code{getParticipantsOfAProject(computationInfoNameFilter)}}{This method returns a data.frame that contains all participants for a specific computation project}}
#'   \item{\code{getProjectsOfAParticipant(participantNameFilter)}}{This method returns a data.frame that contains all computation projects a specific participant is registered for.}
ComputationInfoParticipants <- R6Class(
  "ComputationInfoParticipants",
  inherit = MRSDistCompBase,
  public = list(
    Id = NULL,
    ComputationInfoName = NULL,
    ParticipantName = NULL,
    IsEnabled = 1,
    create = function(computationinfoname,
                      participantname,
                      isenabled = 1) {

      self$Id <- uuid::UUIDgenerate()
      self$ComputationInfoName <- computationinfoname
      self$ParticipantName <- participantname
      self$IsEnabled <- isenabled

      # Super call
      super$create(
        Id = self$Id,
        ComputationInfoName = self$ComputationInfoName,
        ParticipantName = self$ParticipantName,
        IsEnabled = self$IsEnabled,
        tablename = "ComputationInfoParticipants"
      )
      return(self$Id)
    },
    getAllComputationInfoParticipants = function() {
      query <- NULL
      return(super$read(queryFilter = query, tablename = "ComputationInfoParticipants"))
    },
    getParticipantsOfAProject = function(projectNameFilter) {
      query <- NULL
      if (!is.null(projectNameFilter)) {
        query <- sprintf("ComputationInfoName like '%s'", projectNameFilter)
      }
      return(super$read(queryFilter = query, tablename = "ComputationInfoParticipants"))
    },
    getProjectsOfAParticipant = function(participantNameFilter) {
      query <- NULL
      if (!is.null(participantNameFilter)) {
        query <- sprintf("ParticipantName like '%s'", participantNameFilter)
      }
      return(super$read(queryFilter = query, tablename = "ComputationInfoParticipants"))
    },
    deleteProjectParticipant = function(computationInfoNameFilter, participantNameFilter=NULL) {
      query <- NULL
      if (!is.null(participantNameFilter)) {
        query <- sprintf("ComputationInfoName = '%s' AND ParticipantName = '%s'",
                         computationInfoNameFilter,
                         participantNameFilter)
      }else{
        query <- sprintf("ComputationInfoName = '%s'", computationInfoNameFilter)
      }
      super$delete(deleteFilter = query, tablename = "ComputationInfoParticipants")
    }
  )
)




#' Class that manages data sources for data to be used in the DistComp application.
#'
#' @docType class
#' @importFrom R6 R6Class
#' @importFrom uuid UUIDgenerate
#' @importFrom RODBC sqlQuery
#' @export
#' @return Object of \code{\link{R6Class}} with methods for communication with backend MRSDistComp database.
#' @format \code{\link{R6Class}} object.
#' @examples
#' DataInfo$new()
#' @field Id Unique identifier for a ComputationInfoParticipant object
#' @field Name Name of a Data Source
#' @field Description Description for the Data Source
#' @field Type Type of Data Source. Any meaningful identifier such as "CSV", "SQLAzure", "AzureBlob", "GoogleBlob" etc.,
#' @field DataCatalog Name of the DataCatalog (Schema) that this data source conforms to. Both to keep track of from the end-user as well as for the distcomp application.
#' @field AccessInfo Content that contains access related information for the data source. For e.g., a connection string to a database
#' @section Methods:
#'
#' \describe{
#'   \item{\code{new()}}{This method is used to create a new DataSources class object.}
#'   \item{\code{createDataSource(name,description,datasourcetype,datacatalogname,accessinfo)}}{This method creates a new DataSource for use with DistComp application.No restrictions are enforced as to what the source is expected to be.}
#'   \item{\code{getDataSourcesForSchema(schemaNameFilter)}}{This method gets all data sources defined for a specific schema.}
#'   \item{\code{getDataSourcesByName(nameFilter)}}{This method returns a data.frame for a data sources with the given name. Specifying NULL value for the nameFilter returns all datasource records defined.}}
DataSources <- R6Class(
  "DataSources",
  inherit = MRSDistCompBase,
  public = list(
    Id = NULL,
    Name = NULL,
    Description = NULL,
    Type = NULL,
    DataCatalog = NULL,
    AccessInfo = NULL,
    IsEnabled = 0,
    createDataSource = function(name,
                                description=NULL,
                                datasourcetype,
                                datacatalogname,
                                accessinfo,
                                isenabled=1) {

      self$Id <- uuid::UUIDgenerate()
      self$Name <- name
      self$Description <- description
      self$Type <- datasourcetype
      self$DataCatalog <- datacatalogname
      self$AccessInfo <-  accessinfo
      self$IsEnabled <-  isenabled

      # Super call
      super$create(
        Id = self$Id,
        Name = self$Name,
        Description = self$Description,
        Type = self$Type,
        DataCatalog = self$DataCatalog,
        AccessInfo = self$AccessInfo,
        IsEnabled = self$IsEnabled,
        tablename = "DataSources"
      )
      return(self$Id)
    },
    createCSVDataSource = function(name,
                                   description=NULL,
                                   datacatalogname,
                                   csvfilepath,
                                   csvfileseparator,
                                   isenabled=1) {
      accessInfoListJSON = toJSON(list(FilePath=csvfilepath, Separator=csvfileseparator))
      return(self$createDataSource(name, description, 'CSV', datacatalogname, accessInfoListJSON, isenabled))
    },
    createSQLDataSource = function(name,
                                   description=NULL,
                                   datacatalogname,
                                   sqlConnectionString,
                                   sqlQuery,
                                   isenabled=1) {
      accessInfoListJSON = toJSON(list(SqlConnectionString=csvfilepath, SqlQuery=csvfileseparator))
      return(self$createDataSource(name, description, 'SQLAzure', datacatalogname, accessInfoListJSON, isenabled))
    },
    getDataSourcesForSchema = function(schemaNameFilter) {
      query <- NULL
      if (!is.null(schemaNameFilter)) {
        query <- sprintf("DataCatalog like '%s'", schemaNameFilter)
      }
      return(super$read(queryFilter = query, tablename = "DataSources"))
    },
    getDataSourcesByName = function(nameFilter=NULL) {
      query <- NULL
      if (!is.null(nameFilter)) {
        query <- sprintf("Name like '%s'", nameFilter)
      }
      return(super$read(queryFilter = query, tablename = "DataSources"))
    },
    getDataFrameFromCSV = function(filePath, separator=", "){
      stopifnot(file.exists(filePath))
      dataframe <- read.csv(file=filePath, header=TRUE, sep=separator)
      return(dataframe)
    },
    getDataFrameFromSQL = function(sqlConnectionString, sqlQuery){
      dataframe = tryCatch({
        connection <- odbcDriverConnect(sqlConnectionString)
        dataframe <- sqlQuery(connection, sqlQuery)
      }, warning = function(w) {
        print("warning!")
      }, error = function(e) {
        print("error encountered!")
        print(e)
      }, finally = {
        close(connection)
        print("goodbye")
      })
      return(dataframe)
    }
  )
)

#' Class that manages ComputationInfoJob in MRSDistComp application.
#'
#' @docType class
#' @importFrom R6 R6Class
#' @importFrom lubridate now
#' @importFrom uuid UUIDgenerate
#' @importFrom RODBC sqlQuery
#' @export
#' @return Object of \code{\link{R6Class}} with methods for communication with backend MRSDistComp database.
#' @format \code{\link{R6Class}} object.
#' @examples
#' ComputationInfoJob$new()
#' @field Id Unique identifier for the Computation job
#' @field ComputationInfo Project Name this Computation job is for.
#' @field Result Result object of a computation job.
#' @field Summary Summary of the computation job.
#' @field LogTxt Log output of the computation job.
#' @field Status Status of the ComputationInfoJob.Expected values are - 'NotStarted','Running','Completed','CompletedWithErrors'
#' @field StartDateTime Start datetime of this ComputationInfoJob.
#' @field EndDateTime Datetime when this ComputationInfoJob ended.
#' @section Methods:
#'
#' \describe{
#'   \item{\code{new()}}{This method is used to create object of this class.}
#'   \item{\code{triggerJob(projectname,status='Created',startdatetime=NULL,enddatetime=NULL)}}{This method creates a new computation job for a ComputationInfo i.e., "project".
#'   This method checks the list of participants for a project and if any found, sends them a new "synchronous" computation request. It is expected that
#'   the "sites" or "workers" already have the ComputationInfo definition (with the same name) and its dependencies - i.e., data catalog (schema)
#'   data sources for the schema defined. This method will also be exposed as a webservice, ONLY on the "master".}
#'   \item{\code{processJob(projectname,status='Created',startdatetime=NULL,enddatetime=NULL)}}{This method creates a new computation job for a ComputationInfo i.e., "project". This is exposed as a webservice only on the "master".}
#'   \item{\code{getJobsByStatus(statusFilter)}}{This method gets a list of all jobs based on a status. Possible status values are: 'Created', 'InProgress', 'Completed', 'Failed'}
#'   \item{\code{getJobsForProject(projectName)}}{This method gets a list of all computation jobs for a project.}}
ComputationInfoJob <- R6Class(
  "ComputationInfoJob",
  inherit = MRSDistCompBase,
  private = list(

    initializeDataContext = function(computationInfoDataFrame){
      # 1. Get DataCatalog object

      print("Get DataCatalog..")
      dataCatalogObj <- DataCatalog$new()
      dataCatalogDataFrame <- dataCatalogObj$getSchemaByName(computationInfoDataFrame$DataCatalog)
      if(is.null(nrow(dataCatalogDataFrame))){
        stop(sprintf("No schema with name '%s' found in the site.", computationInfoDataFrame$DataCatalog))
      }

      # 1. Check if a DataSource is defined at the site for the DataCatalog (Schema) referenced
      # by the ComputationInfo.
      # NOTE: TBD..TBD.. MRSDistComp allows for multiple data sources to be defined
      # for a DataCatalog. The sites must only enable one of them to be active.

      print("Get DataSources...")
      dataSourcesObj <- DataSources$new()
      dataSourcesDataFrame <- dataSourcesObj$getDataSourcesForSchema(computationInfoDataFrame$DataCatalog)
      if(is.null(nrow(dataSourcesDataFrame))){
        stop(sprintf("No DataSource found for schema '%s' in the site.", computationInfoDataFrame$DataCatalog))
      }

      # 4. Fetch data from datasource
      print("Fetching data from datasource...")
      data = NULL
      dataSourcesDataFrame = subset(dataSourcesDataFrame, dataSourcesDataFrame$IsEnabled == 1)
      accessInfo = as.list(fromJSON(as.character(dataSourcesDataFrame$AccessInfo)))
      if(dataSourcesDataFrame$Type == "CSV"){

        # Get CSV access params from db deserialized str
        filePath = accessInfo$FilePath
        separator = accessInfo$Separator

        sprintf("Fetching CSV data from '%s'", filePath)

        if(!is.null(separator)){
          data <- dataSourcesObj$getDataFrameFromCSV(filePath, separator)
        }
        else{
          data <- dataSourcesObj$getDataFrameFromCSV(filePath)
        }
      }
      else if(dataSourcesDataFrame$Type == "SQL" || dataSourcesDataFrame$Type == "SQLAzure"){

        sqlConnectionString = accessInfo$SQLConnectionString
        sqlQuery = accessInfo$SqlQuery

        sprintf("Fetching SQL data from '%s' with query '%s'", sqlConnectionString, sqlQuery)

        data <- dataSourcesObj$getDataFrameFromSQL(sqlConnectionString, sqlQuery)
      }
      else {
        stop(sprintf("Unknown DataSource type '%s' found. Configure a valid data source to proceed.", dataSourcesDataFrame$Type))
      }

      # 5. Check if we have a valid data frame and if the schema match is found
      sprintf("Validating if dataframe matches expected schema")

      schemaData = as.data.frame(fromJSON(as.character(dataCatalogDataFrame$SchemaJSON)))
      if(all(!is.null(data),
             is.data.frame(data),
             colnames(schemaData) %in% colnames(data))){
        print("Schema validation passed")
      }
      else {

        print("Schema validation FAILED!..")

        sprintf("Expected schema: '%s'", as.character(schema$SchemaJSON))
        sprintf("Actual schema: '%s'", as.character(toJSON(data[1,])))
      }

      return(list(data=data))
    }
  ),
  public = list(
    Id = NULL,
    ComputationInfo = NULL,
    Result = NULL,
    Summary = NULL,
    LogTxt = NULL,
    Status = NULL,
    StartDateTime = (lubridate::now(tzone = "GMT")),
    EndDateTime = (lubridate::now(tzone = "GMT")),
    triggerJob = function(projectname,
                          jobId=NULL,
                          workerendpoint='ProcessJob',
                          status = 'Created',
                          startdatetime = NULL,
                          enddatetime = NULL) {

      ## This function is used only by the master and no
      ## corresponding services are registered on the workers/sites.
      if(is.null(jobId)) {
        jobId <- uuid::UUIDgenerate()
      }
      self$Id <- jobId
      self$ComputationInfo <- projectname
      self$Status <- status
      if (!is.null(startdatetime)) {
        self$StartDateTime <- startdatetime
      }
      if (!is.null(enddatetime)) {
        self$EndDateTime <- enddatetime
      }

      # 1. Create a computation job in the backend with a 'Created' status
      print(sprintf("Creating computation job with id '%s' in the MASTER.", jobId))
      super$create(
        Id = self$Id,
        Operation = "triggerJob",
        ComputationInfo = self$ComputationInfo,
        Status = self$Status,
        StartDateTime = as.character(self$StartDateTime),
        EndDateTime = as.character(self$EndDateTime),
        tablename = "ComputationInfoJob"
      )

      # 2. Get the associated computation project
      print("Fetching associated computation project info (ComputationInfo)...")
      computationInfoObj <- ComputationInfo$new()
      computationInfoDataFrame <- computationInfoObj$getComputationInfoByName(projectname)
      if(nrow(computationInfoDataFrame) != 1){
        stop(sprintf("Project with name '%s' not found.", projectname))
      }

      # 3. Get the participants (sites/workers) for the project.
      # The ComputationInfo-Sites relationship controls which
      # Participants (sites) participate in which projects. Note that there is
      # a 'IsEnabled' flag on the participants table.
      # The participation registration is not imposed and could either be
      # sites own volition or controllable by master.
      print("Fetching project participants (ComputationInfoParticipants)...")
      compInfoParticipantsObj <- ComputationInfoParticipants$new()
      compInfoParticipantsDataFrame <- compInfoParticipantsObj$getParticipantsOfAProject(projectname)
      if(nrow(compInfoParticipantsDataFrame) < 1){
        stop(sprintf("No Participants were found for Project with name '%s'. Add one or more Participants to proceed.", projectname))
      }

      # 4. Update Participants dataframe for the following:
      # a. Include only participant records found in the ComputationInfo-Participants dataframe
      # b. Add a new vector that includes the authorization token that needs to be part of http-header.
      # c. Fix the URL column to include the full url path for the target API (processJob)
      print("Fetching participants..")
      participantObj <- Participant$new()
      participantsDataFrame <- participantObj$getParticipants(NULL)

      print("Filter participants dataframe to include only project participants ..")
      participantsDataFrame = participantsDataFrame[participantsDataFrame$Name %in% unique(compInfoParticipantsDataFrame$ParticipantName), ]
      if(nrow(participantsDataFrame) == 0){
        stop(sprintf("Participants not found for triggering computations."))
      }

      print("Fetch AAD token for all project participants ..")
      participantsDataFrame$Token <- mapply(participantObj$getAADToken,
                                            participantsDataFrame$Name,
                                            participantsDataFrame$TenantId,
                                            participantsDataFrame$ClientId,
                                            participantsDataFrame$ClientSecret)

      print("Update participants URL with the workerendpoint ..")
      participantsDataFrame$URL <- gsub("*$",paste0("/", workerendpoint), participantsDataFrame$URL)

      # 5. Create an appropriate computation "master" object and add the list of sites for processing
      print("Creating computation endpoint object ..")
      if(computationInfoDataFrame$ComputationType == "StratifiedCoxModel"){

        print("ComputationType is StratifiedCoxModel. Creating CoxMaster object ..")

        masterObj = CoxMaster$new(defnId = as.character(computationInfoDataFrame$ProjectName),
                                  formula = as.character(computationInfoDataFrame$Formula))
      }
      else if(computationInfoObj$ComputationType == "RankKSVD"){
        #### TBD..TBD..TBD ###
        # masterObj = SVDMaster$new(defnId = computationInfoObj$name, formula = computationInfoObj$formula)
        warning(sprintf("The specified computation type '%s' is currently not supported by mrsdistcomp.",
                        as.character(computationInfoDataFrame$ProjectName)))
      }
      else{
        stop(sprintf("The specified computation type '%s' is not found in the distcomp package or not supported.",
                     as.character(computationInfoDataFrame$ProjectName)))
      }

      # 6. Add the sites list to the computation project
      print("Adding sites to the CoxMaster object ..")
      print(sprintf("Total participants '%s'", nrow(participantsDataFrame)))

      for(i in 1:nrow(participantsDataFrame)) {
        participant <- participantsDataFrame[i,]
        print(sprintf("Adding site '%s' with URL '%s'and token '%s'",
                      participant$Name,
                      participant$URL,
                      participant$Token))
        masterObj$addSite(participant$Name, participant$URL, participant$Token)
      }


      # 7. Run the computation
      print("Running the computation ..")
      result <- masterObj$runMRS(as.character(jobId))

      if(!is.null(result)){
        resultJSON <- toJSON(result)
        print(sprintf("Computation result obtained. '%s'", resultJSON))
      }
      else {
        print("Computation result is NULL.")
        resultJSON <- '{"Error": "Result could not be gathered"}'
      }

      # 8. Gather summary
      print("Gathering run summary..")
      summary <- masterObj$summary()
      if(!is.null(summary)){

        summaryJSON = toJSON(summary)
        print(sprintf("Run summary is '%s'", summaryJSON))

      }
      else {

        print("Computation summary is NULL.")
        summaryJSON <- '{"Error": "Summary could not be gathered"}'
      }


      # 9. Update ComputationInfoJob table with the results and status
      print("Updating ComputationInfoJob table with results..")
      setStmt = sprintf("Summary = '%s', Result = '%s', EndDateTime = '%s',Status = 'Completed'",
                        summaryJSON,
                        resultJSON,
                        as.character((lubridate::now(tzone = "GMT"))))
      filterStmt = sprintf("Id = '%s'", jobId)
      super$update(
        setStmt = setStmt,
        filterStmt = filterStmt,
        tablename = "ComputationInfoJob"
      )

      return(sprintf("Job '%s' completed.", jobId))
    },
    processJob = function(jobId,
                          defnId,
                          method,
                          methodparams,
                          status='Created') {

      # DefinitionId in DistComp APIs is the "ProjectName" PKey in
      # the ComputationInfo table in MRSDistComp
      projectname = defnId
      startDateTime = (lubridate::now(tzone = "GMT"))
      initializeDataCtxt = FALSE
      workerObj = NULL
      filePath = paste0(self$computeContext$datafolder, "/", jobId, ".rds")

      # 1. Check if a Computation with the same name is defined on the site
      print("Checking computation project is defined on the site...")
      computationInfoObj <- ComputationInfo$new()
      computationInfoDataFrame <- computationInfoObj$getComputationInfoByName(projectname)
      if(nrow(computationInfoDataFrame) != 1){
        stop(sprintf("Project '%s' not found in the site.", projectname))
      }

      # 2. Check if a computation job exists on the site.
      # We envision computation proceeding in stages on the client. Each "call"
      # from master creates a new record in the ComputationInfoJob table stratified by the same jobId
      # but with a distinct "operation" and its "state". We first check to see if a record with a
      # jobId exists and if so unserialize the "latest" worker object.
      print("Checking if computation job with the same id exists on the site...")
      computationInfoJobObj <- ComputationInfoJob$new()
      computationInfoJobDataFrame <- computationInfoJobObj$getJobById(jobId)
      if(!is.null(nrow(computationInfoJobDataFrame)) && nrow(computationInfoJobDataFrame) > 0){

        if(file.exists(filePath)) {
          workerObj <- readRDS(file = filePath)
        }
        else {
          stop(sprintf("Data file '%s' was not found. Cannot proceed", filePath))
        }
      }
      else {

        print(sprintf("Job with id '%s' does not exist on the site...", jobId))
        super$create(
          Id = jobId,
          ComputationInfo = projectname,
          Operation = method,
          Status = status,
          StartDateTime = as.character(startDateTime),
          EndDateTime = as.character(startDateTime),
          tablename = "ComputationInfoJob"
        )

        # Initializing data context on the client
        print("Initializing data context on the client...")
        result = private$initializeDataContext(computationInfoDataFrame)

        # Run the requested method on the Worker class and return result
        if(computationInfoDataFrame$ComputationType == "StratifiedCoxModel"){

          print("Creating CoxWorker object...")
          workerObj = CoxWorker$new(formula = as.character(computationInfoDataFrame$Formula),
                                    data = result$data)
        }
        else if(computationInfoObj$ComputationType == "RankKSVD"){

          warning(sprintf("The specified computation type '%s' is currently not supported by mrsdistcomp.",
                          computationInfoObj$name))
        }
        else{

          stop(sprintf("The specified computation type '%s' is not found in the distcomp package or not supported.",
                       computationInfoObj$name))
        }

        filePath = paste0(self$computeContext$datafolder, "/", jobId, ".rds")
        print(sprintf("Creating file '%s' to save worker object for job '%s'", filePath, jobId))
        saveRDS(workerObj, filePath)
      }


      # 3. Execute the requested method on this site. The methodparams is a vector of parameters to
      # be passed to the method. We just convert it to a list and send it across to the object
      print(sprintf("Executing method '%s' on workerobject", method))
      emptyparams = TRUE

      if(!is.null(methodparams) && is.character(methodparams)){
        print(sprintf("Arguments passed in... '%s'", methodparams))
        methodparamslist = as.list(fromJSON(methodparams))
        if(length(methodparamslist) > 0) {
          emptyparams = FALSE
        }
      }

      if(method == "getP"){
        result = workerObj$getP()
        print("Result obtained from getP...")
        print(sprintf("'%f'", result))
      }
      else if (method == "logLik"){
        result = workerObj$logLik(methodparamslist)
        print("Result obtained from logLik...")
        print(sprintf("'%s'", result))
      }
      else {
        stop(sprintf("Method '%s' is not supported by ProcessJob API", method))
      }

      # TBD..TBD..implement distcomp::executeMethod
      #if(!emptyparams) {
      #  call <- substitute(workerObj$METHOD(methodparamslist), list(METHOD = as.name(method)))
      #}
      #else {
      #  call <- substitute(workerObj$METHOD(...), list(METHOD = as.name(method)))
      #}
      #print("Invoking eval on the method...")
      #result <- eval(call)
      #resultJSON <- toJSON(result)

      # 4. Update or insert to ComputationInfoJob table with the results and status
      # We need this variant to tell us if a record for this operation exists. If it exists, update, else insert.
      computationInfoJobDataFrame <- computationInfoJobObj$getJobByIdAndOperation(jobId, method)
      if(!is.null(nrow(computationInfoJobDataFrame)) && nrow(computationInfoJobDataFrame) > 0){

        print("Update ComputationInfoJob table with the results and status...")
        setStmt = sprintf("Result = '%s', EndDateTime = '%s', Status = 'Completed'",
                          as.character(result),
                          as.character((lubridate::now(tzone = "GMT"))))
        filterStmt = sprintf("Id = '%s' AND Operation = '%s'", jobId, method)
        super$update(
          setStmt = setStmt,
          filterStmt = filterStmt,
          tablename = "ComputationInfoJob"
        )

      }
      else {

        print(sprintf("Insert new ComputationInfoJob table with results and status for job id '%s' and operation '%s'...",
                      jobId,
                      method))
        super$create(
          Id = jobId,
          ComputationInfo = projectname,
          Operation = method,
          Result = toJSON(result),
          Status = 'Completed',
          StartDateTime = as.character(startDateTime),
          EndDateTime = as.character(lubridate::now(tzone = "GMT")),
          tablename = "ComputationInfoJob"
        )
      }

      print("ProcessJob completed...")
      return(as.data.frame(result))
    },
    getJobsByStatus = function(statusFilter) {
      query <- NULL
      if (!is.null(statusFilter)) {
        query <- sprintf("Status like '%s'", statusFilter)
      }
      return(super$read(queryFilter = query,
                        tablename = "ComputationInfoJob"))
    },
    getJobsForProject = function(projectName) {
      query <- NULL
      if (!is.null(projectName)) {
        query <- sprintf("ComputationInfo like '%s'", projectName)
      }
      return(super$read(queryFilter = query, tablename = "ComputationInfoJob"))
    },
    getJobById = function(Id) {
      query <- sprintf("Id = '%s'", Id)
      return(super$read(queryFilter = query,
                        tablename = "ComputationInfoJob"))
    },
    getJobByIdAndOperation = function(Id, Operation) {
      query <- sprintf("Id = '%s' AND Operation = '%s' ORDER BY StartDateTime DESC",
                       Id,
                       Operation)
      return(super$read(queryFilter = query, tablename =
                          "ComputationInfoJob"))
    }
  )
)

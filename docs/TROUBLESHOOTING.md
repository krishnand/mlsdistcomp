# Developer and troubleshooting guide for components

## Customizing and packaging web applications

1. The web apps for `Central Registry` and `Participants` is [ASP.NET Core MVC](https://docs.microsoft.com/en-us/aspnet/core/mvc/overview?view=aspnetcore-2.1) based and written in C#.
2. The src for the web applications is in this [directory](../src/webapp) and can be customized.
3. The Azure deployment requires the web applications to be packaged in a specific format. The sample command that will build the project in the required format is: 

```cmd

msbuild "<A_VALID_LOCAL_FOLDER>\CentralRegistry.csproj" /nologo /p:PublishProfile=Release /p:PackageLocation="<A_VALID_LOCAL_FOLDER>\centralwebapp.zip" /p:WebPublishMethod=Package /p:PackageAsSingleFile=true /p:platform="Any CPU" /p:configuration="Release" /p:DesktopBuildPackageLocation="<A_VALID_LOCAL_FOLDER>\centralwebapp.zip" /p:DeployOnBuild=true

```
4. The package zip file will be generated and can be found in the folder specified by the `PackageLocation` parameter in the cmd above. The zip file must be uploaded to any location of your choice from where they can be accessed by the ARM scripts - such your own fork of this github repo or Azure blob storage. 

5. Importantly, the ARM template that you will use must then point to the new package.This is accomplished by updating the `pkgMLSWebApp` property in the `variables` section of either the [Central Registry ARM template](../azuredeploycentral.json)  or the [Participant  ARM template](../azuredeployparticipant.json).


**NOTE**: 
a. The web application src must be downloaded locally for customization.
b. `msbuild` is in PATH and available when using the `MSBuild Command Prompt for VS2015` or  `Developer Command Prompt for VS2017` or other Visual Studio command shell on Windows machines.

### Customizing `mlsdistcomp` R package 

1. Fix and build the package locally [[devtools::build()]]
2. Push new package to mlsdistcomp repo

### Debugging web services

1. Enable localadmin on MLS
  a. Set env var
      ```bash
      MLS_WEBNODE_APPSETTINGS='/opt/microsoft/mlserver/9.2.1/o16n/Microsoft.MLServer.WebNode/appsettings.json'
      ```
  b. Edit app settings file
      ```bash 
      sudo vi $MLS_WEBNODE_APPSETTINGS 
      ```
  c. Update these properties in the JSON file.
     
     .Kestrel.Host="localhost"
     .Authentication.AdminAccount.Enabled=true
     .Authentication.AzureActiveDirectory.Enabled=false
     
2. Restart webnode and compute node services
   ```bash
   MLS_ADMINUTIL_PATH='/opt/microsoft/mlserver/9.2.1/o16n/Microsoft.MLServer.Utils.AdminUtil/Microsoft.MLServer.Utils.AdminUtil.dll'
   sudo dotnet $MLS_ADMINUTIL_PATH

   <<Run these options in the sequence: 3, A, B, C, D, E, 9>>
   ```
   

3. Unregister all MLS webservices
    ```bash
    sudo chmod 777 /tmp/mlsdistcomp_bootstrapper.R
    sudo vi /tmp/mlsdistcomp_bootstrapper.R
   	```

    Find and replace this:
    ```R
	  if (length(args)<5) {
    ```

   	with:     
    ```R
	   #stop("Expected at least 5 arguments.", call.=FALSE)
	   print('Assigning default args')
	   profile <- "Central"
	   url <- "http://localhost:12800"
	   user <- "admin"
	   pwd <- "Welcome1234!"
	   mlsdistcomppath <<- "/opt/microsoft/mlserver/9.2.1/libraries/RServer/mlsdistcomp/R/mlsdistcomp"
	   fn <- "unregister"
	   print('Assignment done')
    ```
   c. Save changes
   d. Execute this command:
      ```bash
      Rscript /tmp/mlsdistcomp_bootstrapper.R
      ```

4. Download and install new package. 
   ```bash
   sudo su - -c "Rscript -e \"remove.packages('mlsdistcomp')\""
   ```
   
   b. Create and save a shell script in the /tmp/ dir with following content
	
    ```bash
   MLSDISTCOMP_LOC="https://raw.githubusercontent.com/krishnand/mlsdistcomp/master/packages/mlsdistcomp_0.1.0.tar.gz"
   MLSDISTCOMP_PKG_PATH='/tmp/mlsdistcomp.tar.gz'
   sudo wget -q $MLSDISTCOMP_LOC -O $MLSDISTCOMP_PKG_PATH
   echo "Installing distcomp package..."
   sudo su - -c "Rscript -e \"install.packages('"$MLSDISTCOMP_PKG_PATH"', repos=NULL, type='source')\""
    ```
  c. Execute the newly created shell script.

5. Register all MLS webservices
    ```bash
   sudo chmod 777 /tmp/mlsdistcomp_bootstrapper.R
   sudo vi /tmp/mlsdistcomp_bootstrapper.R
   ```

    Replace this below with:
    ```R
    if (length(args)<5) {
    ```
    this:
    ```R
    fn <- "unregister"
        TO:
    fn <- "register"
    ```
   c. Save changes
   d. Execute from shell prompt 
      ```bash
      Rscript /tmp/mlsdistcomp_bootstrapper.R
      ```

6. Update APPSETTINGS to point to the Azure DNS and enable AAD auth.
    ```bash
   sudo vi $MLS_WEBNODE_APPSETTINGS
   ```

   Update these properties in the JSON file.
   ```
     .Kestrel.Host=<<ORIGINAL_NAME>>
     .Authentication.AdminAccount.Enabled=false
     .Authentication.AzureActiveDirectory.Enabled=true
    ```

7. Restart webnode and compute node services
  ```bash
   sudo dotnet $MLS_ADMINUTIL_PATH
   <<Run these options in the sequence: 3, A, B, C, D, E, 9>>
  ```
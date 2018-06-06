# Script to deploy web app.
# Requires parameters to update the appsettings.json

# Must point to the correct zip file based
# on the profile
webappzipsrc=$1

# Domain: microsoft.onmicrosoft.com
domain=$2

# Azure Tenant Id
tenantid=$3

# AAD Application ClientId for Web App 
webappaadclientid=$4

# Client Secret on the AAD Application for Web App 
webappaadsecret=$5

# AAD Application ClientId for MLS (that hosts Web API)
mlsappaadclientid=$6

# DNS name (including the port) where MLS Web APIs are exposed
mlsbaseaddress=$7

# appsettings.json template
appsettings_json = '{
  "AzureAd": {    
    "Instance": "https://login.microsoftonline.com/",
    "Domain": "",
    "TenantId": "",
    "ClientId": "",
    "CallbackPath": "/signin-oidc",
    "ClientSecret": "",
    "MRSDistCompResourceAppId": "",
    "MRSDistCompBaseAddress": ""
  },
  "Logging": {
    "IncludeScopes": false,
    "LogLevel": {
      "Default": "Warning"
    }
  }
}'

###############
# 
#### MAIN #####
#
###############

# Get and unzip web app
tmp_file = "webapp$$"
wget -q $webappzipsrc -O "/tmp/$tmp_file.zip"
unzip tmp_file
cd /tmp/tmp_file

# Update appsettings with jq
sudo apt-get install jq

find $pwd -type f -name "appsettings.json"

# Update all attributes with the correct values and save it back to the appsettings.
jq ".AzureAd.Domain=$domain | .AzureAd.TenantId=$tenantid | 
	.AzureAd.ClientId=$webappaadclientid | .AzureAd.ClientSecret=$webappaadsecret |
	.AzureAd.MRSDistCompResourceAppId=$mlsappaadclientid | .AzureAd.MRSDistCompBaseAddress=$mlsbaseaddress" "$pwd/appsettings.json" <<< $appsettings_json

#
# Now deploy the web app following these instructions
# https://docs.microsoft.com/en-us/azure/app-service/app-service-deploy-zip
#

cd /tmp/
rm "$tmp_file.zip"

cd $pwd
zip -r "/tmp/$tmp_file.zip" .

curl -X POST -u <deployment_user> --data-binary @"<zip_file_path>" https://<app_name>.scm.azurewebsites.net/api/zipdeploy
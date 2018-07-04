## Creating Azure Active Directory applications for MLSDistcomp

Each _site_ in an `MLSDistComp` network whether `Central Registry` or `Participant` requires two
Azure Active Directory applications. 

### Terminology

The Azure AD application provisioning commands in the sections below make use of a few monikers.
Replace those monikers with appropriate values as discussed below.


* <<AZURE_RESOURCE_GROUP_NAME>> - Name of an Azure resource group where all your Azure resources will be provisioned. For e.g., contosomlsdistmaster
* <<APP_NAME>> - Name of the AAD application. This could be same or different than 
* <<TENANT_NAME>> - This is the Azure tenant domain. The easiest way to find this is from the url when logged in to the Azure portal. The uri fragment that appears after - 'https://ms.portal.azure.com/#@' is your Azure domain or tenant name.
* <<NEW_GUID>> - Where mentioned, replace with a newly generated guid.
* <<RESOURCE_APP_APPLICATIONID>> - Application ID of the Resource application.



### Resource application

This AAD application is used to secure the Web APIs that will be hosted on the Microsoft Machine Learning Server
on your site. In oAuth\AAD parlance this is the `Resource` or `Audience` application.

```bash

# Execute this command at the BASH prompt on your Azure portal - https://docs.microsoft.com/en-us/azure/cloud-shell/quickstart
# after replacing monikers.
az ad app create --display-name "<<APP_NAME>>" --homepage "http://localhost:12800" --identifier-uris "http://<<TENANT_NAME>>/<<APP_NAME>>" --reply-urls "http://localhost:12800" --required-resource-accesses "[{\"resourceAppId\":\"00000002-0000-0000-c000-000000000000\",\"resourceAccess\":[{\"id\":\"<<NEW_GUID>>\",\"type\":\"Scope\"}]}]"

```

Once this command is successfully executed in the bash prompt on Azure Cloud Shell, the application manifest JSON is output on the console.
Find and note down the `appId` property value. This is the `<<RESOURCE_APP_APPLICATIONID>>` that is required for the client
AAD application.

### Client application for the resource

This AAD application is used to both secure the web application that will be hosted on the Azure App Service.
This web application will be used to manage the `MLSDistComp` for your _site_. To do so, the web application 
needs to talk to your resource or the Web APIs in a secure fashion. Thus this AAP application is the _client_ for the
_resource_ application you provisioned above. In oAuth\AAD parlance this is the `Client` application. 

```bash

az ad app create --display-name "<<APP_NAME>>client" --homepage "https://<<AZURE_RESOURCE_GROUP_NAME>>.azurewebsites.net/signin-oidc" --identifier-uris "http://<<TENANT_NAME>>/<<APP_NAME>>CLIENT" --reply-urls "https://<<AZURE_RESOURCE_GROUP_NAME>>.azurewebsites.net/signin-oidc" --required-resource-accesses "[{\"resourceAppId\":\"00000002-0000-0000-c000-000000000000\",\"resourceAccess\":[{\"id\":\"<<NEW_GUID>>\",\"type\":\"Scope\"}]}, {\"resourceAppId\":\"<<RESOURCE_APP_APPLICATIONID>>\",\"resourceAccess\":[{\"id\":\"<<NEW_GUID>>\",\"type\":\"Scope\"}]}]"

```


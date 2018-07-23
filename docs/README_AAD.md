## Creating Azure Active Directory applications for MLSDistcomp

Each _site_ in an `MLSDistComp` network whether `Central Registry` or `Participant` requires a pair of
Azure Active Directory application entries. 

### Terminology

The Azure AD application provisioning commands in the sections below make use of a few placeholders for solution-specific data.
Replace those placeholders indicated <<LIKE_THIS>> with appropriate values as discussed below.


* <<AZURE_RESOURCE_GROUP_NAME>> - Name of an Azure resource group where all your Azure resources will be provisioned. For e.g., contosomlsdistmaster. Creating a new group makes it easy to treat all constituent resources as one item.  
* <<APP_NAME>> - Name of the AAD application. This could be the same as the resource group name. 
* <<TENANT_NAME>> - This is the URI that identifies your Azure tenant domain. The easiest way to find this is from the URL when logged in to the Azure portal. The URL fragment that appears after - 'https://ms.portal.azure.com/#@' is your Azure domain or tenant name.
* <<NEW_GUID>> - Generate a new unique guid, for example using 

    `python -c 'import uuid; print(str(uuid.uuid1()))'`

* <<RESOURCE_APP_APPLICATIONID>> - Application ID of the Resource application.



### Resource application corresponds to the the "MMLServer" web-server VM

This AAD application is used to secure the `R` Web APIs that will be hosted on the Microsoft Machine Learning Server on your site. In oAuth\AAD parlance this is the `Resource` or `Audience` application.

```bash

# Execute this command at the BASH prompt on your Azure portal - https://docs.microsoft.com/en-us/azure/cloud-shell/quickstart
# after replacing placeholders.
az ad app create --display-name "<<APP_NAME>>" \
    --homepage "http://localhost:12800" \
    --identifier-uris "http://<<TENANT_NAME>>/<<APP_NAME>>" \
    --reply-urls "http://localhost:12800" \
    --required-resource-accesses "[{\"resourceAppId\":\"00000002-0000-0000-c000-000000000000\",\"resourceAccess\":[{\"id\":\"<<NEW_GUID>>\",\"type\":\"Scope\"}]}]"

```

Once this command is successfully executed in the bash prompt on Azure Cloud Shell, the application manifest JSON is output on the console. Find and note down the `appId` property value. This is the `<<RESOURCE_APP_APPLICATIONID>>` that is required for the client AAD application.

### Client application for the resource

This AAD application is used to both secure the web application that will be hosted on the Azure App Service.
This web application will be used to manage the `MLSDistComp` for your _site_. To do so, the web application 
needs to talk to the Web APIs in a securely. Thus this AAP application is the _client_ for the
_resource_ application you provisioned above. In oAuth\AAD parlance this is the `Client` application. 

```bash

az ad app create --display-name "<<APP_NAME>>client" \
    --homepage "https://<<AZURE_RESOURCE_GROUP_NAME>>.azurewebsites.net/signin-oidc" \
    --identifier-uris "http://<<TENANT_NAME>>/<<APP_NAME>>CLIENT" \
    --reply-urls "https://<<AZURE_RESOURCE_GROUP_NAME>>.azurewebsites.net/signin-oidc" \
    --required-resource-accesses "[{\"resourceAppId\":\"00000002-0000-0000-c000-000000000000\",\"resourceAccess\":[{\"id\":\"<<NEW_GUID>>\",\"type\":\"Scope\"}]}, {\"resourceAppId\":\"<<RESOURCE_APP_APPLICATIONID>>\",\"resourceAccess\":[{\"id\":\"<<NEW_GUID>>\",\"type\":\"Scope\"}]}]"

```

### Generating Client Secret Key

You must create a `Client Secret` a key that will used in the token generation process to authenticate that the requester of the token is valid. All AAD applications other than the Central Registry's Resource AAD application will need to have a Client Secret key generated.

To do so:
* Browse to the Azure Portal
* In the left-hand navigation pane, earch for `Azure Active Directory` service. Once on the page go to  `App registrations`, then select the application you want to configure. [Only the client app needs a key. "centralclient"]
* In the application's main registration page, Click the `Settings` at the top of the pane, then `Keys` in the settings pane. 
* Add password - Add a description for your password key.
* Select either a one or two year duration or Never expires option
* Click Save. **NOTE**: The right-most column will contain the key value, after you save the configuration changes. 
Be sure to copy the key for use in your client application code, as it is not accessible once you leave this page.

To create the link between resource and client apps. Go to "required permissions" under the client settings for the AAD app.  

... creating service principals.  




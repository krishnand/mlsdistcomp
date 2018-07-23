#!/bin/bash
# aad_script.sh
# MLSdistcomp deployment step to create the AAD application entries needed for the resource template deployment
# If the entry already exists the command will not create a new one, and exit with an error message.
# 23 July 2018

### First argument is used as a preface for the names of both apps
if [ "$1" = '' ]; then
    APP_NAME=mlsdistcomp
else
    APP_NAME="$1"
fi

### Second argument is the string used to identify the tenant
if [ "$2" = '' ]; then
    TENANT_NAME=microsoft.onmicrosoft.com
else
    TENANT_NAME="$2"
fi

NEW_RES_GUID=$(python3 -c 'import uuid; print(str(uuid.uuid1()))')
printf "\nCreating AAD web-service application with guid: %s\nWeb service " ${NEW_RES_GUID}

RESOURCE_APP_APPLICATIONID=$(az ad app create --display-name ${APP_NAME} \
    --homepage "http://localhost:12800" \
    --identifier-uris "http://${TENANT_NAME}/${APP_NAME}" \
    --reply-urls "https://${APP_NAME}webapp.azurewebsites.net/signin-oidc" \
    --required-resource-accesses "[{\"resourceAppId\":\"00000002-0000-0000-c000-000000000000\",\"resourceAccess\":[{\"id\":\"${NEW_RES_GUID}\",\"type\":\"Scope\"}]}]" | tee "${APP_NAME}_${NEW_RES_GUID:0:4}_output.json" | python3 aad.py)


NEW_WEB_GUID=$(python3 -c 'import uuid; print(str(uuid.uuid1()))')
printf "\nCreating AAD web-server application with guid: %s\nWeb server " ${NEW_WEB_GUID}

CLIENT_APP_APPLICATIONID=$(az ad app create --display-name "${APP_NAME}client" \
    --homepage "https://${APP_NAME}.azurewebsites.net/signin-oidc" \
    --identifier-uris "http://${TENANT_NAME}/${APP_NAME}CLIENT" \
    --reply-urls "https://${APP_NAME}webapp.azurewebsites.net/signin-oidc" \
    --required-resource-accesses "[{\"resourceAppId\":\"00000002-0000-0000-c000-000000000000\",\"resourceAccess\":[{\"id\":\"${NEW_WEB_GUID}\",\"type\":\"Scope\"}]}, {\"resourceAppId\":\"${RESOURCE_APP_APPLICATIONID}\",\"resourceAccess\":[{\"id\":\"${NEW_WEB_GUID}\",\"type\":\"Scope\"}]}]"  | tee "${APP_NAME}client_${NEW_RES_GUID:0:4}_output.json" | python3 aad.py)

printf "Remember these app Ids.  You will need them for the deployment template.\n\n"

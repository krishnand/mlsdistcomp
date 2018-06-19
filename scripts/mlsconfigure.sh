#!/bin/bash
################################################################################
#
# Virtual Machine Configuration Script for the Ubuntu ML-Server 
# This script is loaded on the VM, then executed, to load the R
# code, then run one-time operations. 
#
# Args: Master, sql credentials, certificates
#
# See the end of this file for License terms
# 
# JMA 21 May 2018  john-mark.agosta@microsoft.com
# KRISHNAD 12 June 2018 krishnad@microsoft.com
################################################################################

RSCRIPT_BINARY="/usr/bin/Rscript"
MLS_ROOT="/opt/microsoft/mlserver/9.2.1"
MLS_RLIB_PATH="${MLS_ROOT}/libraries/RServer"
MLS_ADMINUTIL_PATH="${MLS_ROOT}/o16n/Microsoft.MLServer.Utils.AdminUtil/Microsoft.MLServer.Utils.AdminUtil.dll"
MLS_WEBNODE_APPSETTINGS="${MLS_ROOT}/o16n/Microsoft.MLServer.WebNode/appsettings.json"
MLS_URL_DEFAULT='http://localhost:12800'
MLS_ADMIN_USER='admin'

if [ ! -d "${MLS_ROOT}" ]; then
    echo "MLS Root directory was not found at - $MLS_ROOT. Exiting..."
    exit 0
fi

###############################################################################
#
# Arguments
#
###############################################################################

echo "Printing input args..."
echo $@

# Configure the environment for: "Central" or "Participant"
PROFILE=${1}
# SQL Server DNS
SQL_SERVER=${2} 
# SQL Server - Database name
SQL_DATABASE=${3}
# SQL Server admin username
SQL_USER=${4}
# SQL Server admin pwd
SQL_PASSWORD=${5}
# MLSDistcomp package location.
MLSDISTCOMP_LOC=${6}
# Script where the MLSDistcomp bootstrapper script
# is located. This script deploys the web services
MLS_BOOTSTRAPPER_LOC=${7}
# Machine Learning Server (VM) DNS
MLS_URL=${8}
# Machine Learning Server 'admin' password
MLS_ADMIN_PWD=${9}
# Domain of the Azure tenant
TENANT_NAME=${10}
# AAD ApplicationID for the MLS Server
MLS_APPID=${11}
# AAD 'Client' ApplicationID configured with clientsecret and is has permissions
# setup for $MLS_APPID
MLS_CLIENTID=${12}
# Secret key on the AAD 'Client' Application
MLS_CLIENT_SECRET=${13}

###############################################################################
#
#  FUNCTIONS
#
###############################################################################

UpdateSystem()
{
    echo "Updating apt and packages..."
    sudo apt-get -y update

    echo "Installing jq, curl and libsecret packages..."
    sudo apt-get -y install curl jq libsecret-1-dev

    echo "Completed system update"
}

InstallRPackages()
{
    echo "Executing InstallRPackages..."

    # Download mlsdistcomp package to the tmp dir
    MLSDISTCOMP_PKG_PATH='/tmp/mlsdistcomp.tar.gz'

    echo "Fetching mlsdistcomp package from ${MLSDISTCOMP_LOC}"
    wget -q ${MLSDISTCOMP_LOC} -O ${MLSDISTCOMP_PKG_PATH}
    
    echo "Installing distcomp package..."
    sudo su - -c "Rscript -e \"install.packages('devtools');library(devtools);devtools::install_github('krishnand/distcomp')\""

    echo "Installing mlsdistcomp package..."
    # rlist package does not install with Imports in the mlsdistcomp. Explicitly adding it
    # lib='"${MLS_RLIB_PATH}" - Not needed. Lib path defaults to ML Server's lib path
    sudo su - -c "Rscript -e \"install.packages('rlist');install.packages('"${MLSDISTCOMP_PKG_PATH}"', repos=NULL, type='source')\""

    echo "Completed InstallRPackages"
}

UpdateMLSDistCompSecrets()
{
    echo "Executing UpdateMLSDistCompSecrets..."

    # We are going to use the keyring R package to store and access secrets.
    echo "Install the keyring package..."
    sudo su - -c "Rscript -e \"source('https://install-github.me/r-lib/keyring')\""

    echo "Setting secrets in the default keyring..."
    sudo su - -c "Rscript -e \"library(keyring);key_set_with_value('SQL_SERVERNAME',password='"${SQL_SERVER}"');key_set_with_value('SQL_DBNAME',password='"${SQL_DATABASE}"');key_set_with_value('SQL_USER',password='"${SQL_USER}"');key_set_with_value('SQL_PASSWORD',password='"${SQL_PASSWORD}"')\""
    
    echo "Completed UpdateMLSDistCompSecrets"
}

PublishMRSWebServices()
{
    echo "Executing PublishMRSWebServices..."

    # Set MLS admin password. This also restarts the ML Services
    echo "Setting MLS admin password"    
    sudo dotnet $MLS_ADMINUTIL_PATH -silentoneboxinstall $MLS_ADMIN_PWD    
    
    MLS_BOOTSTRAPPER_SCRIPT_NAME=$(basename ${MLS_BOOTSTRAPPER_LOC})
    MLS_BOOTSTRAPPER_SCRIPT_PATH="/tmp/${MLS_BOOTSTRAPPER_SCRIPT_NAME}"    

    echo "Fetching mlsdistcomp bootstrapper script from ${MLS_BOOTSTRAPPER_LOC} to ${MLS_BOOTSTRAPPER_SCRIPT_PATH}"
    wget -q $MLS_BOOTSTRAPPER_LOC -O ${MLS_BOOTSTRAPPER_SCRIPT_PATH}    

    # Path where the mlsdistcomp R script is present.
    MLSDISTCOMP_RSCRIPT_MAIN_PATH="${MLS_RLIB_PATH}/mlsdistcomp/R/mlsdistcomp"

    # Call the bootstrapper RScript in the mlsdistcomp package to deploy web services    
    echo "Executing mlsdistcomp bootstrapper ${MLS_BOOTSTRAPPER_SCRIPT_PATH}..."
    echo "Args passed: ${PROFILE} ${MLS_URL_DEFAULT} ${MLS_ADMIN_USER} ${MLS_ADMIN_PWD} ${MLSDISTCOMP_RSCRIPT_MAIN_PATH}"

    # Expected args: profile <- args[1], url <- args[2], username <- args[3], password <- args[4], mlsdistcomppath <- args[5] 
    bootstrapper_logfile=$(mktemp)
    sudo su - -c "Rscript --no-save --no-restore --verbose \"${MLS_BOOTSTRAPPER_SCRIPT_PATH}\" \"${PROFILE}"\ \"${MLS_URL}\" \"${MLS_ADMIN_USER}\" \"${MLS_ADMIN_PWD}\"" > $bootstrapper_logfile 2>&1"

    echo < $bootstrapper_logfile

    echo "Completed PublishMRSWebServices"
}

ConfigureMLSWebNode()
{
    echo "Executing ConfigureMLSWebNode..."

    # Stop ML Server services
    echo "Stopping ML Services in case they are running..."
    sudo service webnode stop
    sudo service computenode stop    

    # Update Host name & AAD Settings
    MLS_WEBNODE_APPSETTINGS_TMP='/tmp/appsettings.json'
    echo "Updating MLS Web Node appsettings to ${MLS_WEBNODE_APPSETTINGS_TMP}..."
    jq ".Kestrel.Host=\""${MLS_URL}"\"|.Authentication.AdminAccount.Enabled=false|.Authentication.AzureActiveDirectory.Enabled=true|.Authentication.AzureActiveDirectory.Authority=\""https://login.windows.net/${TENANT_NAME}"\"|.Authentication.AzureActiveDirectory.Audience=\""${MLS_APPID}"\"|.Authentication.AzureActiveDirectory.ClientId=\""${MLS_CLIENTID}"\"|.Authentication.AzureActiveDirectory.Key=\""${MLS_CLIENT_SECRET}"\"|.Authentication.AzureActiveDirectory.KeyEncrypted=false" ${MLS_WEBNODE_APPSETTINGS} > $MLS_WEBNODE_APPSETTINGS_TMP

    echo "Updating permissions on ${MLS_WEBNODE_APPSETTINGS} to allow writes..."
    sudo chmod u+w ${MLS_WEBNODE_APPSETTINGS}

    echo "Overwriting ${MLS_WEBNODE_APPSETTINGS} with ${MLS_WEBNODE_APPSETTINGS_TMP}..."
    \cp ${MLS_WEBNODE_APPSETTINGS_TMP} ${MLS_WEBNODE_APPSETTINGS}

    # Restart ML Server services
    echo "Restart ML Server..."
    sudo service computenode start
    sudo service webnode start	

    # Flush iptables
    echo "Flush iptables..."
    sudo iptables --flush

    echo "Completed ConfigureMLSWebNode"
}

###############################################################################
#
#  MAIN
#
###############################################################################

echo "This script has been tested against the Azure Ubuntu DSVM images"
echo "Other OS Versions may work but remain untested."

UpdateSystem
InstallRPackages
UpdateMLSDistCompSecrets
PublishMRSWebServices
ConfigureMLSWebNode

################################################################################
#    Copyright (c) Microsoft. All rights reserved.
#    
#    Apache 2.0 License
#    
#    You may obtain a copy of the License at
#    http://www.apache.org/licenses/LICENSE-2.0
#    
#    Unless required by applicable law or agreed to in writing, software 
#    distributed under the License is distributed on an "AS IS" BASIS, 
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or 
#    implied. See the License for the specific language governing 
#    permissions and limitations under the License.
#
################################################################################
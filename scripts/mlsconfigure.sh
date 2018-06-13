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


INSTALL_DIR="${HOME}/R"
CURL_BINARY="/usr/bin/curl"   # Or should this be installed via apt-get?
RSCRIPT_BINARY="usr/bin/Rscript"
R_BINARY="/usr/bin/R"
MLS_ROOT="/opt/microsoft/mlserver/9.2.1"
MLS_RLIB_PATH="${MLS_ROOT}/libraries/RServer"
MLS_ADMINUTIL_PATH="${MLS_ROOT}/o16n/Microsoft.MLServer.Utils.AdminUtil/Microsoft.MLServer.Utils.AdminUtil.dll"
MLS_WEBNODE_APPSETTINGS="${MLS_ROOT}/o16n/Microsoft.MLServer.WebNode/appsettings.json"
MLS_URL_DEFAULT='http://localhost:12800'
MLS_ADMIN_USER='admin'

if [ -d "$MLS_ROOT" ];
    echo "MLS Root directory was not found at - $MLS_ROOT. Exiting..."
    exit 0
fi

###############################################################################
#
# Arguments
#
###############################################################################
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
# Distcomp package location.
# NOTE: This package is custom built currently and this param will
# be removed evntually.
DISTCOMP_LOC=${6}                    
# MLSDistcomp package location.
MLSDISTCOMP_LOC=${7}
# Machine Learning Server (VM) DNS
MLS_URL=${8}
# Machine Learning Server a'admin' password
MLS_ADMIN_PWD=${9}

# Computed variables
MLSDISTCOMP_PKG_NAME=$(basename ${MLSDISTCOMP_LOC})    
MLSDISTCOMP_PKG_PATH="${PWD}/${MLSDISTCOMP_PKG_NAME}"
DISTCOMP_PKG_NAME=$(basename ${DISTCOMP_LOC})    
DISTCOMP_PKG_PATH="${PWD}/${DISTCOMP_PKG_NAME}"

###############################################################################
#
#  FUNCTIONS
#
###############################################################################

UpdateSystem()
{
    echo "Updating Apt and Packages..."

    sudo apt-get -y update
    sudo apt-get -y install curl jq

    echo "Completed system update"
}

InstallRPackages()
{
    echo "Executing InstallRPackages..."

    echo "Fetching distcomp package from ${DISTCOMP_LOC}"
    wget -q $DISTCOMP_LOC

    echo "Fetching mlsdistcomp package from ${MLSDISTCOMP_LOC}"
    wget -q $MLSDISTCOMP_LOC
    
    echo "Installing distcomp package..."
    $RSCRIPT_BINARY -e "install.packages("${DISTCOMP_PKG_PATH}", lib=${MLS_RLIB_PATH}, repos=NULL, type="source")"

    echo "Installing mlsdistcomp package..."
    $RSCRIPT_BINARY -e "install.packages("${MLSDISTCOMP_PKG_PATH}", lib=${MLS_RLIB_PATH}, repos=NULL, type="source")"

    echo "Completed InstallRPackages"
}

UpdateMLSDistCompSecrets()
{
    echo "Executing UpdateMLSDistCompSecrets..."

    # Path where the MLSDistComp secrets are present.
    # Secrets currently exist in the package. "keyring", envvars are all
    # potential cleaner options.
    $MLSDISTCOMP_SECRETS="${MLS_RLIB_PATH}/${MLSDISTCOMP_PKG_NAME%.*}/R/secrets.R"
    echo "Secrets file is expected at: ${MLSDISTCOMP_SECRETS}"

    # Make secrets editable
    echo "Making secrets file editable"
    sudo chmod 777 $MLSDISTCOMP_SECRETS

    echo "Update secrets file with the right values"
    tmp_secrets="/tmp/tmpsecrets.R"
    yes | cp -rf $MLSDISTCOMP_SECRETS $tmp_secrets

    # This script assumes that the MLSDistComp packages contains a secrets.R
    awk "{gsub('{SQL_SERVER}',"${SQL_SERVER}");
          gsub('{SQL_DATABASE}',"${SQL_DATABASE}");
          gsub('{SQL_USER}',"${SQL_USER}");
          gsub('{SQL_PASSWORD}',"${SQL_PASSWORD}");
          }1" $MLSDISTCOMP_SECRETS > $tmp_secrets && sudo mv $tmp_secrets $MLSDISTCOMP_SECRETS

    echo $MLSDISTCOMP_SECRETS

    # Remove file
    sudo rm -f $tmp_secrets

    echo "Completed UpdateMLSDistCompSecrets"
}

PublishMRSWebServices()
{
    echo "Executing PublishMRSWebServices..."

    # Set MLS admin password. This also restarts the ML Services
    echo "Setting MLS admin password"    
    sudo dotnet $MLS_ADMINUTIL_PATH -silentoneboxinstall $MLS_ADMIN_PWD
    
    # Call the bootstrapper RScript in the mlsdistcomp package to deploy web services
    $MLSDISTCOMP_BOOTSTRAPPER="${MLS_RLIB_PATH}/${MLSDISTCOMP_PKG_NAME%.*}/R/mlsdistcomp_bootstrapper.R"
    echo "Executing mlsdistcomp bootstrapper ${MLSDISTCOMP_BOOTSTRAPPER}..."
    echo "Args passed: ${PROFILE} ${MLS_URL_DEFAULT} ${MLS_ADMIN_USER} ${MLS_ADMIN_PWD}"

    # Expected args: profile <- args[1], url <- args[2], username <- args[3], password <- args[4]
    bootstrapper_logfile=$(mktemp)
    $RSCRIPT_BINARY --no-save --no-restore --verbose ${MLSDISTCOMP_BOOTSTRAPPER} 
        ${PROFILE} ${MLS_URL} ${MLS_ADMIN_USER} ${MLS_ADMIN_PWD} > $bootstrapper_logfile 2>&1

    echo < $bootstrapper_logfile

    echo "Completed PublishMRSWebServices"
}

ConfigureMLSWebNode()
{
    echo "Executing ConfigureMLSWebNode..."

    # Stop ML Server services
    echo "Stopping ML Services in case they are running..."
    sudo service stop webnode
    sudo service stop computenode    

    # Update Host name & AAD Settings
    echo "Updating MLS Web Node appsettings..."
    jq ".Kestrel.Host="${MLS_URL}"|
            .Authentication.AdminAccount.Enabled=false|
            .Authentication.AzureActiveDirectory.Enabled=true|
            .Authentication.AzureActiveDirectory.Authority="https://login.windows.net/${TENANT_NAME}"|
            .Authentication.AzureActiveDirectory.Audience=${MLS_APPID}|
            .Authentication.AzureActiveDirectory.ClientId=${MLS_CLIENTID}|
            .Authentication.AzureActiveDirectory.Key="${MLS_CLIENT_SECRET}"|
            .Authentication.AzureActiveDirectory.KeyEncrypted=false" "${MLS_WEBNODE_APPSETTINGS}"
    
    # Restart ML Server services
    echo "Restart ML Server..."
    sudo service start computenode
    sudo service start webnode	

    # Flush iptables
    echo "Flush iptables..."
    iptables --flush

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
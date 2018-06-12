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
PROFILE=${1}        # Install the central server version instead of the remote version
                    # secrets for the SQL connection string
SQL_SERVER=${2}        # SQL server name
SQL_DATABASE=${3}      # SQL account
SQL_USER=${4}         # SQL password
SQL_PASSWORD=${5}         # SQL password
DISTCOMP_LOC=${6}                    
MLSDISTCOMP_LOC=${7}                 
MLS_URL=${8}
MLS_ADMIN_PWD=${9:-'Welcome1234!'}

print_usage()
{
    echo "Usage:    ${0} [-c / --central | -h ] sql_server_dns sql_account sql_password "
    printf '\n\n'
    echo "sql_server_dns - "
    echo "sql_account    - "
    echo "sql_password   - "
    for option in "-c" "-h"
    do
        case $option in
        --central|-c)
        echo "                    --central | -c  install the central vesion of the service instead of the remote version."
        ;;
        -h)
        echo "                    -h              print this message and exit"
        ;;
        esac
    done
}

# Print help if there are no args passed.
if [ $# -eq 0 ]; then
    print_usage
    exit 0
fi

if [ $# -gt 0 ]; then
  # In case there are command line parameters, check there values.
  case $1 in
     --central | -c)
         #No separate environment to install to, so use the root.
         echo "Installing the Central node version."
         #The central version exposes a modified set of services and different web UI
         INSTALL_CENTRAL=true
         ;;
     -h)
         print_usage
         exit 0
         ;;
     *)
         echo "Error: Unknown option ${1}"
         exit 1
         ;;
  esac
fi

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
    echo "Updating Apt and Packages"
    sudo apt-get -y update
    sudo apt-get -y install curl jq
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

    echo "Completed InstallRPackages..."
}

UpdateMLSDistCompSecrets()
{
    $MLSDISTCOMP_SECRETS="${MLS_RLIB_PATH}/${MLSDISTCOMP_PKG_NAME%.*}/R/secrets.R"

    # make editable
    sudo chmod 777 $MLSDISTCOMP_SECRETS

    tmp_secrets="/tmp/tmpsecrets.R"
    yes | cp -rf $MLSDISTCOMP_SECRETS $tmp_secrets

    # This script assumes that the MLSDistComp packages contains a secrets.R
    awk "{gsub('{SQL_SERVER}',"${SQL_SERVER}");
          gsub('{SQL_DATABASE}',"${SQL_DATABASE}");
          gsub('{SQL_USER}',"${SQL_USER}");
          gsub('{SQL_PASSWORD}',"${SQL_PASSWORD}");
          }1" $MLSDISTCOMP_SECRETS > $tmp_secrets && sudo mv $tmp_secrets $MLSDISTCOMP_SECRETS

    # Remove file
    sudo rm -f $tmp_secrets
}

PublishMRSWebServices()
{
    # Set MLS admin password. This restarts the ML Services
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
}

ConfigureMLSWebNode()
{
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

    echo "MLS web server configuration completed."
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
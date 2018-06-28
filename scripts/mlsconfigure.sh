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
MLS_APP_FOLDER='/var/lib/mlsdistcomp'
MLS_APP_SECRETS_FILENAME='mlsdbsecrets.csv'

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
SQL_SERVERNAME=${2} 
# SQL Server - Database name
SQL_DBNAME=${3}
# SQL Server admin username
SQL_USER=${4}
# SQL Server admin pwd
SQL_USERPWD=${5}
# SQL DB Script
SQL_DISTCOMP_LOC=${6}
# MLSDistcomp package location.
MLSDISTCOMP_LOC=${7}
# Script where the MLSDistcomp bootstrapper script
# is located. This script deploys the web services
MLS_BOOTSTRAPPER_LOC=${8}
# Machine Learning Server (VM) DNS
MLS_DNS_NAME_OR_IP=${9}
# Machine Learning Server 'admin' password
MLS_ADMIN_PWD=${10}
# Domain of the Azure tenant
TENANT_NAME=${11}
# AAD ApplicationID for the MLS Server
MLS_APPID=${12}
# AAD 'Client' ApplicationID configured with clientsecret and is has permissions
# setup for $MLS_APPID
MLS_CLIENTID=${13}
# Secret key on the AAD 'Client' Application
MLS_CLIENT_SECRET=${14}

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

    #
    # To Install SQL tools on vanilla Ubuntu 16.04 - enable section below. Ubuntu DSVM already
    # has sql tools so skipping.
    # https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-linux-2017
    #

    #curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
    #curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list
    #sudo apt-get update 
    #sudo apt-get install mssql-tools
    #echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
    #source ~/.bashrc

    echo "Completed system update"
}

ConfigureSQLDatabase()
{
    echo "Executing ConfigureSQLDatabase..."   

    #
    # Download SQL db script locally
    #    
    SQL_SCRIPT_PATH='/tmp/mlsdistcomp.sql'
    wget -q ${SQL_DISTCOMP_LOC} -O ${SQL_SCRIPT_PATH}
    echo 'Script downloaded'

    #
    # Execute SQL CMD to provision execute schema creation script
    #
    sudo su - -c "sqlcmd -S ${SQL_SERVERNAME}.database.windows.net -U \"${SQL_USER}@${SQL_SERVERNAME}\" -P ${SQL_USERPWD} -d ${SQL_DBNAME} -i ${SQL_SCRIPT_PATH}"
    echo "Completed ConfigureSQLDatabase"    
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

# Ok so we need to setup secrets that the mlsdistcomp package can read & use.
# There are several approaches such as using secrets, keyring, env vars and so on.
# Roadblock 1: The MLS web services are going to point to an R script (the mlsdistcomp.R)
# and thus the secrets have ti be 'embedded' in it.
# Roadblock 2: Several of the facilities that work with secrets are designed for interactive use
# or restrict visibility. I tried out the keyring and it immediately ran into issues
# with just setting the keys even.
# In the interest of simplicity we simply are going to create an app folder that will
# will hold the mlsdbsecrets.csv for mlsdistcomp. It is recommended a non-admin user (with read-only privileges)
# be provisioned on the SQL and that be pointed to in here.
UpdateMLSDistCompSecrets()
{    
    echo "Executing UpdateMLSDistCompSecrets..."        
    
    sudo mkdir ${MLS_APP_FOLDER}
    sudo chmod 777 ${MLS_APP_FOLDER}

    MLSDISTCOMP_SECRETS="${MLS_APP_FOLDER}/${MLS_APP_SECRETS_FILENAME}"
    echo "Checking and removing file - ${MLSDISTCOMP_SECRETS}"
    if [ -f "${MLSDISTCOMP_SECRETS}" ] ; then
        sudo rm -f "${MLSDISTCOMP_SECRETS}"
    fi

    ###############################################
    # Expected format for the db secrets (sql azure)
    # server = "tcp:mrsdistmaster.database.windows.net,1433",
    # database = <as-is>
    # user = "mrssqladmin@mrsdistmaster",
    # password = <as-is>
    ###############################################

    SQL_SERVERNAME_FORMATTED="\"tcp:${SQL_SERVERNAME}.database.windows.net,1433\""
    SQL_USER_FORMATTED="${SQL_USER}@${SQL_SERVERNAME}"

    echo "Creating and adding content to file '${MLS_APP_FOLDER}/${MLS_APP_SECRETS_FILENAME}'"
    echo "SQL_SERVERNAME,SQL_DBNAME,SQL_USER,SQL_USERPWD" >> "${MLS_APP_FOLDER}/${MLS_APP_SECRETS_FILENAME}"
    echo "${SQL_SERVERNAME_FORMATTED},${SQL_DBNAME},${SQL_USER_FORMATTED},${SQL_USERPWD}" >> "${MLS_APP_FOLDER}/${MLS_APP_SECRETS_FILENAME}"

    echo "Completed UpdateMLSDistCompSecrets"
    ###############################################################
    # Keyring
    #

    # We are going to use the keyring R package to store and access secrets.
    #echo "Install the keyring package..."
    #sudo su - -c "Rscript -e \"source('https://install-github.me/r-lib/keyring')\""

    #echo "Setting secrets in the default keyring..."
    #sudo su - -c "Rscript -e \"library(keyring);key_set_with_value('SQL_SERVERNAME',password='"${SQL_SERVERNAME}"');key_set_with_value('SQL_DBNAME',password='"${SQL_DBNAME}"');key_set_with_value('SQL_USER',password='"${SQL_USER}"');key_set_with_value('SQL_USERPWD',password='"${SQL_PASSWORD}"')\""
    ###############################################################    
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
    sudo su - -c "Rscript --no-save --no-restore --verbose \"${MLS_BOOTSTRAPPER_SCRIPT_PATH}\" ${PROFILE} ${MLS_URL_DEFAULT} ${MLS_ADMIN_USER} ${MLS_ADMIN_PWD} ${MLSDISTCOMP_RSCRIPT_MAIN_PATH} > $bootstrapper_logfile 2>&1"
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
    jq ".Kestrel.Host=\""${MLS_DNS_NAME_OR_IP}"\"|.Authentication.AdminAccount.Enabled=false|.Authentication.AzureActiveDirectory.Enabled=true|.Authentication.AzureActiveDirectory.Authority=\""https://login.windows.net/${TENANT_NAME}"\"|.Authentication.AzureActiveDirectory.Audience=\""${MLS_APPID}"\"|.Authentication.AzureActiveDirectory.ClientId=\""${MLS_CLIENTID}"\"|.Authentication.AzureActiveDirectory.Key=\""${MLS_CLIENT_SECRET}"\"|.Authentication.AzureActiveDirectory.KeyEncrypted=false" ${MLS_WEBNODE_APPSETTINGS} > $MLS_WEBNODE_APPSETTINGS_TMP

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

    # Remove temp appsettings file
    sudo rm -vf ${MLS_WEBNODE_APPSETTINGS_TMP}

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
ConfigureSQLDatabase
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
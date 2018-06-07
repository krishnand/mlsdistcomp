#
# PARAMETERS
#

# Database server name
dbservername=$1

# Database name
dbname=$2

# Sql admin user name
adminusername=$3

# Sql admin password
adminpasswd=$4

# Sql script path
sqlscriptpath=$5

echo ******************************************
echo Inputs
echo dbservername is $dbservername
echo dbname is dbname
echo adminusername is $adminusername
echo adminpasswd is $adminpasswd
echo sqlscriptpath is $sqlscriptpath
echo Command is sqlcmd -S $dbservername.database.windows.net -U $adminusername@$dbservername -P $adminpasswd -d $dbname -i $sqlscriptpath
echo ******************************************
#
# Install SQL tools on Ubuntu 16.04
# https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-linux-2017
#

curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list
sudo apt-get update 
sudo apt-get install mssql-tools
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc
# Clean install
#sudo apt-get install mssql-tools unixodbc-dev


#
# Execute SQL CMD to provision execute schema creation script
#
sqlcmd -S $dbservername.database.windows.net -U $adminusername@$dbservername -P $adminpasswd -d $dbname -i $sqlscriptpath



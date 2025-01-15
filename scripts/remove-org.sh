#!/bin/bash
version="0.1.0"
echo "remove-org.sh v($version)"


if [ "$1" == "-h" ] ||  [ $# -lt 1 ];then
        echo "Usage: $(basename $0)  <db-name> <org-name> <org-id>"
        echo "    Param 1: The name of the DB. ex: $db_name DEV-cc PROD-cc
        echo "    Param 2: The name of the organization. If only one"
        echo "             organization of this name exists, it will be "
        echo "             deleted. If more than one organization exists"
        echo "             the org-ids will be displayed."
        echo "    Param 2: (optional) The id of the organization to delete."
       exit 0
fi
db_name=$1
org_name=$2
org_id=$3
echo "DB name: $db_name";
echo "Organization to delete: $org_name";
echo "Organization Id: $org_id";

[ -z "$RG_HOME" ] && RG_HOME='/opt/deploy/sp2'
echo "RG_HOME=$RG_HOME"
myinput=$(cat "$RG_HOME/config/mongo-config.json")
if [ -z "$myinput" ]; then
        echo "Could not find DB details file. Exiting"
        exit 1
fi

mydbuser=$(aws secretsmanager get-secret-value --secret-id RL/RG/$db_name/4.0  --version-stage AWSCURRENT | jq --raw-output .SecretString| jq -r ."username")
mydbuserpwd=$(aws secretsmanager get-secret-value --secret-id RL/RG/$db_name/4.0  --version-stage AWSCURRENT | jq --raw-output .SecretString| jq -r ."password")


if [ -z "$mydbuser" ] || [ -z "$mydbuserpwd" ]; then
        echo "Could not find DB details. Exiting"
        exit 1
fi

if [ ! -f "$RG_HOME/docker-compose.yml" ]; then
        echo "docker-compose.yml does not exist. Exiting"
        exit 1
fi
mydocdburl=$(grep DB_HOST "$RG_HOME/docker-compose.yml" | head -1 | sed -e "s/.*DB_HOST=//")
if [ -z "$mydocdburl" ]; then
        echo "Could not find DB URL. Exiting"
        exit 1
fi

mycommand=""
if [ -z "$org_id" ]; then
       mycommand="mongo '$db_name' --ssl --host $mydocdburl:27017 --sslCAFile $RG_HOME/config/rds-combined-ca-bundle.pem --username $mydbuser --password "$mydbuserpwd" --eval \"var orgName='$org_name', orgId\" $RG_HOME/config/removeOrganization.js"
       echo $mycommand;
       mongo "$db_name" --ssl --host $mydocdburl:27017 --sslCAFile $RG_HOME/config/rds-combined-ca-bundle.pem --username $mydbuser --password "$mydbuserpwd" --eval "var orgName='$org_name', orgId" $RG_HOME/config/removeOrganization.js
       exit 0
fi

if [ -z "$org_name" ]; then
       mycommand="mongo '$db_name' --ssl --host $mydocdburl:27017 --sslCAFile $RG_HOME/config/rds-combined-ca-bundle.pem --username $mydbuser --password "$mydbuserpwd" --eval \"var orgName, orgId='$org_Id'\" $RG_HOME/config/removeOrganization.js"
       echo $mycommand;
       mongo "$db_name" --ssl --host $mydocdburl:27017 --sslCAFile $RG_HOME/config/rds-combined-ca-bundle.pem --username $mydbuser --password "$mydbuserpwd" --eval "var orgName, orgId='$org_id'" $RG_HOME/config/removeOrganization.js
       exit 0
fi
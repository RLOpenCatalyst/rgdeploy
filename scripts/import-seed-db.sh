#!/bin/bash
version="0.1.2"
echo "Connecting to DB....(connect-db.sh v$version)"
STACK_NAME="${STACK_NAME:-sp2}"

if [ "$1" == "-h" ]; then
	echo "Usage: $(basename $0) [ALL | <collection-name>]"
	exit 0
fi
if [ $# -gt 0 ]; then
	mydbname=$1
fi

if [ $# -gt 1 ]; then
	mycollection=$2
fi
[ -z "$RG_HOME" ] && RG_HOME="/opt/deploy/${STACK_NAME}"
echo "RG_HOME=$RG_HOME"
[ -z "$RG_SRC" ] && RG_SRC='/home/ubuntu'
echo "RG_SRC=$RG_SRC"
myinput=$(cat "$RG_HOME/config/mongo-config.json")
if [ -z "$myinput" ]; then
	echo "Could not find DB details file. Exiting"
	exit 1
fi

mydbuser=$(jq -r '.db_auth_config.username' <<<"${myinput}")
mydbuserpwd=$(jq -r '.db_auth_config.password' <<<"${myinput}")

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
if [ "$mycollection" == "ALL" ]; then
	echo "Importing all 3 collections into $mydocdburl"
	mongoimport --host "$mydocdburl:27017" --ssl \
		--sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd" \
		--db "${mydbname}" --collection=studies \
		--jsonArray --drop "$RG_SRC/dump/studies.json"
	mongoimport --host "$mydocdburl:27017" --ssl \
		--sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd" \
		--db "${mydbname}" --collection=standardcatalogitems\
                 --jsonArray --drop "$RG_SRC/dump/standardcatalogitems.json"
	mongoimport --host "$mydocdburl:27017" --ssl \
		--sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd" \
		--db "${mydbname}" --collection=configs\
                --jsonArray --drop "$RG_SRC/dump/configs.json"
else
	# trunk-ignore(shellcheck/SC2060)
	mycollection=$(echo "$mycollection" | tr [:upper:] [:lower:])
	if [ "$mycollection" != "studies" ] && [ "$mycollection" != "standardcatalogitems" ] && [ "$mycollection" != "configs" ]; then
		echo "Unknown collection $mycollection" && exit 1
	fi
	mongoimport --host "$mydocdburl:27017" --ssl \
		--sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd" \
		--db "${mydbname}" --collection="$mycollection" \
		--jsonArray --drop "$RG_SRC/dump/$mycollection.json"
fi

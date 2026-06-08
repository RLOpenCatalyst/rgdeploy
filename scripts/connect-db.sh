#!/bin/bash
version="0.2.1"
echo "Connecting to DB....(connect-db.sh v$version)"
STACK_NAME="${STACK_NAME:-sp2}"

if [ "$1" == "-h" ]; then
	echo "Usage: $(basename $0)"
	exit 0
fi

[ -z "$RG_HOME" ] && RG_HOME="/opt/deploy/${STACK_NAME}"
echo "RG_HOME=$RG_HOME"
myinput=$(cat "$RG_HOME/config/mongo-config.json")
if [ -z "$myinput" ]; then
	echo "Could not find DB details file. Exiting"
	exit 1
fi
mydbsecret=$(jq -r ".db_auth_config.secretName" "$RG_HOME/config/mongo-config.json")
mydbuser=$(aws secretsmanager get-secret-value --secret-id "$mydbsecret"  --version-stage AWSCURRENT | jq --raw-output .SecretString| jq -r ."username")
mydbuserpwd=$(aws secretsmanager get-secret-value --secret-id "$mydbsecret"  --version-stage AWSCURRENT | jq --raw-output .SecretString| jq -r ."password")

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
encoded_pwd=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$mydbuserpwd'''))")
if command -v mongosh >/dev/null 2>&1; then
    echo "Using mongosh to connect..."
    mongosh "mongodb://${mydbuser}:${encoded_pwd}@${mydocdburl}:${dbport}/${dbname}?retryWrites=false&tls=true" \
        --tlsCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem"
elif command -v mongo >/dev/null 2>&1; then
	echo "Using mongo to connect..."
	mongo --ssl --host "$mydocdburl:27017" --sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd"
else
	echo "Error: Neither mongosh nor mongo is installed. Please install one of them to proceed."
	exit 1
fi

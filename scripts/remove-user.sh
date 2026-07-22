#!/bin/bash
version="0.2.0"
echo "remove-user.sh v($version)"

if [ "$1" == "-h" ] || [ $# -lt 1 ]; then
	echo "Usage: $(basename "$0") <user-email>"
	echo "    Param 1: The email address of the user to remove."
	exit 0
fi

user_email="$1"
[ -z "$RG_HOME" ] && RG_HOME='/opt/deploy/sp2'
echo "RG_HOME=$RG_HOME"

userpoolId=$(jq -r '.AWSCognito.userPoolId' "$RG_HOME/config/config.json")
region=$(jq -r '.AWSCognito.region' "$RG_HOME/config/config.json")

if [ -z "$userpoolId" ] || [ "$userpoolId" = "null" ] || [ -z "$region" ] || [ "$region" = "null" ]; then
	echo "Could not find User pool details. Exiting"
	exit 1
fi

# Override with DB_SECRET / DB_NAME env vars if needed
db_secret="${DB_SECRET:-RL/RG/PROD-CC/db4}"
mydbname="${DB_NAME:-PROD-cc}"
remove_user_js="${REMOVE_USER_JS:-$RG_HOME/scripts/removeUserDB.js}"

mydbuser=$(aws secretsmanager get-secret-value --secret-id "$db_secret" --version-stage AWSCURRENT \
	| jq -r '.SecretString | fromjson | .username')
mydbuserpwd=$(aws secretsmanager get-secret-value --secret-id "$db_secret" --version-stage AWSCURRENT \
	| jq -r '.SecretString | fromjson | .password')

if [ -z "$mydbuser" ] || [ -z "$mydbuserpwd" ]; then
	echo "Could not find DB details from secret $db_secret. Exiting"
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

if [ -z "$user_email" ]; then
	echo "Could not find details which you provided. Please pass proper email. Exiting"
	exit 1
fi

if [ ! -f "$remove_user_js" ]; then
	echo "Could not find $remove_user_js. Exiting"
	exit 1
fi

if command -v mongosh >/dev/null 2>&1; then
	mongo_cmd="mongosh"
elif command -v mongo >/dev/null 2>&1; then
	mongo_cmd="mongo"
else
	echo "Error: Neither mongosh nor mongo is installed."
	exit 1
fi

js_init=$(jq -rn \
	--arg useremail "$user_email" \
	--arg myregion "$region" \
	--arg myuserpoolId "$userpoolId" \
	'"var useremail=" + ($useremail | @json) + ",myregion=" + ($myregion | @json) + ",myuserpoolId=" + ($myuserpoolId | @json) + ";"')

echo "Removing user $user_email from $mydbname via $remove_user_js"

# Use CLI password flags (not URI) to avoid MongoParseError from special chars
if [ "$mongo_cmd" = "mongosh" ]; then
	$mongo_cmd --tls --host "${mydocdburl}:27017" \
		--tlsCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd" \
		--authenticationDatabase admin \
		--quiet "$mydbname" \
		--eval "$js_init" "$remove_user_js"
else
	$mongo_cmd --ssl --host "${mydocdburl}:27017" \
		--sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd" \
		--quiet "$mydbname" \
		--eval "$js_init" "$remove_user_js"
fi

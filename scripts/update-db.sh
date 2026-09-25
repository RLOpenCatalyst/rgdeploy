#!/bin/bash
version="0.1.0"
echo "Updating DB....(update-db.sh v$version)"

js_file=""
eval_args=""
while [ $# -gt 0 ]; do
	case "$1" in
	-h)
		echo "Usage: $(basename "$0") [--eval \"var x='y'\"] <script.js>"
		echo ""
		echo "  script.js          Run JS file against the configured database (required)"
		echo "  --eval \"...\"       Pass variables to the script (optional)"
		exit 0
		;;
	--eval)
		eval_args="$2"
		shift 2
		;;
	*)
		if [ -n "$js_file" ]; then
			echo "Error: Unexpected argument: $1"
			exit 1
		fi
		js_file="$1"
		shift
		;;
	esac
done

if [ -z "$js_file" ]; then
	echo "Error: JS file is required"
	echo "Usage: $(basename "$0") [--eval \"var x='y'\"] <script.js>"
	exit 1
fi
if [ ! -f "$js_file" ]; then
	echo "Error: File not found: $js_file"
	exit 1
fi

[ -z "$RG_HOME" ] && RG_HOME='/opt/deploy/sp2'
echo "RG_HOME=$RG_HOME"
myinput=$(cat "$RG_HOME/config/mongo-config.json")
if [ -z "$myinput" ]; then
	echo "Could not find DB details file. Exiting"
	exit 1
fi
mydbsecret=$(jq -r ".db_auth_config.secretName" "$RG_HOME/config/mongo-config.json")
mydbuser=$(aws secretsmanager get-secret-value --secret-id "$mydbsecret" --version-stage AWSCURRENT | jq --raw-output .SecretString | jq -r ."username")
mydbuserpwd=$(aws secretsmanager get-secret-value --secret-id "$mydbsecret" --version-stage AWSCURRENT | jq --raw-output .SecretString | jq -r ."password")

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

mydbname=$(jq -r '.db.dbName' "$RG_HOME/config/config.json")
dbport=$(jq -r '.db.port' "$RG_HOME/config/config.json")
[ -z "$dbport" ] || [ "$dbport" = "null" ] && dbport="27017"
if [ -z "$mydbname" ] || [ "$mydbname" = "null" ]; then
	echo "Could not find DB name in config.json. Exiting"
	exit 1
fi

encoded_pwd=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$mydbuserpwd'''))")
uri="mongodb://${mydbuser}:${encoded_pwd}@${mydocdburl}:${dbport}/${mydbname}?retryWrites=false&tls=true&authMechanism=SCRAM-SHA-1"

if command -v mongosh >/dev/null 2>&1; then
	mongo_cmd="mongosh"
	echo "Using mongosh to connect..."
elif command -v mongo >/dev/null 2>&1; then
	mongo_cmd="mongo"
	echo "Using mongo to connect..."
else
	echo "Error: Neither mongosh nor mongo is installed. Please install one of them to proceed."
	exit 1
fi

echo "Running $js_file against $mydbname..."
if [ "$mongo_cmd" = "mongosh" ]; then
	if [ -n "$eval_args" ]; then
		$mongo_cmd "$uri" --tlsCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
			--eval "$eval_args" --file "$js_file"
	else
		$mongo_cmd "$uri" --tlsCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
			--file "$js_file"
	fi
else
	if [ -n "$eval_args" ]; then
		$mongo_cmd "$mydbname" --ssl --host "$mydocdburl:$dbport" \
			--sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
			--username "$mydbuser" --password "$mydbuserpwd" \
			--eval "$eval_args" "$js_file"
	else
		$mongo_cmd "$mydbname" --ssl --host "$mydocdburl:$dbport" \
			--sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
			--username "$mydbuser" --password "$mydbuserpwd" \
			"$js_file"
	fi
fi
exit $?

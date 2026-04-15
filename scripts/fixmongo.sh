#!/bin/bash
version='0.1.4'
echo "Fixing MongoDB ...(fixmongo.sh v$version)"
STACK_NAME="${STACK_NAME:-sp2}"

if [ "$1" == "-h" ] || [ $# -lt 4 ]; then
	echo "Usage: $(basename $0) db_name admin_password user_name user_password"
	echo '    Param 1: Name of the DB you want to use for application user e.g. PROD-cc'
	echo '    Param 2: Administrator user password'
	echo '    Param 3: User to create e.g. App'
	echo '    Param 4: User password'
	echo '    Param 5: (optional) URL for SNS Callback'
	echo '             Will use public-host-name if not passed'
	echo '             e.g. https://myrg.example.com'
	exit 0
fi

source fixips.sh

mydbname=$1
[ -z "$RG_HOME" ] && RG_HOME="/opt/deploy/${STACK_NAME}"
echo "RG_HOME=$RG_HOME"
[ -z "$RG_SRC" ] && RG_SRC='/home/ubuntu'
echo "RG_SRC=$RG_SRC"
[ -z "$S3_SOURCE" ] && S3_SOURCE=rg-deployment-docs
echo "S3_SOURCE=$S3_SOURCE"

# First check if the IP at which mongod is listening is correct
mymongoip=$(sed -n -e 's/bindIp: \([^,]*\).*/\1/p' /etc/mongod.conf | sed -e 's/\s*//')
echo "Mongod configured to listen at $mymongoip"
# Fetch IMDSv2 session token
TOKEN=$(wget --method=PUT --header="X-aws-ec2-metadata-token-ttl-seconds: 21600" -qO- http://169.254.169.254/latest/api/token)
myip=$(wget --header="X-aws-ec2-metadata-token: $TOKEN" -qO- http://169.254.169.254/latest/meta-data/local-ipv4)
echo "Private IP of this machine is $myip"
if [ "$mymongoip" != "$myip" ]; then
	echo "Mongo is listening on a different IP $mymongoip than the private ip of the machine $myip"
	exit 1
fi

myurl=$5
if [ -z "$myurl" ]; then
	public_host_name="$(wget --header="X-aws-ec2-metadata-token: $TOKEN" -qO- http://169.254.169.254/latest/meta-data/public-hostname)"
	baseurl="http://$public_host_name/"
else
	baseurl="$myurl/"
fi
echo "Base URL is $baseurl"

systemctl is-active --quiet mongod
if [ $? -gt 0 ]; then
	echo "mongod service is not running. Starting..."
	service mongod start
	sleep 5
	systemctl is-active --quiet mongod
	if [ $? -gt 0 ]; then
		echo "Could not start mongod service"
		service mongod status
		exit 1
	fi
fi

# Seed the database with static information
if [ ! -f "$RG_SRC/dump.zip" ]; then
	echo "No seed DB in $RG_SRC. Downloading..."
	aws s3 cp s3://${S3_SOURCE}/dump.zip "$RG_SRC"
fi
echo "Extracting seed data from dump file."
unzip "$RG_SRC/dump.zip" -d "$RG_SRC"
if [ ! "$(ls -A $RG_SRC/dump)" ]; then
	echo "Error: No files found in dump folder. Your database cannot be seeded."
else
	mongoimport --host "$myip" --db "${mydbname}" --collection=standardcatalogitems \
		"$RG_SRC/dump/standardcatalogitems.json"
	mongoimport --host "$myip" --db "${mydbname}" --collection=configs \
		"$RG_SRC/dump/configs.json"
	mongoimport --host "$myip" --db "${mydbname}" --collection=studies \
		"$RG_SRC/dump/studies.json"
fi

# Modify the database to create roles and configs
echo "Modifying database $mydbname to create roles and configs"
mongo --host "$myip" "$1" <<EOF
db.createRole({
  role: "readWriteMinusDropRole",
  privileges: [
  {
    resource: { db: "$1", collection: ""},
    actions: [ "collStats", "dbHash", "dbStats", "find", "killCursors", "listIndexes", "listCollections", "convertToCapped", "createCollection", "createIndex", "dropIndex", "insert", "remove", "renameCollectionSameDB", "update"]} ],
    roles: []
  }
);
db.configs.remove({"key":"snsUrl"});
db.configs.insert({"key":"snsUrl","value":"$baseurl"});
use admin;
db.createUser({user: "admin",pwd: "$2",roles: [ { role: "userAdminAnyDatabase", db: "admin"},{role: "readWriteAnyDatabase", db: "admin"}]})
db.createUser({user: "$3", pwd: "$4", roles: [{role: 'readWriteMinusDropRole', db: "$1"}]})
EOF

# trunk-ignore(shellcheck/SC2181)
[ $? -gt 0 ] && echo "Could not create roles and configs. Exiting!" && exit 1
rootca="${RG_HOME}/config/rootCA.key"
rlca="${RG_HOME}/config/RL-CA.pem"
mongodbkey="${RG_HOME}/config/mongodb.key"
mongodbcsr="${RG_HOME}/config/mongodb.csr"
mongodbcrt="${RG_HOME}/config/mongodb.crt"
echo "Creating mongodb.pem file"
host_name="$(wget --header="X-aws-ec2-metadata-token: $TOKEN" -qO- http://169.254.169.254/latest/meta-data/local-hostname | sed -e 's/\..*//')"
openssl genrsa -out "$rootca" 2048
openssl req -x509 -new -nodes -key "$rootca" -sha256 -days 1024 -out "$rlca" -subj "/CN=."
openssl genrsa -out "$mongodbkey" 2048
openssl req -new -key "$mongodbkey" -out "$mongodbcsr" -subj "/CN=$host_name"
openssl x509 -req -in "$mongodbcsr" -CA "$rlca" -CAkey "$rootca" -CAcreateserial -out "$mongodbcrt" -days 500 -sha256
cat "$mongodbkey" "$mongodbcrt" >"$RG_HOME/config/mongodb.pem"

echo "Roles Created. Enabling authorization in mongod.conf"
if [ -f /etc/mongod.conf ]; then
	echo "mongod.conf exists"
	sed -i -e '/Enable ssl/, +4 s/^#//' -e "s/authorization:.*/authorization: enabled /" -e "s#PEMKeyFile:.*#PEMKeyFile: $RG_HOME/config/mongodb.pem#" -e "s#CAFile:.*#CAFile: $rlca#" /etc/mongod.conf
	grep -e 'authorization' -e 'PEMKeyFile' -e 'CAFile' /etc/mongod.conf
	echo "Restarting MongoD"
	service mongod restart
	sleep 10
else
	echo 'Cannot find /etc/mongod.conf'
	exit 1
fi

if [ -f "$RG_HOME/docker-compose.yml" ]; then
	echo "docker-compose.yml exists"
	sed -i -e "s/DB_HOST.*/DB_HOST=$myip/" "$RG_HOME/docker-compose.yml"
	echo "Modified docker-compose.yml with private IP of the machine"
fi

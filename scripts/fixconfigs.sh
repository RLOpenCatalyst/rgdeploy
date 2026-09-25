#!/bin/bash
version="0.1.13"
echo "Fixing configs...(fixconfig.sh v$version)"

[ -z "$RG_HOME" ] && RG_HOME='/opt/deploy/sp2'
echo "RG_HOME=$RG_HOME"
[ -z "$RG_SRC" ] && RG_SRC='/home/ubuntu'
echo "RG_SRC=$RG_SRC"
[ -z "$RG_ENV" ] && RG_ENV='PROD'
echo "RG_ENV=$RG_ENV"
[ -z "$S3_SOURCE" ] && S3_SOURCE=rg-deployment-docs
echo "S3_SOURCE=$S3_SOURCE"
# Get the session token
TOKEN=$(wget --method=PUT --header="X-aws-ec2-metadata-token-ttl-seconds: 21600" -qO- http://169.254.169.254/latest/api/token)

# Get the region to build the parameter name
instance_region=$(wget --header="X-aws-ec2-metadata-token: $TOKEN" -qO- http://169.254.169.254/latest/meta-data/placement/region)
echo "Retrieved region ${instance_region} from metadata service"

role_name="$(wget --header="X-aws-ec2-metadata-token: $TOKEN" -qO- http://169.254.169.254/latest/meta-data/iam/security-credentials/)"
echo "Role name : $role_name"
# Use the token to get instance identity document
ac_name=$(wget --header="X-aws-ec2-metadata-token: $TOKEN" -qO- http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .accountId)
echo "Account number : $ac_name"
# Get the instance id to build the parameter name
instanceid=$(wget --header="X-aws-ec2-metadata-token: $TOKEN" -qO- http://169.254.169.254/latest/meta-data/instance-id)
echo "Instance-id : $instanceid"

if ! [ -d "$RG_HOME/tmp" ]; then
	echo "$RG_HOME/tmp does not exist. Creating"
	mkdir -p "$RG_HOME/tmp"
fi

if ! [ -d "$RG_HOME/config" ]; then
	echo "$RG_HOME/config does not exist. Creating"
	mkdir -p "$RG_HOME/config"
fi
tar -xvf "$RG_SRC/config.tar.gz" -C "$RG_HOME"
if [ -z "$(ls -A $RG_HOME/config)" ]; then
	echo "FATAL: $RG_HOME/config is still empty. Exiting"
	exit 1
fi
mytemp=$(mktemp -d -p "${RG_HOME}/tmp" -t "config.old.XXX")
echo "$mytemp"
cp "${RG_HOME}/config/config.json" "$mytemp"
cp "${RG_HOME}/config/notification-config.json" "$mytemp"
cp "${RG_HOME}/config/trustPolicy.json" "$mytemp"

echo "Modifying config.json"
jq -r ".baseAccountInstanceRoleName=\"$role_name\"" "$mytemp/config.json" >"${RG_HOME}/config/config.json"

echo "Modifying notification-config.json"
jq -r ".tokenID=[\"$instanceid\"]" "$mytemp/notification-config.json" >"${RG_HOME}/config/notification-config.json"

echo "Modifying trustPolicy.json"
jq -r ".trustPolicy.Statement[0].Principal.AWS=\"arn:aws:iam::$ac_name:role/$role_name\"" "$mytemp/trustPolicy.json" >"${RG_HOME}/config/trustPolicy.json"

echo "Fetching latest docker-compose.yml"
aws s3 cp s3://${S3_SOURCE}/docker-compose.yml $RG_SRC

# Fix the APP_ENV in the docker compose file.
# DB_HOST will be set later in the fixmongo.sh or fixdocdb.sh scripts.
echo "Copying docker-compose.yml from $RG_SRC to $RG_HOME"
# trunk-ignore(shellcheck/SC2016)
repcmd='s#\${PWD}#'$RG_HOME'#'
echo "Modifying docker-compose.yml"
sed -e "$repcmd" -e "s#APP_ENV=.*#APP_ENV=$RG_ENV#" "$RG_SRC/docker-compose.yml" >"$RG_HOME/docker-compose.yml"
grep -i "APP_ENV" "$RG_HOME/docker-compose.yml"
echo "Modified docker-compose.yml"

for dir in logs slogs topologies catalog integrations notification_sink_logs; do
	mkdir -p "$RG_HOME/$dir"
done

if [ -f "$RG_SRC/nginx.conf" ]; then
	cp "$RG_SRC/nginx.conf" "$RG_HOME/nginx.conf"
elif aws s3 cp "s3://${S3_SOURCE}/nginx.conf" "$RG_HOME/nginx.conf" 2>/dev/null; then
	echo "Copied nginx.conf from S3"
else
	echo "WARNING: nginx.conf not found in $RG_SRC or s3://${S3_SOURCE}/nginx.conf"
fi

echo 'Configuration changed successfully'

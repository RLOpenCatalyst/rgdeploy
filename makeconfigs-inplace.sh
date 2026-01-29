#!/bin/bash
version="0.1.0"
echo "Making configs locally...(makeconfigs.sh v$version)"
# Ensure right number of params
if [ $# -lt 8 ]; then
	echo 'At least 8 parameters are required!'
	echo '  Param 1: AWS Cognito User Pool id'
	echo '  Param 2: AWS Cognito client id'
	echo '  Param 3: RG Bucket Name (The bucket where CFT templates are stored)'
	echo '  Param 4: App username'
	echo '  Param 5: URL to reach RG'
	echo '           e.g https://rg.example.com'
	echo '           Note that the protocol will be picked from this param!'
	echo '  Param 6: AWS Region'
	echo '  Param 7: Hosted Zone Id in Route53 to be used for enabling SSL'
    echo '            in projects'
	echo '  Param 8: AWS secret ARN'
	exit 1
fi

myuserpoolid=$1
myclientid=$2
mys3bucket=$3
myappuser=$4
myapppwd=$(date +%s | sha256sum | base64 | tr -dc _a-z-0-9 | head -c 24)
myrunid=$(date +%s | sha256sum | base64 | tr -dc _a-z-0-9 | head -c 4)
myurl=$5
# Get the IMDSv2 token
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Get IAM Role name
role_name=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/ | head -n 1)

# Get Account ID
ac_name=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .accountId)

region=$6
secret_arn=${8}
RG_HOME=$(mktemp -d -t "config.$myrunid.XXX")
echo "RG_HOME=$RG_HOME"
[ -z "$RG_SRC" ] && RG_SRC='/home/ubuntu/rgdeploy'
echo "RG_SRC=$RG_SRC"
[ -z "$RG_ENV" ] && RG_ENV='PROD'
echo "RG_ENV=$RG_ENV"
echo "Region : $region"
echo "Role name : $role_name"
if [ -z "$ac_name" ]; then
	ac_name=$(
		wget -q -O - http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .accountId
	)
	[ -z "$ac_name" ] && echo "Error: Account Number is needed" && exit 1
fi
echo "Account number : $ac_name"
r53_hosted_zone=${7}
generated_token=$(
	date +%s | sha256sum | base64 | tr -dc _a-z-0-9 | head -c 24
	echo
)
echo "Generated token : $generated_token"
if [ -z "$myurl" ]; then
	echo "ERROR: No RG URL passed. Exiting."
	exit 1
fi
baseurl="$myurl/"
echo "Base URL set to $baseurl"
snsprotocol=$(
	echo "$myurl" | sed -e 's/\(http.*:\/\/\).*/\1/' -e 's/://' -e 's/\///g'
)
[ -z "$snsprotocol" ] && echo "RG URL must begin with http or https" && exit 1
echo "snsprotocol set to $snsprotocol"
r53_domain_name="${myurl//http[s]*:\/\//}"
echo "Domain name is ${r53_domain_name}"
mkdir -p "$RG_HOME/config"
mytemp="$RG_SRC/config"
if [ ! -e "$mytemp" ]; then
	echo "Error: Did not find $mytemp folder. Run this from rgdeploy folder"
	exit 1
fi
cp "$mytemp"/* "$RG_HOME/config"
s3url="https://${mys3bucket}.s3.${region}.amazonaws.com/"
echo "Modifying config.json"
if [ -z "$baseurl" ]; then
	echo "WARNING: Base URL is not passed. config.json file may not be configured correctly"
fi
jq -r ".baseURL=\"$baseurl\"" "$mytemp/config.json" |
	jq -r ".googleOAuthCredentials.callbackURL=\"$baseurl\"" |
	jq -r ".baseAccountInstanceRoleName=\"$role_name\"" |
	jq -r '.baseAccountPolicyName="RG-Portal-CrossAccount-Policy"' |
	jq -r ".baseAccountNumber=\"$ac_name\"" |
	jq -r ".researchGatewayAPIToken=\"$generated_token\"" |
	jq -r ".BucketName=\"$mys3bucket\"" |
	jq -r ".cftTemplateURL=\"$s3url\"" |
	jq -r ".AWSCognito.userPoolId=\"$myuserpoolid\"" |
	jq -r ".AWSCognito.clientId=\"$myclientid\"" |
    jq -r ".route53.domainName=\"${r53_domain_name}\"" |
    jq -r ".route53.hostedZoneId=\"${r53_hosted_zone}\"" |
	jq -r ".AWSCognito.region=\"$region\"" |
	jq -r ".sampleCSVBucketRegion=\"$region\"" |
	jq -r ".enableB2CMode=false" >"${RG_HOME}/config/config.json"
echo "Modifying snsConfig.json"
if [ -z "$snsprotocol" ]; then
	echo "WARNING: SNS protocol could not be determined. Did you pass in the correct RG URL?"
	echo "snsConfig.json file may not be configured correctly"
fi
jq -r ".snsProtocol=\"$snsprotocol\"" "$mytemp/snsConfig.json" >"${RG_HOME}/config/snsConfig.json"
echo "Modifying mongo-config.json"
jq -r ".db_ssl_enable=true" "$mytemp/mongo-config.json" |
	jq -r '.db_ssl_config.CAFile="rds-combined-ca-bundle.pem"' |
	jq -r ".db_auth_enable=true" |
	jq -r ".db_documentdb_enable=true" |
	jq -r ".db_auth_config.username=\"$myappuser\"" |
	jq -r ".db_auth_config.password=\"$myapppwd\"" |
	jq -r ".db_auth_config.secretName=\"$secret_arn\"" |
	jq -r '.db_auth_config.authenticateDb="admin"' >"${RG_HOME}/config/mongo-config.json"

echo "Modifying notification-config.json"
jq -r ".tokenID=[\"$generated_token\"]" "$mytemp/notification-config.json" >"${RG_HOME}/config/notification-config.json"
echo "Modifying trustPolicy.json"
jq -r ".trustPolicy.Statement[0].Principal.AWS=\"arn:aws:iam::$ac_name:role/$role_name\"" "$mytemp/trustPolicy.json" |
	jq -r ".roleName=\"RG-Portal-ProjectRole-$RG_ENV-$myrunid\"" |
	jq -r ".policyName=\"RG-Portal-ProjectPolicy-$RG_ENV-$myrunid\"" >"${RG_HOME}/config/trustPolicy.json"
echo "Modifying mongo-config.json file"
jq -r ".db_ssl_enable=true" "$mytemp/mongo-config.json" |
	jq -r ".db_auth_enable=true" |
	jq -r ".db_documentdb_enable=true" |
	jq -r '.db_ssl_config.CAFile="rds-combined-ca-bundle.pem"' |
	jq -r '.db_ssl_config.PEMFile="mongodb.pem"' |
	jq -r ".db_auth_config.username=\"$myappuser\"" |
	jq -r ".db_auth_config.password=\"$myapppwd\"" |
	jq -r ".db_auth_config.secretName=\"$secret_arn\"" |
	jq -r '.db_auth_config.authenticateDb="admin"' >"${RG_HOME}/config/mongo-config.json"
tar -C $RG_HOME -cvzf config.tar.gz "config"
tar -tf config.tar.gz
rm -rf "$RG_HOME"
echo 'Configuration changed successfully'
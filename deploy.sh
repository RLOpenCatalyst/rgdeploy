#!/bin/bash

# Verify that utilities we use in this script are installed on the machine
echo "Verifying utilities are installed"
apps=(jq aws)
for program in "${apps[@]}"; do
	if ! command -v "$program" >/dev/null 2>&1; then
		echo "$program not found. This Script needs jq and aws cli. Please install the application/s and restart deployment, Exiting."
		exit
	else
		echo "$program found"
	fi
done
region=$(aws configure list | grep region | awk '{print $2}')
echo "current aws region is $region"

if [ "$1" = "-f" ]; then
	if [ -z "$2" ]; then
		echo "Need a filename with -f option"
		exit 1
	fi
	if ! [ -f "$2" ]; then
		echo "Could not find file $2"
		exit 1
	fi
	echo "Reading past run details from $2"
	myinput=$(cat "$2")
	amiid=$(jq -r '.params.amiid' <<<"${myinput}")
	bucketname=$(jq -r '.params.bucketname' <<<"${myinput}")
	vpcid=$(jq -r '.params.vpcid' <<<"${myinput}")
	subnet1id=$(jq -r '.params.subnet1id' <<<"${myinput}")
	subnet2id=$(jq -r '.params.subnet2id' <<<"${myinput}")
	subnet3id=$(jq -r '.params.subnet3id' <<<"${myinput}")
	keypairname=$(jq -r '.params.keypairname' <<<"${myinput}")
	env=$(jq -r '.params.environment' <<<"${myinput}")
	rgurl=$(jq -r '.params.rgurl' <<<"${myinput}")
	tgarn=$(jq -r '.params.tgarn' <<<"${myinput}")

	runid=$(jq -r '.runid' <<<"${myinput}")
	appuser=$(jq -r '.appuser' <<<"${myinput}")
	appuserpassword=$(jq -r '.appuserpassword' <<<"${myinput}")
	adminpassword=$(jq -r '.adminpassword' <<<"${myinput}")
	S3_SOURCE=$(jq -r '.s3src' <<<"${myinput}")
	echo "Run ID: $runid"
	echo "APPUSER: $appuser"
	echo "APPUSERPWD: $appuserpassword"
	echo "ADMINPWD: $adminpassword"
	echo "AMIID: $amiid"
	echo "BUCKET: $bucketname"
	echo "VPCID: $vpcid"
	echo "SUBNET1: $subnet1id"
	echo "SUBNET2: $subnet2id"
	echo "SUBNET3: $subnet3id"
	echo "KEYPAIR: $keypairname"
	echo "RGURL: $rgurl"
	echo "TGARN: $tgarn"
	echo "S3_SOURCE: $S3_SOURCE"

elif [ $# -lt 7 ]; then
	echo 'Usage: deploy.sh <amiid> <bucketname> <rgurl> '
	echo '       Param 1:  The AMI from which the EC2 for Research Gateway should be created'
	echo '       Param 2:  The S3 bucket to create for holding the CFT templates'
	echo '                 A random suffix will be added to uniquify the name'
	echo '       Param 3:  The VPC in which to launch the Research Gateway EC2 instance, DocumentDB'
	echo '       Param 4:  The Subnet1 in which to launch the Research Gateway DocumentDB'
	echo '       Param 5:  The Subnet2 in which to launch the Research Gateway DocumentDB'
	echo '       Param 6:  The Subnet3 in which to launch the Research Gateway DocumentDB'
	echo '       Param 7:  The Key Pair to use for launching the EC2 instance.'
	echo '       Param 8:  The Environment DEV / QA / STAGE / PROD to deploy DB instance.'
	echo '       Param 9:  The URL at which Research Gateway will be accessed'
	echo '       Param 10: The Target Group to which the Portal EC2 instance should be added'
	echo '       Param 11: The hosted-zone ID for URL in param 9.'
	exit 1
else
	echo "New run"
	amiid=$1
	bucketname=$2
	vpcid=$3
	subnet1id=$4
	subnet2id=$5
	subnet3id=$6
	keypairname=$7
	env=$8
	rgurl=$9
	tgarn=${10}

	runid=$(
		date +%s | sha256sum | base64 | tr -dc _a-z-0-9 | head -c 4
		echo
	)
	appuser='rguser'
	appuserpassword=$(
		date +%s | sha256sum | base64 | tr -dc _a-z-0-9 | head -c 24
		echo
	)
	adminpassword=$(
		date +%s | sha256sum | base64 | tr -dc _a-z-0-9 | head -c 24
		echo
	)
	[ -z "$S3_SOURCE" ] && S3_SOURCE=rg-deployment-docs
	echo "S3 Source bucket is $S3_SOURCE"

	cat <<EOT >>"$runid.json"
  {
    "runid": "$runid",
    "appuser": "$appuser",
    "appuserpassword": "$appuserpassword",
    "adminpassword": "$adminpassword",
    "s3src": "$S3_SOURCE",
    "params": {
      "amiid":  "$amiid",
      "bucketname":  "$bucketname",
      "vpcid":  "$vpcid",
      "subnet1id":  "$subnet1id",
      "subnet2id":  "$subnet2id",
      "subnet3id":  "$subnet3id",
      "keypairname":  "$keypairname",
      "environment": "$env",
      "rgurl":  "$rgurl",
      "tgarn":  "$tgarn"
    }
  }
EOT
fi
aws ec2 describe-images --image-id "$amiid" >/dev/null 2>&1
# trunk-ignore(shellcheck/SC2181)
if [ $? -gt 0 ]; then
	echo "The AMI $amiid does not exist. Exiting"
	exit 1
fi

if ! echo "$bucketname" | grep -q -P '(?=^.{3,63}$)(?!^xn\-\-)(?!.*s3alias$)(?!^(\d+\.)+\d+$)(^(([a-z0-9]|[a-z0-9][a-z0-9\-]*[a-z0-9])\.)*([a-z0-9]|[a-z0-9][a-z0-9\-]*[a-z0-9])$)'; then
	echo "Invalid bucketname passed"
	echo "See https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html"
	exit 1
fi

aws ec2 describe-vpcs --vpc-id "$vpcid" >/dev/null 2>&1
# trunk-ignore(shellcheck/SC2181)
if [ $? -gt 0 ]; then
	echo "The VPC $vpcid does not exist. Exiting."
	exit 1
fi

aws ec2 describe-subnets --filters Name=vpc-id,Values="$vpcid" --subnet-ids "$subnet1id" >/dev/null 2>&1
# trunk-ignore(shellcheck/SC2181)
if [ $? -gt 0 ]; then
	echo "The subnet $subnet1id does not belong to $vpcid. Exiting."
	exit 1
fi

aws ec2 describe-subnets --filters Name=vpc-id,Values="$vpcid" --subnet-ids "$subnet2id" >/dev/null 2>&1
# trunk-ignore(shellcheck/SC2181)
if [ $? -gt 0 ]; then
	echo "The subnet $subnet2id does not belong to $vpcid. Exiting."
	exit 1
fi

aws ec2 describe-subnets --filters Name=vpc-id,Values="$vpcid" --subnet-ids "$subnet3id" >/dev/null 2>&1
# trunk-ignore(shellcheck/SC2181)
if [ $? -gt 0 ]; then
	echo "The subnet $subnet3id does not belong to $vpcid. Exiting."
	exit 1
fi

aws ec2 describe-key-pairs --key-name "$keypairname" >/dev/null 2>&1
# trunk-ignore(shellcheck/SC2181)
if [ $? -gt 0 ]; then
	echo "The KeyPair provided is not found. Exiting."
	exit 1
fi

echo "$rgurl" | grep -i -e '^http'
# trunk-ignore(shellcheck/SC2181)
if [ $? -gt 0 ]; then
	echo "The URL $rgurl must begin with http. Exiting."
	exit 1
fi

aws elbv2 describe-target-groups --target-group-arns "$tgarn" >/dev/null
# trunk-ignore(shellcheck/SC2181)
if [ $? -gt 0 ]; then
	echo "The Target Group ARN $tgarn does not exists. Exiting."
	exit 1
fi

function calculate_duration() {
	mylabel=$1
	mystarttime=$2
	myelapsedtime=$((SECONDS - mystarttime))
	# trunk-ignore(shellcheck/SC2016)
	eval "echo $mylabel Elapsed time: $(date -ud "@$myelapsedtime" +'$((%s/3600/24)) %M min %S sec')"
}

localhome=$(pwd)
bucketstackname="RG-PortalStack-Bucket-$runid"
start_time=$SECONDS

echo "Update Parameter Store"
scripts/updatessmpaths.sh "$region" "$localhome"

BUCKET_TEST=$(aws s3api head-bucket --bucket "$bucketname" 2>&1)
if [ -z "$BUCKET_TEST" ]; then
	echo "Bucket $bucketname exists, Hit Enter to continue, Ctrl-C to exit"
	bucket_region=$(aws s3api get-bucket-location --bucket "$bucketname" | jq -r ".LocationConstraint")
      if [[ "$bucket_region" != "$region" ]]; then
          echo "The given bucket $bucketname is not in $region. Please provide a bucket in this region."
          exit 1
      fi
	read -r a && echo "Copying files to bucket $bucketname"
else
	echo "An S3 bucket with name $bucketname  doesn't exist in current AWS account. Creating..."

	# Create S3 bucket to copy RG Deployment files, ensure --stack-name 'name'
	# should be unique and it does not exist as part of current stacks.
	echo "Deploying the bucket stack"
	aws cloudformation deploy --template-file rg_deploy_bucket.yml --stack-name "$bucketstackname" \
		--parameter-overrides S3NewBucketName="$bucketname"
	echo "Waiting for stack $bucketname to finish deploying..."
	aws cloudformation wait stack-create-complete --stack-name "$bucketstackname"
	if [ $? -eq 255 ]; then
		echo "Failed to deploy stack $bucketstackname Exiting"
		exit 1
	fi
fi
# Populate the new S3 bucket with RG Deployment files
echo "Copying docker-compose.yml file"
aws s3 cp "$localhome"/docker-compose.yml s3://"$bucketname"
echo "Copying nginx.conf file"
aws s3 cp "$localhome"/nginx.conf s3://"$bucketname"
echo "Copying updatescripts.sh file"
aws s3 cp "$localhome"/updatescripts.sh s3://"$bucketname"


#Modify file rg_userpool.yml to refer new S3 bucket
#sed -i -e "s/S3Bucket:.*/S3Bucket: $bucketname/" "$localhome"/rg_userpool.yml

#Copy extracted cft template to the new bucket
echo "Copying deployment files to new bucket"
aws s3 sync "$localhome/cft-templates/" s3://"$bucketname/"

echo "Copying config files to new bucket"
tar -czf config.tar.gz config/*
tar -tf config.tar.gz
aws s3 cp "$localhome"/config.tar.gz s3://"$bucketname"
rm -f config.tar.gz

echo "Copying script files to new bucket"
sed -i "s/secret_name/RL-RG-$runid-$env/g"  "$localhome"/scripts/connect-db.sh  
tar -czf scripts.tar.gz scripts/*
tar -tf scripts.tar.gz
aws s3 cp "$localhome"/scripts.tar.gz s3://"$bucketname"
rm -f scripts.tar.gz

echo "Copying bootstrap scripts to new bucket"
aws s3 cp "$localhome"/scripts/bootstrap-scripts/ s3://"$bucketname/"bootstrap-scripts --recursive


echo "Copying lambda files to new bucket"
cd "$localhome"/lambdas || exit
zip -j pre_verification_custom_message.zip pre_verification_custom_message/index.js
zip -j post_verification_send_message.zip post_verification_send_message/index.js
aws s3 cp ./pre_verification_custom_message.zip s3://"$bucketname"
aws s3 cp ./post_verification_send_message.zip s3://"$bucketname"
rm -f ./pre_verification_custom_message.zip ./post_verification_send_message.zip

echo "Copying Image Builder files to new bucket"
cd "$localhome"/products || exit
tar -czf nextflow-advanced.tar.gz Nextflow-Advanced/*
aws s3 cp ./nextflow-advanced.tar.gz s3://"$bucketname/"
rm -f nextflow-advanced.tar.gz
tar -czf rstudio.tar.gz RStudio/*
aws s3 cp ./rstudio.tar.gz s3://"$bucketname/"
rm -f rstudio.tar.gz
tar -czf nicedcv.tar.gz Nicedcv/*
aws s3 cp ./nicedcv.tar.gz s3://"$bucketname/"
rm -f nicedcv.tar.gz
zip -r ec2-winsecure-image.zip ec2-secure-windows/*
aws s3 cp ./ec2-winsecure-image.zip s3://"$bucketname/"
rm -f ec2-winsecure-image.zip
tar -czf Rhelnicedcv.tar.gz Rhelnicedcv/*
aws s3 cp ./Rhelnicedcv.tar.gz s3://"$bucketname/"
rm -f Rhelnicedcv.tar.gz


cp ./PCluster/machine-images/config/infra/files/pcluster/slurm-main.yaml  ./PCluster/machine-images/config/infra/files/pcluster/slurm.yaml
cp ./PCluster/machine-images/config/infra/files/pcluster/batch-main.yaml  ./PCluster/machine-images/config/infra/files/pcluster/batch.yaml
sed -i "s/tempbucket/$bucketname/g" ./PCluster/machine-images/config/infra/files/pcluster/slurm.yaml
sed -i "s/tempbucket/$bucketname/g" ./PCluster/machine-images/config/infra/files/pcluster/batch.yaml
tar -czf PCluster.tar.gz PCluster/*
aws s3 cp ./PCluster.tar.gz s3://"$bucketname/"
rm -f ./PCluster/machine-images/config/infra/files/pcluster/slurm.yaml
rm -f ./PCluster/machine-images/config/infra/files/pcluster/batch.yaml 
rm -f PCluster.tar.gz

echo "Copying Database seed-data files to new bucket"
cd "$localhome" || exit
zip dump.zip dump/*
unzip -l dump.zip
aws s3 cp dump.zip s3://"$bucketname/"
rm -f dump.zip

#=====================================================================================================
function get_stack_status() {
	stackname=$1
	stack_status=0
	jqcmd='.StackSummaries | map(select(.StackName=='"\"$stackname\""')|  .u=(.LastUpdatedTime[:16] | strptime("%Y-%m-%dT%H:%M") | mktime)) | sort_by(.u)| .[-1]'
	#echo $jqcmd
	stack_exists=$(echo "$stack_summaries" | jq -r "$jqcmd")

	if [ -z "$stack_exists" ] || [ "$stack_exists" == "null" ]; then
		# stack does not exist
		return 0
	fi
	#echo $stack_exists | jq -r
	stack_status=$(echo "$stack_exists" | jq -r '.StackStatus')
	echo "$stack_status"
	#if [ "$stack_status" == "CREATE_COMPLETE" ]; then
	if [ "$stack_status" == "CREATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS" ] || [ "$stack_status" == "UPDATE_ROLLBACK_COMPLETE" ]; then
		return 1
	#elif [ "$stack_status" == "ROLLBACK_COMPLETE" ] || [ "$stack_status" == "UPDATE_ROLLBACK_COMPLETE" ]; then
	elif [ "$stack_status" == "CREATE_FAILED" ] || [ "$stack_status" == "ROLLBACK_COMPLETE" ] || [ "$stack_status" == "ROLLBACK_FAILED" ] || [ "$stack_status" == "UPDATE_FAILED" ]; then
		return 2
	elif [ "$stack_status" == "DELETE_COMPLETE" ]; then
		return 0
	else
		# stack exists but with status other than above
		return 3
	fi
}

function delete_stack() {
	echo "Deleting stack $1"
	aws cloudformation delete-stack --stack-name "$1"
	aws cloudformation wait stack-delete-complete --stack-name "$1"
}

function create_cognito_pool() {
	echo "Creating new stack $1"
	aws cloudformation deploy --template-file "$localhome"/rg_userpool.yml \
		--stack-name "$1" \
		--parameter-overrides UserPoolNameParam="$1" PortalURLParam="$rgurl" \
		Function1Name="post_verification_send_message-$runid" Function2Name="pre_verification_custom_message-$runid" \
		CFTBucketName="$bucketname" --capabilities CAPABILITY_IAM

	aws cloudformation wait stack-create-complete --stack-name "$userpoolstackname"
}

function create_doc_db() {
	echo "Creating new stack $1"
	aws cloudformation deploy --template-file "$localhome"/rg_document_db.yml --stack-name "$1" \
		--parameter-overrides DocDBSecretName="RL-RG-$runid-$env" VpceSecurityGroupName="RGVE-SG-$runid" \
		DBClusterName="RGCluster-$runid" DBInstanceName="RGInstance-$runid" DBInstanceClass="db.t3.medium" \
		Subnet1="$subnet1id" Subnet2="$subnet2id" Subnet3="$subnet3id" VPC="$vpcid" \
		SecurityGroupName="RGDB-SG-$runid" DocDBSubnetGroupName="RGDBSubnet-$runid" --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
	echo "Waiting for stack $1 to finish deploying..."
	aws cloudformation wait stack-create-complete --stack-name "$1"
}

function create_image_builder() {
	echo "Creating new stack $1"
	aws cloudformation deploy --template-file "$localhome"/products/rg_imgbldr.yml --stack-name "$1" \
		--parameter-overrides PrivateSubnetId="$subnet1id" VPCId="$vpcid" SourceBucketName="$bucketname" \
    --capabilities CAPABILITY_IAM
	echo "Waiting for stack $1 to finish deploying..."
	aws cloudformation wait stack-create-complete --stack-name "$1"

}


function create_main_stack() {
	echo "Creating new stack $1"
	#update the AMI id in the RGMainStack CFT
	if echo "$amiid" | grep -E '^ami-[0-9a-zA-Z]+'; then
		echo "Valid AMI Id $amiid passed. Replacing in RGMainStack"
		sed -i -E "s/ami-[0-9a-zA-Z]+/$amiid/" "$localhome"/rg_main_stack.yml
	fi
	echo "UserPool Id: $userpool_id"
	echo "UserPool ClientId: $userpoolclient_id"
	echo "BucketName $bucketname"
	echo "RG URL: $rgurl"
	if [ -n "$secpassword" ]; then
		echo "UserPassword is not a blank string"
	fi
	if [ -n "$adminpassword" ]; then
		echo "AdminPassword is not a blank string"
	fi
	echo "VPC Id: $vpcid"
	echo "subnet1id: $subnet1id"
	echo "Key Pair: $keypairname"
	echo "TGARN: $tgarn"
	echo "DocDBURL: $docdburl"
	echo "Env: $env"
	echo "Source Bucket: $S3_SOURCE"
	aws cloudformation deploy --template-file "$localhome"/rg_main_stack.yml \
		--stack-name "$mainstackname" \
		--parameter-overrides CFTBucketName="$bucketname" RGUrl="$rgurl"\
		UserPassword="$secpassword" AdminPassword="$adminpassword" \
		VPC="$vpcid" Subnet1="$subnet1id" KeyName1="$keypairname" TGARN="$tgarn" \
		DocumentDBInstanceURL="$docdburl" Environment="$env" BaseAccountPolicyName="RG-Portal-Base-Account-Policy-$env-$runid" \
		--capabilities CAPABILITY_NAMED_IAM
	echo "Waiting for stack $1 to finish deploying..."
	aws cloudformation wait stack-create-complete --stack-name "$mainstackname"
}
#===============================================================================================================
stack_summaries=$(aws cloudformation list-stacks)
#===============================================================================================================
#Creating the Cognito User Pool
echo "Creating Cognito User Pool"
userpoolstackname="RG-PortalStack-UserPool-$runid"
# getstack status if returns 2 exit, if 0 (Create-complete) skip this block 229 to 235
# if it is 1  delete stack if delete fails, exit stack exists manually delete and retry,
# next create the new stack.
echo "$userpoolstackname"
eval "get_stack_status $userpoolstackname"
stack_status=$?
echo $stack_status
#exit 0
if [ $stack_status -eq 3 ]; then
	exit 1
fi
if [ $stack_status -eq 2 ]; then
	if ! delete_stack "$userpoolstackname"; then
		echo "Could not delete stack $userpoolstackname"
		exit 1
	fi
	stack_status=0
fi
if [ $stack_status -eq 0 ]; then
	create_cognito_pool "$userpoolstackname"
	if ! create_cognito_pool "$userpoolstackname"; then
		aws cloudformation describe-stack-events --stack-name "$userpoolstackname"
		exit 1
	fi	
fi

#Capture User Pool Client ID
userpoolclient_id=$(aws cloudformation describe-stack-resources --stack-name "$userpoolstackname" --logical-resource-id CognitoUserPoolClient | jq -r '.StackResources [] | .PhysicalResourceId')
#Capture User Pool ID
userpool_id=$(aws cloudformation describe-stack-resources --stack-name "$userpoolstackname" --logical-resource-id CognitoUserPool | jq -r '.StackResources [] | .PhysicalResourceId')
if [ -z "$userpoolclient_id" ] || [ -z "$userpool_id" ]; then
	echo "Unable to extract user pool outputs. Exiting."
	exit 1
fi

#===============================================================================================================
#Creating DocumentDB stack
echo "Creating DocumentDB stack"
docdbstackname="RG-PortalStack-DocDB-$runid"
# getstack status if returns 2 exit, if 0 (Create-complete) skip this block 254 to 260
# if it is 1  delete stack if delete fails, exit stack exists manually delete and retry,
# next create the new stack.
echo "$docdbstackname"
eval "get_stack_status $docdbstackname"
stack_status=$?
echo $stack_status
docdb_start_time=$SECONDS
if [ $stack_status -eq 3 ]; then
	exit 1
fi
if [ $stack_status -eq 2 ]; then
	if ! delete_stack "$docdbstackname"; then
		echo "Could not delete stack $docdbstackname"
		exit 1
	fi
	stack_status=0
fi
if [ $stack_status -eq 0 ]; then
	if ! create_doc_db "$docdbstackname"; then
		aws cloudformation describe-stack-events --stack-name "$docdbstackname"
		exit 1
	fi		
fi
calculate_duration "DocumentDB Instance Creation" "$docdb_start_time"

#Capture DocumentDB Instance Id
docdburl=$(aws cloudformation describe-stacks --stack-name "$docdbstackname" | jq -r '.Stacks[] | .Outputs[] | select(.OutputKey=="InstanceEndpoint")|.OutputValue')
if [ -z "$docdburl" ]; then
	echo "Unable to extract DocumentDB outputs. Exiting."
	exit 1
fi
#===============================================================================================================
#Creating Image Builder Pipelines
echo "Creating Image Builder Pipelines stack"
imgbldrstackname="RG-PortalStack-ImageBuilder-$runid"
# getstack status if returns 2 exit, if 0 (Create-complete) skip this block 254 to 260
# if it is 1  delete stack if delete fails, exit stack exists manually delete and retry,
# next create the new stack.
echo "$imgbldrstackname"
eval "get_stack_status $imgbldrstackname"
stack_status=$?
echo $stack_status
imgbldr_start_time=$SECONDS
if [ $stack_status -eq 3 ]; then
	exit 1
fi
if [ $stack_status -eq 2 ]; then
	if ! delete_stack "$imgbldrstackname"; then
		echo "Could not delete stack $imgbldrstackname"
		exit 1
	fi
	stack_status=0
fi
if [ $stack_status -eq 0 ]; then
	if ! create_image_builder "$imgbldrstackname"; then
		aws cloudformation describe-stack-events --stack-name "$imgbldrstackname"
		exit 1
	fi	
fi
calculate_duration "Image Builder Stack Creation" "$imgbldr_start_time"

#Capture Image Builder stack outputs
echo "Image Builder stack outputs"
aws cloudformation describe-stacks --stack-name "$imgbldrstackname" | jq -r '.Stacks[] | .Outputs[] | .OutputValue'

#===============================================================================================================
#Creating configs locally
ac_name=$(aws sts get-caller-identity --query "Account" --output text)
r53_domain_name="${rgurl//http[s]*:\/\//}"
jqcmd='.HostedZones[] | select(.Name=='"\"${r53_domain_name}.\""')|.Id'
hosted_zone=$(aws route53 list-hosted-zones-by-name --dns-name "$r53_domain_name" | jq -r "$jqcmd" | sed -e 's#\/hostedzone\/##')
secretdb_arn=$(aws secretsmanager get-secret-value --secret-id RL-RG-$runid-$env | jq --raw-output .ARN) 
echo "Creating configs locally"
export RG_ENV="$env"
./makeconfigs.sh "$userpool_id" "$userpoolclient_id"  "$bucketname" "$appuser" "$appuserpassword" \
            "$runid" "$rgurl" "$region" "ROLE_NAME" "$ac_name" "$hosted_zone" "$secretdb_arn"
echo "Uploading configs to $bucketname"
aws s3 cp "$localhome"/config.tar.gz s3://"$bucketname"
secpassword=$(aws secretsmanager get-secret-value --secret-id RL-RG-$runid-$env  --version-stage AWSCURRENT | jq --raw-output .SecretString| jq -r ."password")
#===============================================================================================================
#Creating Main stack
echo "Deploying main stack (roles, ec2 instance etc.)"
mainstack_start_time=$SECONDS
mainstackname="RG-PortalStack-$runid"
echo "$mainstackname"
eval "get_stack_status $mainstackname"
stack_status=$?
echo $stack_status
if [ $stack_status -eq 3 ]; then
	exit 1
fi
if [ $stack_status -eq 2 ]; then
	delete_stack "$mainstackname"
	if [ $? -gt 0 ]; then
		echo "Could not delete stack $mainstackname"
		exit 1
	fi
	stack_status=0
fi
if [ $stack_status -eq 0 ]; then
	if ! create_main_stack "$mainstackname"; then
		aws cloudformation describe-stack-events --stack-name "$mainstackname"
		exit 1
	fi
fi
echo "Obtaining MainStack outputs"
portalinstance_id=$(aws cloudformation describe-stack-resources --stack-name "$mainstackname" --logical-resource-id "RGEC2Instance" | jq -r '.StackResources[] | .PhysicalResourceId')
echo "Research Gateway has been successfully deployed. You can access the EC2 instance using $portalinstance_id"
#===============================================================================================================

calculate_duration "MainStack Creation" $mainstack_start_time
calculate_duration "Research Gateway Deployment" $start_time

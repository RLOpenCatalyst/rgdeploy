#!/bin/bash
# Verify that utilities we use in this script are installed on the machine
# this is a test 
echo "Verifying utilities are installed"
apps=(jq aws)
for program in "${apps[@]}"; do
    if ! command -v "$program" > /dev/null 2>&1; then
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
  if ! [ -f $2 ]; then
    echo "Could not find file $2"
    exit 1
  fi
  echo "Reading past run details from $2"
  myinput=`cat $2`
  amiid=$(jq -r '.params.amiid' <<< ${myinput})
  bucketname=$(jq -r '.params.bucketname' <<< ${myinput})
  vpcid=$(jq -r '.params.vpcid' <<< ${myinput})
  subnet1id=$(jq -r '.params.subnet1id' <<< ${myinput})
  subnet2id=$(jq -r '.params.subnet2id' <<< ${myinput})
  subnet3id=$(jq -r '.params.subnet3id' <<< ${myinput})
  keypairname=$(jq -r '.params.keypairname' <<< ${myinput})
  env=$(jq -r '.params.environment' <<< ${myinput})
  rgurl=$(jq -r '.params.rgurl' <<< ${myinput})
  tgarn=$(jq -r '.params.tgarn' <<< ${myinput})

  runid=$(jq -r '.runid' <<< ${myinput})
  appuser=$(jq -r '.appuser' <<< ${myinput})
  appuserpassword=$(jq -r '.appuserpassword' <<< ${myinput})
  adminpassword=$(jq -r '.adminpassword' <<< ${myinput})
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
  echo '       Param 9:  (Optional) The URL at which Research Gateway will be accessed'
  echo '       Param 10:  (Optional) The Target Group to which the Portal EC2 instance should be added'
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
  
  runid=$(date +%s | sha256sum | base64 | tr -dc _a-z-0-9| head -c 4 ; echo)
  appuser='rguser'
  appuserpassword=$(date +%s | sha256sum | base64 | tr -dc _a-z-0-9| head -c 24 ; echo)
  adminpassword=$(date +%s | sha256sum | base64 | tr -dc _a-z-0-9| head -c 24 ; echo)
  cat << EOT >> "$runid.json"
  {
    "runid": "$runid",
    "appuser": "$appuser",
    "appuserpassword": "$appuserpassword",
    "adminpassword": "$adminpassword",
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
aws ec2 describe-images --image-id $amiid >/dev/null 2>&1
if [ $? -gt 0 ]; then
   echo "The AMI $amiid does not exist. Exiting"
   exit 1
fi

if ! [ `echo $bucketname | grep -P '(?=^.{3,63}$)(?!^xn\-\-)(?!.*s3alias$)(?!^(\d+\.)+\d+$)(^(([a-z0-9]|[a-z0-9][a-z0-9\-]*[a-z0-9])\.)*([a-z0-9]|[a-z0-9][a-z0-9\-]*[a-z0-9])$)'` ]; then
  echo "Invalid bucketname passed"
  echo "See https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html"
  exit 1
fi

aws ec2 describe-vpcs --vpc-id $vpcid >/dev/null 2>&1
if [ $? -gt 0 ]; then
   echo "The VPC $vpcid does not exist. Exiting."
   exit 1
fi

aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid --subnet-ids $subnet1id >/dev/null 2>&1
if [ $? -gt 0 ]; then
   echo "The subnet $subnet1id does not belong to $vpcid. Exiting."
   exit 1
fi

aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid --subnet-ids $subnet2id >/dev/null 2>&1
if [ $? -gt 0 ]; then
   echo "The subnet $subnet2id does not belong to $vpcid. Exiting."
   exit 1
fi

aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid --subnet-ids $subnet3id >/dev/null 2>&1
if [ $? -gt 0 ]; then
   echo "The subnet $subnet3id does not belong to $vpcid. Exiting."
   exit 1
fi

aws ec2 describe-key-pairs --key-name $keypairname >/dev/null 2>&1
if [ $? -gt 0 ]; then
   echo "The KeyPair provided is not found. Exiting."
   exit 1
fi

echo $rgurl | grep -i -e '^http'
if [ $? -gt 0 ]; then
   echo "The URL $rgurl must begin with http. Exiting."
   exit 1
fi

aws elbv2 describe-target-groups --target-group-arns $tgarn > /dev/null
if [ $? -gt 0 ]; then
   echo "The Target Group ARN $tgarn does not exists. Exiting."
   exit 1
fi

function calculate_duration() {
   mylabel=$1
   mystarttime=$2
   myelapsedtime=$(( SECONDS - mystarttime ))
   eval "echo $mylabel Elapsed time: $(date -ud "@$myelapsedtime" +'$((%s/3600/24)) %M min %S sec')"
}

localhome=`pwd`
bucketstackname="RG-PortalStack-Bucket-$runid"
userpoolstackname="RG-PortalStack-UserPool-$runid"

start_time=$SECONDS

#Capture User Pool Client ID
userpoolclient_id=$(aws cloudformation describe-stack-resources --stack-name "$userpoolstackname" --logical-resource-id CognitoUserPoolClient | jq -r '.StackResources [] | .PhysicalResourceId')
#Capture User Pool ID
userpool_id=$(aws cloudformation describe-stack-resources --stack-name "$userpoolstackname" --logical-resource-id CognitoUserPool | jq -r '.StackResources [] | .PhysicalResourceId')

docdbstackname="RG-PortalStack-DocDB-$runid"
#Capture DocumentDB Instance Id
docdburl=$(aws cloudformation describe-stacks --stack-name $docdbstackname | jq -r '.Stacks[] | .Outputs[] | select(.OutputKey=="InstanceEndpoint")|.OutputValue')

#Creating Main stack
#update the AMI id in the RGMainStack CFT
echo $amiid | grep -E '^ami-[0-9a-zA-Z]+'
if [ $? -eq 0 ]; then
  echo "Valid AMI Id $amiid passed. Replacing in RGMainStack"
  sed -i -E "s/ami-[0-9a-zA-Z]+/$amiid/" $localhome/rg_main_stack.yml
fi

echo "Deploying main stack (roles, ec2 instance etc.)"
mainstack_start_time=$SECONDS
mainstackname="RG-PortalStack-$runid"
aws cloudformation deploy --template-file $localhome/rg_main_stack.yml \
                          --stack-name "$mainstackname" \
                          --parameter-overrides ClientId="$userpoolclient_id" UserPoolId="$userpool_id" \
                            CFTBucketName="$bucketname" RGUrl="$rgurl" UserPassword="$appuserpassword" AdminPassword="$adminpassword" \
                            VPC="$vpcid" Subnet1="$subnet1id" KeyName1="$keypairname" TGARN="$tgarn" \
                            DocumentDBInstanceURL="$docdburl" Environment="$env" \
                            BaseAccountPolicyName="RG-Portal-Base-Account-Policy-$env-$runid" \
                            RunId="$runid" \
                          --capabilities CAPABILITY_NAMED_IAM
aws cloudformation wait stack-create-complete --stack-name "$mainstackname"
if [ $? -gt 0 ]; then
   echo " $mainstackname Stack Failed to Create "
   exit 1
else
   portalinstance_id=$(aws cloudformation describe-stack-resources --stack-name "$mainstackname" --logical-resource-id "RGEC2Instance" | jq -r '.StackResources[] | .PhysicalResourceId')
   echo "Research Gateway has been successfully deployed. You can access the EC2 instance using $portalinstance_id"
fi
calculate_duration "MainStack Creation" $mainstack_start_time
calculate_duration "Research Gateway Deployment" $start_time

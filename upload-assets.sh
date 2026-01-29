#!/bin/bash

# Verifying required utilities
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

# Check required parameters
if [ $# -lt 2 ]; then
    echo "Usage: $0 <amiid> <bucketname>"
    echo '       Param 1:  The AMI from which the EC2 for Research Gateway should be created'
	echo '       Param 2:  The S3 bucket to create for holding the CFT templates'
    exit 1
fi

amiid=$1
bucketname=$2
region=$(aws configure get region)
[ -z "$region" ] && echo "AWS region not configured. Run 'aws configure'" && exit 1

# Validate AMI ID
echo "Validating AMI ID: $amiid"
if ! aws ec2 describe-images --image-id "$amiid" >/dev/null 2>&1; then
    echo "Error: AMI ID $amiid does not exist."
    exit 1
fi

# Validate bucket name
echo "Validating bucket name: $bucketname"
if ! echo "$bucketname" | grep -q -P '(?=^.{3,63}$)(?!^xn--)(?!.*s3alias$)(?!^(\d+\.)+\d+$)(^(([a-z0-9]|[a-z0-9][a-z0-9\-]*[a-z0-9])\.)*([a-z0-9]|[a-z0-9][a-z0-9\-]*[a-z0-9])$)'; then
    echo "Error: Invalid S3 bucket name."
    exit 1
fi

localhome=$(pwd)
bucketstackname="RG-PortalStack-Bucket-$(date +%s)"

# Create or check bucket
if aws s3api head-bucket --bucket "$bucketname" 2>/dev/null; then
    echo "Bucket $bucketname exists. Proceeding to upload files..."
else
    echo "Bucket $bucketname does not exist. Creating it using CloudFormation..."
    aws cloudformation deploy --template-file rg_deploy_bucket.yml --stack-name "$bucketstackname" \
        --parameter-overrides S3NewBucketName="$bucketname"
    aws cloudformation wait stack-create-complete --stack-name "$bucketstackname"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create S3 bucket via CloudFormation."
        exit 1
    fi
fi

echo "Uploading required files to s3://$bucketname..."

# Upload individual config and script files
aws s3 cp "$localhome"/docker-compose.yml s3://"$bucketname"
aws s3 cp "$localhome"/nginx.conf s3://"$bucketname"
aws s3 cp "$localhome"/updatescripts.sh s3://"$bucketname"
aws s3 cp "$localhome"/makeconfigs-inplace.sh s3://"$bucketname"
aws s3 cp "$localhome"/mainonly.sh s3://"$bucketname"
aws s3 cp "$localhome"/makestudies.sh s3://"$bucketname"

# Sync CFT templates
aws s3 sync "$localhome/cft-templates/" s3://"$bucketname/"

# Upload config files
tar -czf config.tar.gz config/*
tar -tf config.tar.gz
aws s3 cp config.tar.gz s3://"$bucketname"
rm -f config.tar.gz

# Upload scripts
tar -czf scripts.tar.gz scripts/*
tar -tf scripts.tar.gz
aws s3 cp scripts.tar.gz s3://"$bucketname"
rm -f scripts.tar.gz

# Upload bootstrap scripts
aws s3 cp "$localhome"/scripts/bootstrap-scripts/ s3://"$bucketname/bootstrap-scripts" --recursive

# Upload Lambda zip files
cd "$localhome"/lambdas || exit
zip -j pre_verification_custom_message.zip pre_verification_custom_message/index.js
zip -j post_verification_send_message.zip post_verification_send_message/index.js
aws s3 cp pre_verification_custom_message.zip s3://"$bucketname"
aws s3 cp post_verification_send_message.zip s3://"$bucketname"
rm -f pre_verification_custom_message.zip post_verification_send_message.zip

# Upload Image Builder products
cd "$localhome"/products || exit

tar -czf nicedcv.tar.gz Nicedcv/*
aws s3 cp nicedcv.tar.gz s3://"$bucketname/"
rm -f nicedcv.tar.gz


zip -r ec2-winsecure-image.zip ec2-secure-windows/*
aws s3 cp ec2-winsecure-image.zip s3://"$bucketname/"
rm -f ec2-winsecure-image.zip

# Upload dump data
cd "$localhome" || exit
zip dump.zip dump/*
unzip -l dump.zip
aws s3 cp dump.zip s3://"$bucketname/"
rm -f dump.zip
echo "✅ All files uploaded successfully to s3://$bucketname"
exit 0


# ./upload-assets.sh ami-0f78b782bj5ef10a6 single-cft-test-s3
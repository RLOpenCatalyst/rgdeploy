#!/bin/bash

# rgdeploy.sh - Unified deployment script for Research Gateway using a single CloudFormation Template (CFT)
# This script provisions ALB, Cognito, DocumentDB, EC2, and all required resources in a single stack.
# VPC and subnets must be created externally and passed as parameters.

# Usage:
#   ./rgdeploy.sh \
#     --rg-src <RG_SRC> \
#     --ami-id <AMI_ID> \
#     --bucket-name <S3_BUCKET> \
#     --vpc-id <VPC_ID> \
#     --public-subnet-1 <SUBNET_ID> \
#     --public-subnet-2 <SUBNET_ID> \
#     --public-subnet-3 <SUBNET_ID> \
#     --private-subnet-1 <SUBNET_ID> \
#     --private-subnet-2 <SUBNET_ID> \
#     --private-subnet-3 <SUBNET_ID> \
#     --keypair <KEYPAIR_NAME> \
#     --env <ENV> \
#     --rg-url <RG_URL> \
#     --certificate-arn <CERT_ARN> \
#     --region <AWS_REGION> \
#     --hostedzoneid <HOSTED_ZONE_ID> \
#     --base-account-policy-name <BASE_POLICY_NAME> \
#     --admin-email <ADMIN_EMAIL> \
#     [--run-id <RUN_ID>]

set -e

# Parse input arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --rg-src) RG_SRC="$2"; shift; shift ;;
    --ami-id) AMI_ID="$2"; shift; shift ;;
    --bucket-name) BUCKET_NAME="$2"; shift; shift ;;
    --vpc-id) VPC_ID="$2"; shift; shift ;;
    --public-subnet-1) PUBLIC_SUBNET_1="$2"; shift; shift ;;
    --public-subnet-2) PUBLIC_SUBNET_2="$2"; shift; shift ;;
    --public-subnet-3) PUBLIC_SUBNET_3="$2"; shift; shift ;;
    --private-subnet-1) PRIVATE_SUBNET_1="$2"; shift; shift ;;
    --private-subnet-2) PRIVATE_SUBNET_2="$2"; shift; shift ;;
    --private-subnet-3) PRIVATE_SUBNET_3="$2"; shift; shift ;;
    --keypair) KEYPAIR_NAME="$2"; shift; shift ;;
    --env) ENVIRONMENT="$2"; shift; shift ;;
    --rg-url) RG_URL="$2"; shift; shift ;;
    --certificate-arn) CERT_ARN="$2"; shift; shift ;;
    --region) REGION="$2"; shift; shift ;;
    --hostedzoneid) HOSTED_ZONE_ID="$2"; shift; shift ;;
    --base-account-policy-name) BASE_POLICY_NAME="$2"; shift; shift ;;
    --admin-email) ADMIN_EMAIL="$2"; shift; shift ;;
    --run-id) RUN_ID="$2"; shift; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate all required parameters
REQUIRED_VARS=(
  RG_SRC AMI_ID BUCKET_NAME VPC_ID PUBLIC_SUBNET_1 PUBLIC_SUBNET_2 PUBLIC_SUBNET_3
  PRIVATE_SUBNET_1 PRIVATE_SUBNET_2 PRIVATE_SUBNET_3 KEYPAIR_NAME ENVIRONMENT
  RG_URL CERT_ARN REGION HOSTED_ZONE_ID BASE_POLICY_NAME ADMIN_EMAIL
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "Missing required parameter: $var"
    exit 1
  fi
done

# Generate a unique run id if not provided, then use it for the stack name
if [[ -z "$RUN_ID" ]]; then
  RUN_ID=$(date +%s | sha256sum | base64 | tr -dc 'a-z0-9' | head -c 8)
fi
STACK_NAME="RG-PortalStack-ALL-$RUN_ID"

echo "Deploying Research Gateway stack: $STACK_NAME in region: $REGION (RunId: $RUN_ID)"

# Deploy using AWS CloudFormation
aws cloudformation deploy \
  --template-file rgdeploy-cft.yml \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides \
    RgSRC="$RG_SRC" \
    AMIId="$AMI_ID" \
    CFTBucketName="$BUCKET_NAME" \
    VPC="$VPC_ID" \
    PublicSubnet1="$PUBLIC_SUBNET_1" \
    PublicSubnet2="$PUBLIC_SUBNET_2" \
    PublicSubnet3="$PUBLIC_SUBNET_3" \
    PrivateSubnet1="$PRIVATE_SUBNET_1" \
    PrivateSubnet2="$PRIVATE_SUBNET_2" \
    PrivateSubnet3="$PRIVATE_SUBNET_3" \
    KeyPairName="$KEYPAIR_NAME" \
    Environment="$ENVIRONMENT" \
    RGUrl="$RG_URL" \
    CertificateArn="$CERT_ARN" \
    HostedZoneId="$HOSTED_ZONE_ID" \
    BaseAccountPolicyName="$BASE_POLICY_NAME" \
    AdminEmail="$ADMIN_EMAIL" \
    RunId="$RUN_ID"

echo "Deployment initiated. Monitor the progress in AWS CloudFormation Console."

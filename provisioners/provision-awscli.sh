#!/bin/bash -xe

# Update package list
sudo apt-get update -y

# Install prerequisites
sudo apt-get install -y jq unzip curl

# Download AWS CLI v2 installer
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Unzip the AWS CLI installer
unzip awscliv2.zip

# Install AWS CLI
sudo ./aws/install

# Clean up installer files
rm -rf awscliv2.zip aws




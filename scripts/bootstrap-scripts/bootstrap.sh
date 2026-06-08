#!/usr/bin/env bash

# This script bootstraps a workspace instance by preparing S3 study data to be
# mounted via the mount_s3.sh environment script.
# Note that mounting cannot be performed during initial bootstrapping
# because the instance's role will not yet have access to S3 study
# data since the associated resource policies aren't updated until after the
# CFN stack has been completed created.
S3_MOUNTS="$1"
RSTUDIO_USER="$2"


# Get directory in which this script is stored and define URL from which to download goofys
FILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Define a function to determine what type of environment this is (RStudio, or EC2 Linux)
env_type() {
    if [ -d "/var/log/rstudio-server" ]
    then
        printf "rstudio"
    elif [ -f "/usr/bin/nextflow" ]
    then
        printf "nextflow"
    elif [ -d "/home/ec2-user/SageMaker" ]
    then
        printf "sagemaker"    
    else
        printf "ec2-linux"
    fi
}


# Install dependencies
echo "Installing JQ from offline packages"
sudo mv "${FILES_DIR}/offline-packages/jq-1.5-linux64" "/usr/local/bin/jq"
chmod +x "/usr/local/bin/jq"
echo "Finish installing jq"
     
echo "Copying Goofys from offline packages"
cp "${FILES_DIR}/offline-packages/goofys" /usr/local/bin/goofys
chmod +x "/usr/local/bin/goofys"

# Create S3 mount script and config file
echo "Mounting S3"
chmod +x "${FILES_DIR}/bin/mount_s3.sh"
ln -s "${FILES_DIR}/bin/mount_s3.sh" "/usr/local/bin/mount_s3.sh"
# Exit if no S3 mounts were specified
[ -z "$S3_MOUNTS" -o "$S3_MOUNTS" = "[]" ] && exit 0
printf "%s" "$S3_MOUNTS" > "/usr/local/etc/s3-mounts.json"
echo "Finish mounting S3"

OS_VERSION=`cat /etc/os-release | grep VERSION= | sed 's/VERSION="//' | sed 's/"//'`

# Apply updates to environments based on environment type
case "$(env_type)" in
    "ec2-linux") # Add mount script to bash profile
        dnf install -y fuse fuse-common
        printf "\n# Mount S3 study data\nmount_s3.sh\n\n" >> "/home/ec2-user/.bash_profile"
        ;;   
esac

exit 0

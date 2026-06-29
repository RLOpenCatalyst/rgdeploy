#!/usr/bin/env bash

# Prepares S3 / S3 Files study mounts on a workspace instance.
# Mounting runs from ec2-user login (.bash_profile) after IAM policies are active.
S3_MOUNTS="$1"

[ -z "$S3_MOUNTS" -o "$S3_MOUNTS" = "[]" ] && exit 0

FILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
GOOFYS_URL="https://github.com/kahing/goofys/releases/download/v0.24.0/goofys"

env_type() {
    if [ -d "/usr/share/aws/emr" ]
    then
        printf "emr"
    elif [ -d "/home/ec2-user/SageMaker" ]
    then
        printf "sagemaker"
    elif [ -d "/var/log/rstudio-server" ]
    then
        printf "rstudio"
    else
        printf "ec2-linux"
    fi
}

install_jq() {
    if command -v jq >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "${FILES_DIR}/offline-packages/jq-1.5-linux64" ]; then
        sudo mv "${FILES_DIR}/offline-packages/jq-1.5-linux64" "/usr/local/bin/jq"
        sudo chmod +x "/usr/local/bin/jq"
        return 0
    fi
    sudo yum install -y jq
}

install_fuse() {
    if lsmod 2>/dev/null | grep -q '^fuse '; then
        return 0
    fi
    if [ -f "${FILES_DIR}/offline-packages/ec2-linux/fuse-2.9.2-11.amzn2.x86_64.rpm" ]; then
        sudo yum localinstall -y "${FILES_DIR}/offline-packages/ec2-linux/fuse-2.9.2-11.amzn2.x86_64.rpm"
        return 0
    fi
    sudo yum install -y fuse fuse-common 2>/dev/null || sudo yum install -y fuse
}

install_goofys() {
    if command -v goofys >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "${FILES_DIR}/offline-packages/goofys" ]; then
        sudo cp "${FILES_DIR}/offline-packages/goofys" /usr/local/bin/goofys
        sudo chmod +x /usr/local/bin/goofys
        return 0
    fi
    curl -fsSL -o /tmp/goofys "$GOOFYS_URL"
    sudo mv /tmp/goofys /usr/local/bin/goofys
    sudo chmod +x /usr/local/bin/goofys
}

# Create S3 mount script and config file
echo "Mounting S3"
chmod +x "${FILES_DIR}/bin/mount_s3.sh"
ln -s "${FILES_DIR}/bin/mount_s3.sh" "/usr/local/bin/mount_s3.sh"
# Exit if no S3 mounts were specified
[ -z "$S3_MOUNTS" ] || [ "$S3_MOUNTS" = "[]" ] && exit 0
printf "%s" "$S3_MOUNTS" > "/usr/local/etc/s3-mounts.json"
echo "Finish mounting S3"

sudo mkdir -p /usr/local/etc
sudo chmod +x "${FILES_DIR}/bin/mount_s3.sh"
sudo ln -sf "${FILES_DIR}/bin/mount_s3.sh" "/usr/local/bin/mount_s3.sh"
printf "%s" "$S3_MOUNTS" | sudo tee /usr/local/etc/s3-mounts.json >/dev/null
sudo chmod 644 /usr/local/etc/s3-mounts.json

case "$(env_type)" in
    "ec2-linux")
        if ! grep -q 'mount_s3.sh' /home/ec2-user/.bash_profile 2>/dev/null; then
            printf '\n# Mount S3 study data\nmount_s3.sh\n\n' >> /home/ec2-user/.bash_profile
        fi
        chown ec2-user:ec2-user /home/ec2-user/.bash_profile
        ;;
    "rstudio")
        if ! grep -q 'mount_s3.sh' /home/rstudio-user/.bash_profile 2>/dev/null; then
            printf '\n# Mount S3 study data\nmount_s3.sh\n\n' >> /home/rstudio-user/.bash_profile
        fi
        chown rstudio-user:rstudio-user /home/rstudio-user/.bash_profile 2>/dev/null || true
        ;;
esac

exit 0

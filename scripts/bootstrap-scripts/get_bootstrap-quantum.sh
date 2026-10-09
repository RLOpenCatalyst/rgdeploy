#!/usr/bin/env bash

bootstrap_s3_location="$1"
s3_mounts="$2"
rstudio_user="$3"
region="$4"

# Default region if not provided
if [ -z "$region" ]; then
    region="us-east-2"
fi

INSTALL_DIR="/usr/local/share/workspace-environment"

# Create install directory if it doesn't exist
sudo mkdir -p "$INSTALL_DIR"

# Download instance files
sudo aws s3 sync "$bootstrap_s3_location" "$INSTALL_DIR" --region "$region"

# Execute quantum bootstrap script if present
bootstrap_script="$INSTALL_DIR/bootstrap-quantum.sh"

if [ -s "$bootstrap_script" ]; then
    sudo chmod 500 "$bootstrap_script"
    if ! sudo "$bootstrap_script" "$s3_mounts" "$rstudio_user"; then
        printf 'ERROR: bootstrap-quantum.sh failed\n' >&2
        exit 1
    fi
else
    printf 'ERROR: bootstrap-quantum.sh not found under %s\n' "$INSTALL_DIR" >&2
    exit 1
fi

exit 0

#!/bin/bash

# Variables
MINICONDA_INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
MINICONDA_URL="https://repo.anaconda.com/miniconda/$MINICONDA_INSTALLER"
INSTALL_DIR="$HOME/miniconda3"
PROFILE_FILE="$HOME/.bashrc"

# Update system and install prerequisites
sudo yum update -y
sudo yum install -y wget bzip2

# Download Miniconda installer
wget $MINICONDA_URL -O /tmp/$MINICONDA_INSTALLER

# Install Miniconda
bash /tmp/$MINICONDA_INSTALLER -b -p $INSTALL_DIR

# Initialize Conda
eval "$($INSTALL_DIR/bin/conda shell.bash hook)"
conda init

# Clean up
rm /tmp/$MINICONDA_INSTALLER

# Add conda to the PATH
echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> $PROFILE_FILE

# Source the profile file to update the PATH in the current session
source $PROFILE_FILE

# Test the installation
conda --version

echo "Miniconda installation completed successfully."


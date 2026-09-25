#!/bin/bash -xe

export DEBIAN_FRONTEND=noninteractive
export VENV_DIR=/opt/aws/cfn-bootstrap-venv
export HELPER_SCRIPTS_BIN_DIR=/opt/aws/bin

# Update system and install prerequisites
sudo apt update
sudo apt-get install -y tzdata software-properties-common

# Add Python 3.11 PPA and install Python 3.11
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.11 python3.11-venv

# Create a virtual environment with correct permissions
sudo mkdir -p ${VENV_DIR}
sudo python3.11 -m venv ${VENV_DIR}

# Adjust permissions for the virtual environment
sudo chown -R $USER:$USER ${VENV_DIR}
sudo chmod -R 755 ${VENV_DIR}

# Activate the virtual environment
source ${VENV_DIR}/bin/activate

# Upgrade pip inside the virtual environment
pip install --upgrade pip

# Install AWS CFN bootstrap helper scripts
pip install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz

# Create symbolic links for helper scripts
sudo mkdir -p ${HELPER_SCRIPTS_BIN_DIR}
for script in cfn-elect-cmd-leader cfn-get-metadata cfn-hup cfn-init cfn-send-cmd-event cfn-send-cmd-result cfn-signal; do
  if [ -L "${HELPER_SCRIPTS_BIN_DIR}/${script}" ]; then
    sudo rm -f "${HELPER_SCRIPTS_BIN_DIR}/${script}"
  fi
  sudo ln -s ${VENV_DIR}/bin/${script} ${HELPER_SCRIPTS_BIN_DIR}/${script}
done

# Deactivate the virtual environment
deactivate

# Verify installation
echo "Verification:"


echo "AWS CloudFormation Helper Scripts installation completed successfully."

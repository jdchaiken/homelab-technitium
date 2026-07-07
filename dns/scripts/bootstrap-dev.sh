#!/bin/bash
set -e

echo "=== Bootstrapping Developer Machine (Linux) ==="

sudo apt update

echo "Installing Terraform..."
sudo apt install -y wget unzip
wget -O terraform.zip https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform.zip
sudo mv terraform /usr/local/bin/
rm terraform.zip

echo "Installing Ansible..."
sudo apt install -y ansible

echo "Installing Git..."
sudo apt install -y git

echo "Installing SSH client..."
sudo apt install -y openssh-client

echo "Installing Python3 and pip..."
sudo apt install -y python3 python3-pip

echo "Installing dig..."
sudo apt install -y dnsutils

echo "Installing jq and yq..."
sudo apt install -y jq
sudo snap install yq

echo "Installing make..."
sudo apt install -y make

echo ""
echo "Developer machine bootstrap complete."

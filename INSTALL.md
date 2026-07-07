# INSTALL – GitOps DNS Infrastructure
This guide explains how to install and bootstrap the GitOps DNS system.

All manual edits are clearly marked with:

    YOU MUST EDIT THIS SECTION

This ensures anyone can adapt the system to their own environment.

---------------------------------------------------------------------
1. Requirements
---------------------------------------------------------------------

You need:
- A Proxmox cluster
- A Debian 13 cloud-init template VM
- Bitwarden Secrets Manager
- SSH keys for Terraform and Ansible
- Gitea CI/CD
- A Git repo containing this project

---------------------------------------------------------------------
2. Developer Machine Requirements
---------------------------------------------------------------------

Before running any commands in this repository, your workstation must
have the following software installed:

Required Tools
--------------

1. Terraform  
   Required to run the VM lifecycle automation.  
   Version: 1.6.x or later

2. Ansible  
   Required to configure Technitium DNS inside the VM.  
   Version: 2.15.x or later

3. ansible-playbook  
   Must be available on your PATH.

4. Git  
   Required to clone the repository and interact with CI/CD.

5. SSH client  
   Required for Terraform remote-exec and Ansible connections.

6. Python 3  
   Required for Ansible and helper scripts.

7. pip or pipx  
   Required to install Python-based tooling.

8. dig (DNS utilities)  
   Required for DNS validation and troubleshooting.  
   Package: dnsutils (Debian/Ubuntu)

9. jq  
   Required for JSON parsing in scripts.

10. yq  
   Required for YAML parsing in scripts.

11. make  
   Required to run the Makefile automation.

Security Tools (Required)
-------------------------

These tools are used by `make scan-secrets` and `make verify-secrets`.

12. detect-secrets  
    Used to scan the repository for accidental secret leaks.  
    Install via pipx (recommended):

        pipx install detect-secrets

13. git-secrets  
    Used to prevent committing secrets to the repository.  
    Install from GitHub (Ubuntu/Debian):

        sudo apt install git
        sudo git clone https://github.com/awslabs/git-secrets.git /opt/git-secrets
        cd /opt/git-secrets
        sudo make install

    Enable hooks:

        git secrets --install
        git secrets --register-aws

Verification Commands
---------------------

Run these to confirm your environment is ready:

    terraform -version
    ansible --version
    ansible-playbook --version
    git --version
    ssh -V
    python3 --version
    pip --version
    dig -v
    jq --version
    yq --version
    make -v
    detect-secrets --version
    git-secrets --version

If any of these commands fail, install the missing software before
continuing.


---------------------------------------------------------------------
3. Prepare Proxmox
---------------------------------------------------------------------

3.1 Create secrets directory

    mkdir -p /etc/pve/technitium
    chmod 700 /etc/pve/technitium

3.2 Create Bitwarden env file

YOU MUST EDIT THIS SECTION

Create:

    /etc/pve/technitium/bw.env

Contents:

    BW_TOKEN="YOUR_BITWARDEN_SERVICE_ACCOUNT_TOKEN"
    BW_ORGID="YOUR_BITWARDEN_ORG_ID"
    BW_PROJECTID="YOUR_BITWARDEN_PROJECT_ID"

Permissions:

    chmod 600 /etc/pve/technitium/bw.env

---------------------------------------------------------------------
4. Create Cloud-Init Template
---------------------------------------------------------------------

You need a Debian 13 cloud-init template VM.

YOU MUST EDIT THIS SECTION

Record your template VMID:

    cloudinit_template = <YOUR_TEMPLATE_VMID>

Add the file:

    technitium/cloud-init/technitium-user.yaml

as a Proxmox snippet.

---------------------------------------------------------------------
5. Configure Terraform
---------------------------------------------------------------------

Edit:

    technitium/terraform/terraform.tfvars

YOU MUST EDIT THIS SECTION

Set:

    pm_api_url        = "https://your-proxmox.example.com:8006/api2/json"
    pm_user           = "root@pam"
    pm_password       = "CHANGEME"
    pm_node           = "pve01"
    cloudinit_template = 9000

    ssh_pubkey        = "~/.ssh/id_ed25519.pub"
    ssh_privkey       = "~/.ssh/id_ed25519"

    old_vm_id         = 4000

Set IP placeholders:

    TEMP_VM_IP  = "X.X.X.X"
    PROD_VM_IP  = "Y.Y.Y.Y"
    GATEWAY_IP  = "Z.Z.Z.Z"
    UNBOUND_IP  = "A.A.A.A"

---------------------------------------------------------------------
6. Configure TSIG Keys
---------------------------------------------------------------------

TSIG keys authenticate RFC2136 updates from ExternalDNS.

6.1 Create TSIG key in Technitium

1. Open Technitium UI
2. Settings → TSIG Keys → Add
3. Name: externaldns-key
4. Algorithm: hmac-sha256
5. Secret: Generate
6. Save

Copy:
- TSIG Name
- TSIG Algorithm
- TSIG Secret (base64)

6.2 Store TSIG values in Bitwarden

Create three secrets:

    externaldns-tsig-name
    externaldns-tsig-algorithm
    externaldns-tsig-secret

Copy their Secret IDs.

6.3 Update Ansible

Edit:

    technitium/ansible/configure-technitium.yaml

YOU MUST EDIT THIS SECTION

Set:

    tsig_name_secret_id: "YOUR_SECRET_ID"
    tsig_algorithm_secret_id: "YOUR_SECRET_ID"
    tsig_secret_secret_id: "YOUR_SECRET_ID"

---------------------------------------------------------------------
7. Configure DNS Zones
---------------------------------------------------------------------

Edit zone files under:

    dns/zones/

Update SOA serials:

    dns/scripts/update-serials.sh

Validate:

    make validate-zones

---------------------------------------------------------------------
8. CI/CD Validation
---------------------------------------------------------------------

Push changes.

Gitea validates:
- Syntax
- Serial increments
- Drift
- SOA correctness

If CI/CD fails, fix the zone files.

---------------------------------------------------------------------
9. Deploy Technitium
---------------------------------------------------------------------

Run:

    make deploy

Terraform will:
1. Allocate VMID (4000–4999)
2. Create temporary VM at TEMP_VM_IP
3. Apply cloud-init
4. Run Ansible
5. Validate DNS
6. Stop old VM
7. Swap IPs
8. Destroy old VM

Zero downtime.

---------------------------------------------------------------------
10. Validate DNS
---------------------------------------------------------------------

    dig @PROD_VM_IP SOA
    dig @PROD_VM_IP <hostname> A

---------------------------------------------------------------------
11. TSIG Rotation
---------------------------------------------------------------------

See:

    docs/TSIG-ROTATION.md


---------------------------------------------------------------------
12. Developer Machine Setup (OS-Specific)
---------------------------------------------------------------------

Linux (Ubuntu/Debian)
---------------------
Install required tools:

    sudo apt update
    sudo apt install -y ansible git openssh-client python3 python3-pip dnsutils make jq
    sudo snap install yq

Install Terraform:

    wget -O terraform.zip https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
    unzip terraform.zip
    sudo mv terraform /usr/local/bin/
    rm terraform.zip

macOS
-----
Install Homebrew:

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

Install tools:

    brew install terraform ansible git python jq yq make bind

Windows (PowerShell)
--------------------
Install Chocolatey:

    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

Install tools:

    choco install terraform ansible git python jq make

Install dig:

    choco install bind-toolsonly




---------------------------------------------------------------------
13. Summary
---------------------------------------------------------------------

You must manually configure:
- Proxmox Bitwarden env
- Terraform variables
- SSH keys
- IP addresses
- Unbound/BIND resolver IP
- TSIG Secret IDs

Everything else is automated:
- CI/CD
- Terraform
- Cloud-init
- Ansible
- Zero-downtime rebuilds

This INSTALL.md is now ready for public consumption.

---------------------------------------------------------------------
Appendix: Manual-Edit Variable Table
---------------------------------------------------------------------

| Variable | Description | Example Placeholder |
|---------|-------------|---------------------|
| `pm_api_url` | Proxmox API endpoint | `https://proxmox.example.com:8006/api2/json` |
| `pm_user` | Proxmox username | `root@pam` |
| `pm_password` | Proxmox password | `CHANGEME` |
| `pm_node` | Proxmox node name | `pve01` |
| `cloudinit_template` | VMID of cloud-init template | `9000` |
| `ssh_pubkey` | Path to SSH public key | `~/.ssh/id_ed25519.pub` |
| `ssh_privkey` | Path to SSH private key | `~/.ssh/id_ed25519` |
| `old_vm_id` | Current production Technitium VMID | `4000` |
| `TEMP_VM_IP` | Temporary VM IP | `X.X.X.X` |
| `PROD_VM_IP` | Production VM IP | `Y.Y.Y.Y` |
| `GATEWAY_IP` | Gateway IP | `Z.Z.Z.Z` |
| `UNBOUND_IP` | External DNS -OR- Internal recursive resolver IP address (Unbound, BIND, etc.) | `A.A.A.A` |

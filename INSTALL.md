# INSTALL – GitOps DNS Infrastructure
This guide explains how to install and bootstrap the GitOps DNS system.
All manual edits are clearly marked with:

    YOU MUST EDIT THIS SECTION

Follow the steps in order. Do not skip ahead.

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

Install all required tools before using this repository.

Required Tools:
- Terraform 1.6+
- Ansible 2.15+
- ansible-playbook
- Git
- SSH client
- Python 3
- pip or pipx
- dig (dnsutils)
- jq
- yq
- make
- bind9-utils (named-checkzone)

Security Tools:
- detect-secrets
- git-secrets

Install Git hooks:

    make install-hooks
    make verify-hooks

Hooks enforce:
- secret blocking
- commit message rules
- pre-push validation

---------------------------------------------------------------------
3. Prepare Proxmox
---------------------------------------------------------------------

3.1 Create secrets directory:

    mkdir -p /etc/pve/technitium
    chmod 700 /etc/pve/technitium

3.2 Create Bitwarden env file

YOU MUST EDIT THIS SECTION

Create:

    /etc/pve/technitium/bw.env

Contents:

    BW_TOKEN="YOUR_BITWARDEN_SERVICE_ACCOUNT_TOKEN"
    BW_ORGID="YOUR_BITWARDEN_ORG_ID"
    BW_PROJECTID="YOUR_BITWARDARDEN_PROJECT_ID"

Permissions:

    chmod 600 /etc/pve/technitium/bw.env

---------------------------------------------------------------------
4. Create Cloud-Init Template
---------------------------------------------------------------------

You need a Debian 13 cloud-init template VM.

Record your template VMID:

    cloudinit_template = <YOUR_TEMPLATE_VMID>

Add the cloud-init user-data file as a Proxmox snippet:

    technitium/cloud-init/technitium-user.yaml

Snippets must be placed in a storage that supports "Snippets".
Recommended location:

    /var/lib/vz/snippets/

Copy the file:

    cp technitium/cloud-init/technitium-user.yaml /var/lib/vz/snippets/

-or-

Copy with clush: ```clush -l root -g pve -c ./technitium-user.yaml --dest /var/lib/vz/snippets```

Ensure "Snippets" is enabled:
Datacenter → Storage → local → Content → check "Snippets".

Terraform will reference the snippet:

    cicustom = "user=local:snippets/technitium-user.yaml"

Additionally: 

Copy next-vmid.sh to the /opt/infra/technitium folder on the PVE Host
```bash
clush -g pve mkdir -p /opt/infra/technitium
clush -g pve -c technitium/terraform/scripts/next-vmid.sh --dest /opt/infra/technitium
clush -g pve chmod +x /opt/infra/technitium/*

#
pveum aclmod /nodes/pve01 -user root@pam -role Administrator
pveum aclmod /nodes/pve02 -user root@pam -role Administrator
pveum aclmod /nodes/pve03 -user root@pam -role Administrator
pveum aclmod /nodes/pve04 -user root@pam -role Administrator

```

This step is manual only once.

---------------------------------------------------------------------
5. Configure Terraform
---------------------------------------------------------------------

Edit:

    technitium/terraform/terraform.tfvars

YOU MUST EDIT THIS SECTION

Set Proxmox connection:

    pm_api_url        = "https://your-proxmox.example.com:8006/api2/json"
    pm_user           = "root@pam"
    pm_password       = "CHANGEME"
    pm_node           = "pve01"

Set cloud-init template VMID:

    cloudinit_template = 9000

Set SSH keys:

    ssh_pubkey        = "~/.ssh/id_ed25519.pub"
    ssh_privkey       = "~/.ssh/id_ed25519"

Set previous VM ID (for zero-downtime cutover):

    old_vm_id         = 4000

Set IP configuration:

    TEMP_VM_IP        = "X.X.X.X"
    PROD_VM_IP        = "Y.Y.Y.Y"
    GATEWAY_IP        = "Z.Z.Z.Z"
    UNBOUND_IP        = "A.A.A.A"

All values belong inside terraform.tfvars.

---------------------------------------------------------------------
6. Initial Deployment (Creates Technitium)
---------------------------------------------------------------------

Run:

    make deploy

This performs the first full build:

Terraform → Proxmox → Cloud-init → Ansible → Technitium

After this step:
- The VM exists
- Technitium is installed
- You can log in
- You can create TSIG keys

TSIG keys cannot be created before this step.

---------------------------------------------------------------------
7. Configure TSIG Keys
---------------------------------------------------------------------

TSIG keys authenticate RFC2136 updates from ExternalDNS.

7.1 Create TSIG key in Technitium

1. Open Technitium UI
2. Settings → TSIG Keys → Add
3. Name: externaldns-key
4. Algorithm: hmac-sha256
5. Secret: Generate
6. Save

Record:
- TSIG Name
- TSIG Algorithm
- TSIG Secret (base64)

7.2 Store TSIG values in Bitwarden

Create secrets:

    externaldns-tsig-name
    externaldns-tsig-algorithm
    externaldns-tsig-secret

Copy their Secret IDs.

7.3 Update Ansible

Edit:

    technitium/ansible/configure-technitium.yaml

YOU MUST EDIT THIS SECTION

Set:

    tsig_name_secret_id: "YOUR_SECRET_ID"
    tsig_algorithm_secret_id: "YOUR_SECRET_ID"
    tsig_secret_secret_id: "YOUR_SECRET_ID"

Commit and push.

---------------------------------------------------------------------
8. Redeploy with TSIG Keys
---------------------------------------------------------------------

Run:

    make deploy

This rebuilds the VM with TSIG configuration applied.

---------------------------------------------------------------------
9. Configure DNS Zones
---------------------------------------------------------------------

Edit zone files:

    dns/zones/

Update SOA serials:

    dns/scripts/update-serials.sh

Validate:

    make validate-zones

Commit and push.

---------------------------------------------------------------------
10. CI/CD Validation
---------------------------------------------------------------------

Gitea validates:
- Syntax
- Serial increments
- Drift
- SOA correctness
- Secrets
- Git hooks

Fix any failures.

---------------------------------------------------------------------
11. Deploy Technitium (Zero Downtime)
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
12. Validate DNS
---------------------------------------------------------------------

    dig @PROD_VM_IP SOA
    dig @PROD_VM_IP <hostname> A

---------------------------------------------------------------------
13. TSIG Rotation
---------------------------------------------------------------------

See:

    docs/TSIG-ROTATION.md

---------------------------------------------------------------------
14. Summary
---------------------------------------------------------------------

You must manually configure:
- Proxmox Bitwarden env
- Terraform variables
- SSH keys
- IP addresses
- Unbound resolver IP
- TSIG Secret IDs

Everything else is automated:
- CI/CD
- Terraform
- Cloud-init
- Ansible
- Zero-downtime rebuilds

---------------------------------------------------------------------
Appendix: Manual-Edit Variable Table
---------------------------------------------------------------------

| Variable | Description | Example |
|---------|-------------|---------|
| pm_api_url | Proxmox API endpoint | https://proxmox.example.com:8006/api2/json |
| pm_user | Proxmox username | root@pam |
| pm_password | Proxmox password | CHANGEME |
| pm_node | Proxmox node name | pve01 |
| cloudinit_template | VMID of cloud-init template | 9000 |
| ssh_pubkey | SSH public key | ~/.ssh/id_ed25519.pub |
| ssh_privkey | SSH private key | ~/.ssh/id_ed25519 |
| old_vm_id | Current production VMID | 4000 |
| TEMP_VM_IP | Temporary VM IP | X.X.X.X |
| PROD_VM_IP | Production VM IP | Y.Y.Y.Y |
| GATEWAY_IP | Gateway IP | Z.Z.Z.Z |
| UNBOUND_IP | Recursive resolver IP | A.A.A.A |

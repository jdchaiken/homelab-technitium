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
    BW_PROJECTID="YOUR_BITWARDEN_PROJECT_ID"
    TECHNITIUM_ADMIN_PASSWORD="YOUR_NEW_TECHNITIUM_ADMIN_PASSWORD"
    CLOUDFLARE_API_TOKEN="YOUR_CLOUDFLARE_API_TOKEN"

TECHNITIUM_ADMIN_PASSWORD is the password Ansible will set on Technitium's
built-in `admin` account the first time it configures a freshly built VM
(Technitium ships with `admin`/`admin` by default). No manual API key
creation is required — see step 6.

CLOUDFLARE_API_TOKEN (scoped to DNS edit on example.com) is used by
configure-technitium-tls.yaml on every deploy to issue a Let's Encrypt
certificate for ns1.example.com via Cloudflare DNS-01, enabling
DNS-over-TLS/HTTPS/HTTP3/QUIC.

Permissions:

    chmod 600 /etc/pve/technitium/bw.env

---------------------------------------------------------------------
4. Create Cloud-Init Template
---------------------------------------------------------------------

You need a Debian 13 cloud-init template VM.

Record your template VMID:

    cloudinit_template = <YOUR_TEMPLATE_VMID>

Add the cloud-init user-data file as a Proxmox snippet. This file carries a
real SSH public key, so it's not tracked in git -- copy the tracked example
to the gitignored `local/` path and fill in your own key first:

    cp technitium/cloud-init/technitium-user.yaml.example technitium/cloud-init/local/technitium-user.yaml
    # edit local/technitium-user.yaml: replace the ssh_authorized_keys placeholder with your real key

`make deploy` (via its `sync-snippets` step) copies that local file to
Proxmox automatically on every deploy. For a one-off manual copy instead:

Snippets must be placed in a storage that supports "Snippets".
Recommended location:

    /var/lib/vz/snippets/

Copy the file:

    cp technitium/cloud-init/local/technitium-user.yaml /var/lib/vz/snippets/

-or-

Copy with clush: ```clush -l root -g pve -c ./local/technitium-user.yaml --dest /mnt/pve/tank/snippets/```

Ensure "Snippets" is enabled:
Datacenter → Storage → local → Content → check "Snippets".

Terraform will reference the snippet:

    cicustom = "user=local:snippets/technitium-user.yaml"

Additionally: 

Copy next-vmid.sh and current-prod-vmid.sh to the /opt/infra/technitium folder on the PVE Host
```bash
clush -g pve mkdir -p /opt/infra/technitium
clush -g pve -c technitium/terraform/scripts/next-vmid.sh --dest /opt/infra/technitium
clush -g pve -c technitium/terraform/scripts/current-prod-vmid.sh --dest /opt/infra/technitium
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

Copy the example vars file and edit it:

    cp technitium/terraform/terraform.tfvars.example technitium/terraform/local/terraform.tfvars

YOU MUST EDIT THIS SECTION

Set Proxmox connection:

    pm_api_url  = "https://your-proxmox.example.com:8006/api2/json"
    pm_user     = "root@pam"
    pm_password = "CHANGEME"
    pm_node     = "pve01"
    target_node = "pve01"
    datastore   = "tank"

Set the cloud-init image and (optionally) template VMID:

    cloud_init_image_id = "tank:iso/debian-13-generic-amd64.qcow2"
    cloudinit_template   = 9000   # optional, defaults to 9000

Set VM credentials and SSH keys:

    vm_password = "CHANGEME"
    ssh_pubkey  = "ssh-ed25519 AAAA...yourkey"
    ssh_privkey = "~/.ssh/id_ed25519"   # optional, defaults to ~/.ssh/id_ed25519

Set previous VM ID (for zero-downtime cutover):

    old_vm_id = 3000

Set networking:

    temp_vm_ip = "X.X.X.X/24"
    prod_vm_ip = "Y.Y.Y.Y/24"
    gateway_ip = "Z.Z.Z.Z"

All values belong inside `technitium/terraform/local/terraform.tfvars`
(git-ignored — this is where real, per-environment values live;
`terraform.tfvars.example` is the checked-in template).

---------------------------------------------------------------------
6. Deploy Technitium
---------------------------------------------------------------------

Run:

    make deploy

This is the only deploy command you need, first run or every run after.
`make deploy` runs `terraform apply`, which handles the entire flow:

1. Allocates a VMID
2. Creates the VM from the cloud-init template
3. Waits for cloud-init to finish — cloud-init clones this repo onto the
   VM and runs the install + configure Ansible playbooks locally
4. During configuration, Ansible logs into Technitium's default
   `admin`/`admin` account, sets it to TECHNITIUM_ADMIN_PASSWORD, and
   mints a fresh permanent API key — no manual API key creation, ever
5. Ansible generates a TSIG key and imports DNS zones
6. Terraform polls DNS on the temporary IP until Technitium answers
7. Terraform stops the old VM, moves the new VM to the production IP,
   and reboots it
8. Terraform destroys the old VM

Zero downtime, fully automated, no manual steps in the Technitium UI.

---------------------------------------------------------------------
7. Configure DNS Zones
---------------------------------------------------------------------

Edit zone files:

    dns/zones/

Update SOA serials:

    dns/scripts/update-serials.sh

Validate:

    make validate-zones

Commit and push.

---------------------------------------------------------------------
8. CI/CD Validation
---------------------------------------------------------------------

Gitea validates:
- Syntax
- Serial increments
- Drift
- SOA correctness
- Secrets
- Git hooks

See docs/CI-PIPELINE.md for the exact checks and their trigger paths.

Fix any failures.

---------------------------------------------------------------------
9. Redeploy (Zero Downtime)
---------------------------------------------------------------------

Run:

    make deploy

Every deploy builds a brand-new VM and cuts over to it with zero
downtime (see step 6 for the full sequence). There is nothing
version-specific to redo — the same command handles the first deploy,
zone updates, and TSIG rotation.

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
12. Summary
---------------------------------------------------------------------

You must manually configure:
- Proxmox Bitwarden env (including TECHNITIUM_ADMIN_PASSWORD, CLOUDFLARE_API_TOKEN)
- Terraform variables (`technitium/terraform/local/terraform.tfvars`)
- SSH keys
- IP addresses
- Upstream resolver IP (`upstream_resolver_ip` in
  technitium/ansible/configure-technitium.yaml)


Everything else is automated:
- CI/CD
- Terraform
- Cloud-init
- Ansible (including Technitium bootstrap, API key, and TSIG creation)
- Zero-downtime rebuilds

---------------------------------------------------------------------
Appendix: Manual-Edit Variable Table
---------------------------------------------------------------------

| Variable | Description | Example |
|---------|-------------|---------|
| pm_api_url | Proxmox API endpoint | https://proxmox.example.com:8006/api2/json |
| pm_user | Proxmox username | root@pam |
| pm_password | Proxmox password | CHANGEME |
| pm_node | Node used for VMID allocation script | pve01 |
| target_node | Node where the temporary VM will be created | pve01 |
| datastore | Proxmox datastore | tank |
| cloud_init_image_id | Storage path of the cloud-init image | tank:iso/debian-13-generic-amd64.qcow2 |
| cloudinit_template | VMID of the cloud-init template to clone (optional, default 9000) | 9000 |
| temp_vm_ip | Temporary VM IP in CIDR format | 172.16.100.7/24 |
| prod_vm_ip | Production VM IP in CIDR format | 172.16.100.6/24 |
| gateway_ip | Default gateway | 172.16.100.1 |
| vm_password | Root password set via cloud-init | CHANGEME |
| ssh_pubkey | SSH public key | ~/.ssh/id_ed25519.pub |
| ssh_privkey | SSH private key path (optional, default ~/.ssh/id_ed25519) | ~/.ssh/id_ed25519 |
| old_vm_id | Current production VMID | 3000 |
| TECHNITIUM_ADMIN_PASSWORD | Initial Technitium admin password, set in `/etc/pve/technitium/bw.env` | \<a strong password\> |
| CLOUDFLARE_API_TOKEN | Cloudflare token (DNS edit) for Let's Encrypt DNS-01, set in `/etc/pve/technitium/bw.env` | \<a scoped API token\> |
| upstream_resolver_ip | Recursive resolver IP, set in `technitium/ansible/configure-technitium.yaml` vars | 172.16.100.1 |


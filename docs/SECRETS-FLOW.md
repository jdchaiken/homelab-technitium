# Secrets Flow

Proxmox → Cloud-init → Ansible → Technitium → Bitwarden

Proxmox:
    bw.env (BW_TOKEN, BW_ORGID, BW_PROJECTID, TECHNITIUM_ADMIN_PASSWORD)

Cloud-init:
    Copies bw.env into the VM (via qemu-guest-agent file-read), clones
    this repo, and runs the install + configure Ansible playbooks
    locally. Terraform only waits for this to finish
    (`cloud-init status --wait`) — it does not copy bw.env or invoke
    Ansible itself.

Ansible:
    Reads bw.env locally
    Logs into Technitium's default admin/admin account
    Sets the admin password to TECHNITIUM_ADMIN_PASSWORD
    Creates a permanent API key for itself
    Generates a TSIG key via the Technitium API

Technitium:
    Generates the TSIG key and API key values

Bitwarden:
    Ansible writes the generated values back:
        technitium-ansible-api-key
        externaldns-tsig-name
        externaldns-tsig-algorithm
        externaldns-tsig-secret

Ansible never fetches secrets from Bitwarden — it only writes to it.

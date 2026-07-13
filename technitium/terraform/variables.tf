###############################################################################
# Proxmox API
###############################################################################
variable "pm_api_url" {
  type        = string
  description = "Proxmox API endpoint"
}

variable "pm_user" {
  type        = string
  description = "Proxmox username"
}

variable "pm_password" {
  type        = string
  sensitive   = true
  description = "Proxmox password"
}

###############################################################################
# Node & Storage
###############################################################################
variable "pm_node" {
  type        = string
  description = "Node used for VMID allocation script"
}

variable "target_node" {
  type        = string
  description = "Node where the temporary VM will be created"
}

variable "datastore" {
  type        = string
  description = "Proxmox datastore"
}

###############################################################################
# Cloud-init Image
###############################################################################
variable "cloud_init_image_id" {
  type        = string
  description = "Storage path of cloud-init image"
}

variable "cloudinit_template" {
  type        = number
  default     = 9000
  description = "VMID of the Debian cloud-init template to clone"
}

###############################################################################
# Networking
###############################################################################
variable "temp_vm_ip" {
  type        = string
  description = "Temporary VM IP in CIDR format"
}

variable "prod_vm_ip" {
  type        = string
  description = "Production VM IP in CIDR format"
}

variable "prod_vm_name" {
  type        = string
  default     = "ns1"
  description = "Name the VM is renamed to (via `qm set --name`) once cutover completes"
}

variable "gateway_ip" {
  type        = string
  description = "Default gateway"
}

###############################################################################
# Environment Identity (staging support)
###############################################################################
variable "dns_hostname" {
  type        = string
  default     = "ns1.example.com"
  description = <<-EOT
    Hostname this Technitium instance identifies as -- used for its own
    dnsServerDomain setting, the Let's Encrypt cert's domain (tls_domain),
    and the wait_for_dns readiness check. Override for staging (e.g.
    "ns1-staging.example.com") so its TLS cert and DNS self-identity
    don't collide with production's.
  EOT
}

variable "acme_server" {
  type        = string
  default     = ""
  description = <<-EOT
    ACME directory URL passed to certbot's --server flag. Empty (the
    default) means certbot's own built-in production directory -- do not
    set this for production. Staging sets this to Let's Encrypt's staging
    directory (https://acme-staging-v02.api.letsencrypt.org/directory) so
    repeated test rebuilds don't risk production's real rate limits.
  EOT
}

variable "nfs_subdir" {
  type        = string
  default     = "technitium"
  description = <<-EOT
    Subdirectory under the shared NFS mount where the persisted Let's
    Encrypt cert/key/renewal state lives. Override for staging (e.g.
    "technitium-staging") so it doesn't read or overwrite production's
    actual certificate state on the same NFS export.
  EOT
}

variable "is_staging" {
  type        = bool
  default     = false
  description = <<-EOT
    Set true for a staging deploy. Staging has no separate ExternalDNS/
    OPNsense to test DDNS against, so instead of generating and writing a
    new TSIG key to Bitwarden every rebuild (not idempotent -- bws secret
    create makes a new dated entry every time), staging fetches
    production's real, already-generated TSIG key from Bitwarden by name
    and reuses it. Also skips writing technitium-ansible-api-key to
    Bitwarden (nothing reads it back programmatically; staging doesn't
    need its own audit entry there).
  EOT
}

###############################################################################
# VM Credentials
###############################################################################
variable "vm_password" {
  type        = string
  sensitive   = true
  description = "Root password for cloud-init"
}

variable "ssh_pubkey" {
  type        = string
  description = "SSH public key"
}

variable "ssh_privkey" {
  type        = string
  default     = "~/.ssh/id_ed25519"
  description = "Path to the SSH private key used for Terraform provisioners"
}

###############################################################################
# Old VM Cleanup
###############################################################################
variable "old_vm_id" {
  type        = number
  default     = null
  description = <<-EOT
    Manual override for the VMID stopped by cutover just before its IP is
    handed to the new VM. Normally you don't need to set this at all: main.tf
    auto-detects the current production VM (data.external.current_prod_vmid)
    by asking Proxmox which VM in the reserved range actually holds
    prod_vm_ip, so old_vm_id no longer needs to be hand-updated before every
    rebuild. Only set this if you need to force a specific VMID (e.g. the
    auto-detected VM is wrong, or you deliberately want to skip stopping
    anything by some other means). Its actual destruction is handled
    natively by Terraform (technitium_temp has create_before_destroy = true),
    not by this variable. Leave null (the default) for normal operation.
  EOT
}

###############################################################################
# Rebuild Trigger
###############################################################################
variable "rebuild_id" {
  type        = string
  default     = "1"
  description = <<-EOT
    Bump this (e.g. "2", "3", or a date) to force a full rebuild: a new VM
    is built alongside the current one (create_before_destroy), DNS is
    validated on it, cutover stops old_vm_id and moves the new VM to
    prod_vm_ip, and Terraform destroys the old VM natively once that's
    done. Set old_vm_id to the current production VMID in the same apply --
    see its description. Without changing this, `terraform
    apply` is a safe no-op against an already-cutover VM -- vm_id and
    initialization drift are ignored on purpose so routine applies can't
    force-replace or revert a live production VM (see technitium_temp's
    lifecycle block in main.tf).
  EOT
}

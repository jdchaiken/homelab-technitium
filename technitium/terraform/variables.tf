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
    VMID of the current production VM, stopped by cutover just before its
    IP is handed to the new one (required so the two VMs never briefly
    share prod_vm_ip). Its actual destruction is handled natively by
    Terraform (technitium_temp has create_before_destroy = true), not by
    this variable. For a real rebuild, set this to the CURRENT production
    VMID (check `terraform output new_vmid` from the last successful
    deploy) in the SAME apply as bumping rebuild_id. Leave unset (null)
    only when there's no previous VM at all -- e.g. the first build, or a
    rebuild right after `terraform destroy`.
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

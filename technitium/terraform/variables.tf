variable "pm_api_url" {
  description = "Proxmox API URL"
}

variable "pm_user" {
  description = "Proxmox username"
}

variable "pm_password" {
  description = "Proxmox password"
  sensitive   = true
}

variable "pm_node" {
  description = "Proxmox node name"
}

variable "cloudinit_template" {
  description = "Cloud-init template VMID"
}

variable "ssh_pubkey" {
  description = "Path to SSH public key"
}

variable "ssh_privkey" {
  description = "Path to SSH private key"
}

variable "old_vm_id" {
  description = "VMID of the current production Technitium VM"
}

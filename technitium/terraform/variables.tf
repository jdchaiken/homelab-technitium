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

###############################################################################
# Old VM Cleanup
###############################################################################
variable "old_vm_id" {
  type        = number
  description = "VMID of old Technitium VM"
}

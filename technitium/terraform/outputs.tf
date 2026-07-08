output "new_vmid" {
  description = "Allocated VMID for the new Technitium VM"
  value       = local.new_vmid
}

output "temp_vm_name" {
  description = "Name of the temporary Technitium VM"
  value       = proxmox_virtual_environment_vm.technitium_temp.name
}

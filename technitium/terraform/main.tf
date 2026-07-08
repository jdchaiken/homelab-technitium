###############################################################################
# Terraform + Providers
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.111"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.3.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.pm_api_url
  username = var.pm_user
  password = var.pm_password
  insecure = true
}

provider "external" {}
provider "null" {}

###############################################################################
# VMID Allocation (GitOps-safe)
###############################################################################

data "external" "vmid" {
  program = ["ssh", "root@${var.pm_node}", "/opt/infra/technitium/next-vmid.sh"]
}

locals {
  new_vmid = tonumber(data.external.vmid.result.vmid)
}

###############################################################################
# Temporary Technitium VM (Cloud-init)
###############################################################################

resource "proxmox_virtual_environment_vm" "technitium_temp" {
  name      = "technitium-temp"
  node_name = var.target_node
  vm_id     = local.new_vmid

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = 8
    file_id      = var.cloud_init_image_id
    file_format  = "qcow2"
  }

  network_device {
    bridge = "Servers"
    model  = "virtio"
  }

  initialization {
    datastore_id = var.datastore

    user_data_file_id = "tank:snippets/technitium-user.yaml"

    user_account {
      username = "root"
      keys     = [trimspace(file("~/.ssh/id_ed25519.pub"))]
    }

    ip_config {
      ipv4 {
        address = var.temp_vm_ip
        gateway = var.gateway_ip
      }
    }
  }
}

###############################################################################
# Wait for DNS Readiness
###############################################################################

resource "null_resource" "wait_for_dns" {
  depends_on = [proxmox_virtual_environment_vm.technitium_temp]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      VM_IP="$(echo "${var.temp_vm_ip}" | cut -d'/' -f1)"

      echo "Waiting for DNS on $$VM_IP..."
      for i in $(seq 1 60); do
        if dig +short @$$VM_IP technitium.example.com SOA >/dev/null 2>&1; then
          echo "DNS is ready on $$VM_IP"
          exit 0
        fi
        sleep 5
      done

      echo "DNS did not become ready in time"
      exit 1
    EOT
  }
}

###############################################################################
# Cutover: Move New VM to Production IP
###############################################################################

resource "null_resource" "cutover" {
  depends_on = [null_resource.wait_for_dns]

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Stopping old VM ${var.old_vm_id}..."
      qm stop ${var.old_vm_id}

      PROD_IP="$(echo "${var.prod_vm_ip}" | cut -d'/' -f1)"
      CIDR="$(echo "${var.prod_vm_ip}" | cut -d'/' -f2)"

      echo "Setting new VM ${local.new_vmid} to production IP $$PROD_IP/$$CIDR..."
      qm set ${local.new_vmid} --ipconfig0 ip=$$PROD_IP/$$CIDR,gw=${var.gateway_ip}

      echo "Rebooting new VM ${local.new_vmid}..."
      qm reboot ${local.new_vmid}
    EOT
  }
}

###############################################################################
# Destroy Old VM After Successful Cutover
###############################################################################

resource "null_resource" "destroy_old" {
  depends_on = [null_resource.cutover]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Destroying old VM ${var.old_vm_id}..."
      qm destroy ${var.old_vm_id}
    EOT
  }
}

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

###############################################################################
# Current Production VMID Detection (GitOps-safe)
#
# old_vm_id used to be a value operators had to remember to update in
# terraform.tfvars before every single rebuild -- easy to forget, and a
# stale value either fails loudly (VM already gone) or, worse, could target
# the wrong VM. This finds the CURRENT production VM itself, the same way
# next-vmid.sh finds the next free ID: query Proxmox for whichever VM in
# the reserved range actually holds prod_vm_ip right now.
###############################################################################

data "external" "current_prod_vmid" {
  program = ["ssh", "root@${var.pm_node}", "/opt/infra/technitium/current-prod-vmid.sh"]
  query = {
    prod_ip = trimspace(element(split("/", var.prod_vm_ip), 0))
  }
}

locals {
  new_vmid   = tonumber(data.external.vmid.result.vmid)
  bw_env_tmp = "/tmp/technitium-bw-env-${local.new_vmid}"

  # var.old_vm_id is kept only as a manual override escape hatch (e.g.
  # deliberately skipping the stop step); leave it null (the default) to
  # let Terraform detect the current production VM on its own.
  detected_old_vm_id = data.external.current_prod_vmid.result.vmid != "" ? tonumber(data.external.current_prod_vmid.result.vmid) : null
  old_vm_id          = var.old_vm_id != null ? var.old_vm_id : local.detected_old_vm_id
}

###############################################################################
# Rebuild Trigger
# A plain `terraform apply` must be a safe no-op against an already-cutover
# VM (see ignore_changes below), so replacement can't be driven by ordinary
# input drift. Bumping var.rebuild_id is the only thing that forces a real
# rebuild: new temp VM -> DNS check -> cutover -> destroy old_vm_id.
###############################################################################

resource "terraform_data" "rebuild_trigger" {
  input = var.rebuild_id
}

###############################################################################
# Temporary Technitium VM (Cloud-init)
###############################################################################

resource "proxmox_virtual_environment_vm" "technitium_temp" {
  name      = "technitium-temp"
  node_name = var.target_node
  vm_id     = local.new_vmid

  lifecycle {
    replace_triggered_by = [terraform_data.rebuild_trigger]
    # Without this, Terraform's default replace order is destroy-then-
    # create: bumping rebuild_id would destroy the CURRENT production VM
    # first and only then start building its replacement, taking DNS down
    # for the entire ~10+ minute build+configure window instead of just the
    # brief cutover reboot. create_before_destroy builds and fully
    # configures the new VM first; the old instance is only torn down once
    # every dependent (wait_for_dns, cutover) has completed.
    create_before_destroy = true
    ignore_changes = [
      # vm_id comes from data.external.vmid, which re-runs next-vmid.sh on
      # every plan/apply and can return a different value each time (e.g.
      # once the cluster has more VMs). vm_id is ForceNew, so without this
      # a routine `terraform apply` with zero config changes would force-
      # replace this VM just because the allocator's answer moved on.
      # (A deliberate rebuild via replace_triggered_by still picks up
      # whatever next-vmid.sh currently returns, since ignore_changes only
      # suppresses in-place update diffs, not the value used on create.)
      vm_id,
      # The cutover null_resource moves this VM to prod_vm_ip via `qm set`
      # outside of Terraform's own model, so the resource's declared
      # initialization (still pointing at temp_vm_ip) permanently drifts
      # from reality after a successful cutover. Without this, any later
      # apply would "correct" the live production VM back to the temp IP.
      initialization,
      # Cutover also renames the VM from "technitium-temp" to "technitium"
      # via `qm set`, for the same out-of-band reason as initialization above.
      name,
    ]
  }

  # Clone Debian cloud-init template
  clone {
    vm_id = var.cloudinit_template
    full  = false
  }

  operating_system {
    type = "l26"
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
  }

  agent {
    enabled = true
  }

  # Resize/move cloned disk to iSCSI storage "itank"
  disk {
    datastore_id = "itank"
    interface    = "scsi0"
    size         = 8
  }

  network_device {
    bridge = "Servers"
    model  = "virtio"
  }

  initialization {
    datastore_id = "tank"

    user_data_file_id = "tank:snippets/technitium-user.yaml"

    user_account {
      username = "root"
      password = var.vm_password
    }

    ip_config {
      ipv4 {
        address = var.temp_vm_ip
        gateway = var.gateway_ip
      }
    }
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = trimspace(element(split("/", var.temp_vm_ip), 0))
    private_key = file(var.ssh_privkey)
  }

  # Wait for cloud-init (package installs, repo clone) to finish before
  # touching the VM further.
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
  }

  # Deliver the Bitwarden env file from the Proxmox host into the guest.
  # qemu-guest-agent cannot do this: it lets the host read/write files in
  # the guest, not the other way around, so a guest-side "file-read" of a
  # host path silently fails. Terraform itself does not run on pve01 either,
  # so relay the file through a local scratch copy (never stored in state,
  # unlike a data source would be) fetched over SSH and deleted right after
  # use.
  provisioner "local-exec" {
    command = "ssh root@${var.pm_node} cat /etc/pve/technitium/bw.env > ${local.bw_env_tmp} && chmod 600 ${local.bw_env_tmp}"
  }

  provisioner "file" {
    source      = local.bw_env_tmp
    destination = "/root/bw.env"
  }

  provisioner "local-exec" {
    command = "rm -f ${local.bw_env_tmp}"
  }

  # Run the Ansible playbooks only now that bw.env is actually present.
  # (These used to run from cloud-init's runcmd, which starts them before
  # Terraform has a chance to deliver bw.env.)
  provisioner "remote-exec" {
    inline = [
      # Terraform concatenates every inline entry into one combined script
      # and only checks the LAST command's exit status -- without set -e,
      # a failure partway through (e.g. configure-technitium-tls.yaml)
      # would silently continue into the next ansible-playbook call against
      # a broken, incomplete VM instead of stopping there. Invisible until
      # a 4th line was added after what used to be the last command.
      "set -e",
      "chmod 600 /root/bw.env",
      "ansible-playbook /opt/infra/technitium/technitium/ansible/install-technitium.yaml",
      "ansible-playbook /opt/infra/technitium/technitium/ansible/configure-technitium.yaml -e dns_hostname=${var.dns_hostname} -e is_staging=${var.is_staging}",
      "ansible-playbook /opt/infra/technitium/technitium/ansible/configure-technitium-tls.yaml -e dns_hostname=${var.dns_hostname} -e acme_server=${var.acme_server} -e nfs_subdir=${var.nfs_subdir}",
      "ansible-playbook /opt/infra/technitium/technitium/ansible/configure-technitium-apps.yaml -e dns_hostname=${var.dns_hostname}",
    ]
  }
}

###############################################################################
# Wait for DNS Readiness (Technitium authoritative check)
###############################################################################

resource "null_resource" "wait_for_dns" {
  # Re-run whenever technitium_temp is actually replaced (new .id), not on
  # every apply -- see the rebuild trigger note above technitium_temp.
  triggers = {
    vm_instance_id = proxmox_virtual_environment_vm.technitium_temp.id
  }

  depends_on = [proxmox_virtual_environment_vm.technitium_temp]

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      VM_IP="$(echo "${var.temp_vm_ip}" | cut -d'/' -f1)"
      HOSTNAME="${var.dns_hostname}"

      echo "Waiting for DNS on $VM_IP..."

      for i in $(seq 1 360); do
        if dig +short @$VM_IP $HOSTNAME SOA >/dev/null 2>&1; then
          echo "DNS is ready on $VM_IP"
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
  triggers = {
    vm_instance_id = proxmox_virtual_environment_vm.technitium_temp.id
  }

  depends_on = [null_resource.wait_for_dns]

  # Stopping the old VM here (rather than leaving it to Terraform's own
  # create_before_destroy teardown) is required, not optional: that native
  # teardown only happens after every dependent of this resource finishes,
  # which is too late -- the old VM would still be holding prod_vm_ip when
  # this script tries to hand that IP to the new one. There is no separate
  # "destroy old VM" resource anymore: once create_before_destroy is set on
  # technitium_temp, Terraform destroys the old instance natively as the
  # last step of the replace, once this resource (and wait_for_dns) have
  # completed -- a hand-rolled `qm destroy` here would just race it.
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      %{if local.old_vm_id != null~}
      echo "Stopping old VM ${local.old_vm_id}..."
      ssh root@${var.pm_node} "qm stop ${local.old_vm_id}"
      %{else~}
      echo "No previous production VM detected -- nothing to stop (first build or post-destroy rebuild)."
      %{endif~}

      PROD_IP="$(echo "${var.prod_vm_ip}" | cut -d'/' -f1)"
      CIDR="$(echo "${var.prod_vm_ip}" | cut -d'/' -f2)"

      echo "Setting new VM ${local.new_vmid} to production IP $PROD_IP/$CIDR..."
      ssh root@${var.pm_node} "qm set ${local.new_vmid} --ipconfig0 ip=$PROD_IP/$CIDR,gw=${var.gateway_ip}"

      echo "Renaming new VM ${local.new_vmid} to ${var.prod_vm_name}..."
      ssh root@${var.pm_node} "qm set ${local.new_vmid} --name ${var.prod_vm_name}"

      echo "Rebooting new VM ${local.new_vmid}..."
      ssh root@${var.pm_node} "qm reboot ${local.new_vmid}"
    EOT
  }
}

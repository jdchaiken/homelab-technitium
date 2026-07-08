

###############################################################################
# Proxmox Provider Authentication Modes
#
# PASSWORD AUTH (default)
#   provider "proxmox" {
#     endpoint = var.pm_api_url
#     username = var.pm_user
#     password = var.pm_password
#     insecure = true
#   }
#
# TOKEN AUTH (recommended for production)
#   provider "proxmox" {
#     endpoint = var.pm_api_url
#     username = var.pm_user
#     api_token {
#       id     = var.pm_token_id
#       secret = var.pm_token_secret
#     }
#     insecure = true
#   }
#
# Notes:
#   - Token auth bypasses 2FA and is safer for automation.
#   - Token must have VM.* privileges on the target node.
#   - Password auth is simpler but less secure.
###############################################################################



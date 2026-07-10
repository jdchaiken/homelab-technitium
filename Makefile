###############################################################################
# Technitium GitOps Makefile
###############################################################################
.DEFAULT_GOAL := help

ANSIBLE := ansible-playbook
REPO_DIR := /opt/infra/technitium

# Colors
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[0;34m
RESET  := \033[0m

###############################################################################
# Help
###############################################################################
help: ## Show this help menu
		@echo ""
		@echo "$(BLUE)Available Makefile Commands$(RESET)"
		@echo ""
		@grep -E '^[a-zA-Z_-]+:.*?##' Makefile | \
				awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}'
		@echo ""

###############################################################################
# Ansible Operations
###############################################################################
install: ## Run Technitium install playbook
		$(ANSIBLE) technitium/ansible/install-technitium.yaml

configure: ## Run Technitium configure playbook
		$(ANSIBLE) configure-technitium.yaml

rebuild: ## Run full Ansible rebuild (install + configure)
		$(ANSIBLE) install-technitium.yaml
		$(ANSIBLE) configure-technitium.yaml

###############################################################################
# DNS Zone Validation
###############################################################################
validate-zones: ## Validate DNS zone files using named-checkzone
		@echo "Validating zone files..."
		@for z in dns/zones/*.zone; do \
				origin=$$(basename "$$z" .zone); \
				echo "Checking $$z"; \
				named-checkzone "$$origin" "$$z"; \
		done

###############################################################################
# Git Operations
###############################################################################
pull: ## Pull latest infra repo changes
		cd $(REPO_DIR) && git pull --rebase

###############################################################################
# Sync Cloud-Init Snippet
#
# tank is NFS, shared cluster-wide, so one copy from any node reaches all of
# them. This snippet is NOT tracked/synced by Terraform itself -- without
# this step, `deploy` would silently run against whatever stale copy is
# already sitting in Proxmox storage, no matter what's committed to git.
###############################################################################
sync-snippets: ## Sync the cloud-init snippet to Proxmox shared storage
		@PM_NODE=$$(grep '^pm_node' technitium/terraform/local/terraform.tfvars | sed -E 's/.*"([^"]+)".*/\1/'); \
		echo "$(BLUE)Syncing technitium-user.yaml to $$PM_NODE:/mnt/pve/tank/snippets/...$(RESET)"; \
		scp technitium/cloud-init/technitium-user.yaml root@$$PM_NODE:/mnt/pve/tank/snippets/technitium-user.yaml

###############################################################################
# Terraform Deployment (Full GitOps Flow)
###############################################################################
deploy: sync-snippets ## Deploy Technitium DNS via Terraform (VM create, Ansible via Terraform remote-exec, DNS cutover — all handled by Terraform)
		cd technitium/terraform && terraform init && terraform apply -auto-approve -var-file=local/terraform.tfvars

		@echo "$(BLUE)Confirming DNS on production IP...$(RESET)"
		@PROD_IP=$$(grep '^prod_vm_ip' technitium/terraform/local/terraform.tfvars | sed -E 's/.*"([0-9.]+)\/[0-9]+".*/\1/'); \
		for i in $$(seq 1 30); do \
				if dig +short @$$PROD_IP technitium.example.com SOA >/dev/null 2>&1; then \
						echo "$(GREEN)DNS is live on $$PROD_IP$(RESET)"; \
						break; \
				fi; \
				sleep 5; \
				if [ $$i -eq 30 ]; then \
						echo "$(YELLOW)DNS did not confirm on production IP in time$(RESET)"; \
						exit 1; \
				fi; \
		done

		@echo "$(GREEN)Technitium deployment complete.$(RESET)"

###############################################################################
# Developer Environment
###############################################################################
verify-dev: ## Verify developer machine prerequisites
		scripts/verify-dev.sh

install-dev: ## Bootstrap developer machine (Linux)
		scripts/bootstrap-dev.sh

###############################################################################
# Git Hooks
###############################################################################
install-hooks: ## Install git-secrets and repo-specific Git hooks
		@echo "$(BLUE)Installing git-secrets hooks...$(RESET)"
		git secrets --install -f
		git secrets --register-aws

		@echo "$(BLUE)Installing custom Git hooks...$(RESET)"
		install -m 755 hooks/pre-commit .git/hooks/pre-commit
		install -m 755 hooks/pre-push .git/hooks/pre-push
		install -m 755 hooks/commit-msg .git/hooks/commit-msg

		@echo "$(GREEN)Git hooks installed successfully.$(RESET)"

test-hooks: ## Test that Git hooks are functioning correctly
		@echo "$(BLUE)Testing hooks with fake AWS key...$(RESET)"
		echo "AKIA1234567890FAKEKEY" > hooks/test.txt
		git add hooks/test.txt || true

		@if git commit -m "hook test"; then \
				echo "$(YELLOW)ERROR: Hooks did NOT block the commit.$(RESET)"; \
				exit 1; \
		else \
				echo "$(GREEN)SUCCESS: Hooks blocked the commit.$(RESET)"; \
		fi

		rm -f hooks/test.txt
		git reset --hard HEAD

verify-hooks: ## Verify installed Git hooks match repository versions
		hooks/verify-hooks.sh

###############################################################################
# Secret Scanning
###############################################################################
scan-secrets: ## Run detect-secrets and git-secrets scans
		detect-secrets scan > .detect-secrets.json
		git secrets --scan

verify-secrets: ## Validate secrets baseline
		detect-secrets-hook --baseline .detect-secrets.json
		git secrets --scan

###############################################################################
# Linting
###############################################################################
lint: ## Run all linters (shell, YAML, Terraform)
		@echo "$(BLUE)Linting shell scripts...$(RESET)"
		-@shellcheck dns/scripts/*.sh
		-@shellcheck technitium/terraform/scripts/*.sh

		@echo "$(BLUE)Linting YAML...$(RESET)"
		-@yamllint technitium/ansible
		-@yamllint technitium/cloud-init

		@echo "$(BLUE)Linting Terraform...$(RESET)"
		@cd technitium/terraform && terraform fmt -check -no-color && terraform validate -no-color

		@echo "$(GREEN)Lint complete.$(RESET)"


bootstrap:
		ansible-playbook -i ansible/inventory/technitium.ini ansible/technitium-bootstrap.yaml

###############################################################################
# Phony Targets
###############################################################################
.PHONY: install configure rebuild validate-zones pull sync-snippets deploy \
		verify-dev install-dev scan-secrets verify-secrets lint help \
		install-hooks test-hooks verify-hooks

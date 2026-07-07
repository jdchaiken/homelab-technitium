# CI Pipeline – Zone Validation and Security Enforcement

This document describes the CI/CD pipeline used to validate DNS zone files,
enforce Git hook integrity, and prevent secrets from entering the repository.

The pipeline runs on every push and pull request that modifies DNS zones,
DNS scripts, Git hooks, or the Makefile.

---

# 1. What the Pipeline Enforces

The CI pipeline performs the following checks:

1. Git hook integrity
2. detect-secrets baseline validation
3. git-secrets scanning
4. DNS zone syntax validation (named-checkzone)
5. Strict zone diff validation
6. Terraform validation (optional)
7. Artifact upload for zone diffs

These checks ensure that all DNS changes are safe, validated, and compliant
with the GitOps workflow.

---

# 2. Trigger Paths

The pipeline runs when any of the following paths change:

    infra/technitium/dns/zones/**
    infra/technitium/dns/scripts/**
    infra/technitium/hooks/**
    infra/technitium/Makefile

---

# 3. CI Workflow Definition

Below is the workflow used in Gitea Actions:

    name: Zone File Validation (Combined)

    on:
      push:
        paths:
          - "infra/technitium/dns/zones/**"
          - "infra/technitium/dns/scripts/**"
          - "infra/technitium/hooks/**"
          - "infra/technitium/Makefile"
      pull_request:
        paths:
          - "infra/technitium/dns/zones/**"
          - "infra/technitium/dns/scripts/**"
          - "infra/technitium/hooks/**"
          - "infra/technitium/Makefile"

    jobs:
      zone-check:
        runs-on: ubuntu-latest

        steps:
          - name: Checkout repository
            uses: actions/checkout@v3
            with:
              fetch-depth: 0

          - name: Install system dependencies
            run: |
              sudo apt-get update
              sudo apt-get install -y bind9-utils shellcheck yamllint terraform

          - name: Verify Git hook integrity
            run: |
              chmod +x infra/technitium/hooks/verify-hooks.sh
              infra/technitium/hooks/verify-hooks.sh

          - name: Run detect-secrets baseline validation
            run: |
              pip install detect-secrets
              detect-secrets-hook --baseline infra/technitium/.detect-secrets.json

          - name: Run git-secrets scan
            run: |
              git secrets --scan

          - name: Run syntax validation (make validate-zones)
            run: |
              cd infra/technitium
              make validate-zones

          - name: Run strict zone diff checker
            run: |
              cd infra/technitium
              bash dns/scripts/zone-diff-strict.sh

          - name: Save diff output
            id: diff
            run: |
              cd infra/technitium
              bash dns/scripts/zone-diff.sh > diff_output.txt || true

          - name: Upload diff as artifact
            uses: actions/upload-artifact@v3
            with:
              name: zone-diff
              path: infra/technitium/diff_output.txt

          - name: Validate Terraform (optional)
            run: |
              cd infra/technitium/technitium/terraform
              terraform init -input=false
              terraform validate

---

# 4. Troubleshooting

If the pipeline fails:

1. Run make validate-zones locally
2. Run dns/scripts/zone-diff-strict.sh locally
3. Run make verify-hooks
4. Run detect-secrets scan
5. Run git secrets --scan
6. Validate Terraform manually

---

# 5. Summary

The CI pipeline ensures:

- DNS changes are validated
- Secrets cannot be committed
- Git hooks remain enforced
- Terraform remains valid
- Operators and developers follow the GitOps workflow

This pipeline is required for all DNS changes.

```mermaid
flowchart TD

A[make deploy] --> B[Fresh VM built via Terraform + cloud-init]
B --> C[configure-technitium.yaml generates externaldns-key TSIG]
C --> D[Ansible writes TSIG name/algorithm/secret to Bitwarden]
D --> E[Point ExternalDNS at refreshed Bitwarden values]

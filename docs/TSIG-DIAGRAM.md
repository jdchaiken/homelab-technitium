```mermaid
flowchart TD

A[Create new TSIG in Technitium] --> B[Store in Bitwarden]
B --> C[Update Secret IDs in repo]
C --> D[Commit + push]
D --> E[CI validates]
E --> F[make deploy]
F --> G[Technitium reloads zones]

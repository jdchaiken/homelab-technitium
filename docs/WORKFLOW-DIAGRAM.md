# Developer Workflow Diagram (Mermaid)

```mermaid
flowchart TD

A[Edit zone file] --> B[Run update-serials.sh]
B --> C[make validate-zones]
C --> D[Commit]
D --> E[Git hooks enforce safety]
E --> F[Push]
F --> G[CI pipeline validates zones]
G --> H[make deploy]
H --> I[Zero-downtime rebuild]

flowchart TD

A[Push or PR] --> B[Checkout]
B --> C[Verify Git hooks]
C --> D[detect-secrets]
D --> E[git-secrets]
E --> F[Zone syntax validation]
F --> G[Strict diff validation]
G --> H[Terraform validate]
H --> I[Artifact upload]
I --> J[Pipeline pass or fail]

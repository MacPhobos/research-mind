# Scripts

Utility scripts for the research-mind project.

## Available Scripts

| Script                          | Purpose                                                  |
| ------------------------------- | -------------------------------------------------------- |
| `verify-install.sh`             | Verify installation is complete and services are healthy |
| `docker-entrypoint-combined.sh` | Entrypoint for combined Docker container                 |

## Usage

All scripts should be run from the repository root:

```bash
# Verify your installation
./scripts/verify-install.sh

# The entrypoint script is used internally by Docker
# and should not be run manually
```

## Adding New Scripts

When adding new scripts:

1. Make them executable: `chmod +x scripts/your-script.sh`
2. Add a row to the table above
3. Include a shebang (`#!/bin/bash`) and set `-e` for error handling

# Copilot instructions for this repository

## Build, test, and lint commands

This repository currently has no application build system or unit-test runner. Validation is centered on Bicep and CI guardrails.

| Purpose | Command |
|---|---|
| Lint one Bicep file | `az bicep lint --file <path-to-file.bicep> --diagnostics-format sarif` |
| Validate (compile) one Bicep file | `az bicep build --file <path-to-file.bicep>` |
| Validate one Bicep parameter file | `az bicep build-params --file <path-to-file.bicepparam>` |
| Lint all Bicep files (PowerShell) | `Get-ChildItem -Recurse -Filter *.bicep | ForEach-Object { az bicep lint --file $_.FullName --diagnostics-format sarif }` |
| Validate all Bicep files (PowerShell) | `Get-ChildItem -Recurse -Filter *.bicep | ForEach-Object { az bicep build --file $_.FullName }` |
| Validate all Bicep param files (PowerShell) | `Get-ChildItem -Recurse -Filter *.bicepparam | ForEach-Object { az bicep build-params --file $_.FullName }` |

## High-level architecture

This repository is an ops bootstrap-and-guardrails repo for an AI-driven FinOps/SecOps setup, not an application codebase.

1. **Bootstrap automation (`bootstrap/`)**: two equivalent scripts (`Bootstrap.ps1` for Windows, `bootstrap.sh` for Bash) create a GitHub repository, create Azure resources (resource group + user-assigned managed identity), configure GitHub OIDC federated credentials, set required GitHub secrets (`AZURE_CLIENT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`), and assign subscription Reader role to the identity.
2. **CI policy guardrails (`.github/workflows/`)**:
   - `bicep-lint.yml` enforces Bicep quality with `az bicep lint`, `az bicep build`, and `az bicep build-params`.
   - `secret-scan.yml` runs gitleaks on every push/PR.
   - `validate-branch-name` enforces branch naming rules on pull requests.

## Key conventions specific to this repo

- **Branch naming is enforced in CI**: branch names must match `^(feature|bugfix|hotfix)/[a-zA-Z0-9._-]+$`.
- **Azure resource naming pattern is fixed in bootstrap scripts**:
  - Managed identity: `id-<repo>-prd-<location>-001`
  - Resource group: `rg-<repo>-prd-<location>-001`
- **OIDC subject format is explicitly constructed from GitHub repo metadata** for the `main` branch and used for federated credential creation.
- **Bootstrap scripts fail fast on missing dependencies** (`gh`, `az`, and `jq` for Bash).

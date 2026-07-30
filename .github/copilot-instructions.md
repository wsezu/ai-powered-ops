# Copilot instructions for this repository

## Documentation

Detailed docs live in `docs/`:
- [`docs/bootstrap.md`](../docs/bootstrap.md) — optional one-time setup of GitHub repo + Azure OIDC infrastructure
- [`docs/infra.md`](../docs/infra.md) — Bicep infrastructure layout, types, variables, modules, and deployment commands
- [`docs/workflows.md`](../docs/workflows.md) — all six CI/CD workflows: triggers, steps, secrets, and conventions

## Build, test, and lint commands

There is no application build system or unit-test runner. Validation is Bicep linting and Python linting.

**Bicep:**

| Purpose | Command |
|---|---|
| Lint one Bicep file | `az bicep lint --file <path-to-file.bicep> --diagnostics-format sarif` |
| Validate (compile) one Bicep file | `az bicep build --file <path-to-file.bicep>` |
| Validate one Bicep parameter file | `az bicep build-params --file <path-to-file.bicepparam>` |
| Lint all Bicep files (PowerShell) | `Get-ChildItem -Recurse -Filter *.bicep \| ForEach-Object { az bicep lint --file $_.FullName --diagnostics-format sarif }` |
| Validate all Bicep files (PowerShell) | `Get-ChildItem -Recurse -Filter *.bicep \| ForEach-Object { az bicep build --file $_.FullName }` |
| Validate all Bicep param files (PowerShell) | `Get-ChildItem -Recurse -Filter *.bicepparam \| ForEach-Object { az bicep build-params --file $_.FullName }` |

**Python:**

| Purpose | Command |
|---|---|
| Lint all Python files | `ruff check .` |
| Security scan Python files | `bandit -r . -x .venv,venv,.git,__pycache__` |
| Audit Python dependencies | `pip-audit` |

## High-level architecture

This repository is an ops bootstrap-and-guardrails repo for an AI-driven FinOps/SecOps setup, not an application codebase.

1. **Bootstrap automation (`bootstrap/`)**: two equivalent scripts (`Bootstrap.ps1` for Windows, `bootstrap.sh` for Bash) perform a one-time setup — create a GitHub repository, Azure resource group and user-assigned managed identity, GitHub OIDC federated credentials, required GitHub secrets (`AZURE_CLIENT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`), and subscription Reader role assignment. See `docs/bootstrap.md`.

2. **Infrastructure as code (`infra/`)**: subscription-scoped Bicep templates that deploy Azure resources. Entry point is `infra/main.bicep` with `infra/main.bicepparam` for configuration. Shared types are in `helpers/types.bicep`, shared constants (regions, role definition GUIDs) in `helpers/variables.bicep`. Modules source from the Azure Verified Modules public registry (`br/public:avm/...`) with pinned versions. See `docs/infra.md`.

3. **CI/CD workflows (`.github/workflows/`)** — six workflows:
   - `bicep-lint.yml` — lints and compiles all Bicep files on push/PR; requires OIDC Azure login for public registry module resolution.
   - `deploy-azure-resources.yml` — deploys `infra/main.bicep` to Azure on push to `main` when `infra/**` changes.
   - `python-lint.yml` — runs Ruff on all Python files.
   - `security-scan.yml` — runs Bandit (static analysis) and pip-audit (CVE check) on all Python files.
   - `secret-scan.yml` — runs Gitleaks on every push and PR across full commit history.
   - `validate-branch-name.yml` — enforces branch naming convention on PRs.

   See `docs/workflows.md`.

## Key conventions specific to this repo

- **Branch naming is enforced in CI**: branch names must match `^(feature|bugfix|hotfix)/[a-zA-Z0-9._-]+$`.
- **Bootstrap resource naming pattern**: `id-<repo>-prd-<location>-001` (identity), `rg-<repo>-prd-<location>-001` (resource group).
- **Infra resource naming pattern**: `<type>-<shortName>-<environment>-<regionShortName>-<instance>`, e.g. `rg-aiops-prd-swc-001`.
- **Region references in Bicep**: always use `v.regions.<key>.location` from `helpers/variables.bicep` — never hardcode region strings.
- **Role definition IDs**: always use `v.roleDefinitionId.<key>` from `helpers/variables.bicep` — never hardcode GUIDs.
- **AVM modules**: resource modules are sourced from `br/public:avm/...` with pinned versions.
- **Optional Bicep parameters**: use the safe-access operator (`resource.?field`) when passing optional fields to AVM modules.
- **All Azure workflows use OIDC**: any workflow that calls Azure must include `id-token: write` permission and the `azure/login@v2` OIDC step.
- **Bootstrap scripts fail fast on missing dependencies** (`gh`, `az`, and `jq` for Bash).

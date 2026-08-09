# Copilot instructions for this repository

## Documentation

Detailed docs live in `docs/`:
- [`docs/bootstrap.md`](../docs/bootstrap.md) — optional one-time setup of GitHub repo + Azure OIDC infrastructure
- [`docs/infra.md`](../docs/infra.md) — Bicep infrastructure layout, types, variables, modules, and deployment commands
- [`docs/workflows.md`](../docs/workflows.md) — all eight CI/CD workflows: triggers, steps, variables, and conventions
- [`docs/function-app.md`](../docs/function-app.md) — Python Function App functions, endpoints, anomaly detection logic, and configuration
- [`docs/agents.md`](../docs/agents.md) — Foundry agent assets, setup script, and tool surface

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

This repository is an ops bootstrap-and-guardrails repo for an AI-driven FinOps/SecOps architecture advisor on Azure, combining infrastructure-as-code, a Python anomaly-detection Function App, and CI/CD guardrails. It is still a work in progress: bootstrap and infra are done, agents are in progress, and a chat interface is planned.

1. **Bootstrap automation (`bootstrap/`)**: two equivalent scripts (`Bootstrap.ps1` for Windows, `bootstrap.sh` for Bash) perform a one-time setup — create a GitHub repository, Azure resource group and user-assigned managed identity, **two** GitHub OIDC federated credentials (one for `main` branch deployments, one for pull request linting), required GitHub repository variables (`AZURE_CLIENT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`), and subscription Reader role assignment. See `docs/bootstrap.md`.

2. **Infrastructure as code (`infra/`)**: subscription-scoped Bicep templates that deploy Azure resources. Entry point is `infra/main.bicep` with `infra/main.bicepparam` for configuration. It deploys resource groups via AVM, then orchestrates three resource-group-scoped modules: `supporting_resources.bicep` (Log Analytics, Application Insights, user-assigned identity, hardened storage account, VNet/NSG), `function-app_resources.bicep` (Linux App Service plan + Python 3.12 Function App with managed identity storage auth and VNet integration), and `foundry_resources.bicep` (AI Foundry account and model deployments). A fourth module, `event_grids.bicep`, wires blob-created events from storage to the Function App and is deployed separately by `deploy-event-grids.yml`. Shared types are in `helpers/types.bicep`, shared constants (regions, role definition GUIDs) in `helpers/variables.bicep`. See `docs/infra.md`.

3. **Python Function App (`src/python/`)**: Azure Functions v2 app deployed to `func-aiops-prd-weu-001`. Four functions:
   - `BlobCreatedEventGridFunction` — Event Grid trigger; reads FOCUS-format Parquet blobs, aggregates daily spend, detects anomalies (z-score, IQR, day-over-day), merges updates per signal key, writes `latest.json` and daily history to the `normalized` container with ETag-conditional retries.
   - `GetLatestCostAnomalies` — HTTP GET; returns the current anomaly snapshot.
   - `GetCostAnomalyHistory` — HTTP GET; returns flagged signals with persistence streak counts across historical snapshots.
   - `StorageHealthCheck` — HTTP GET; lists blobs in a container for diagnostics.
   Supporting logic in `anomaly_detection.py` (`signal_key`, `is_latest_flagged`, `compute_persistence`). See `docs/function-app.md`.

4. **CI/CD workflows (`.github/workflows/`)** — eight workflows:
   - `validate-branch-name.yml` — enforces branch naming convention on PRs.
   - `bicep-lint.yml` — lints and compiles Bicep files on PRs to `main` targeting `infra/**`; requires OIDC Azure login for public AVM registry module resolution.
   - `deploy-azure-resources.yml` — deploys `infra/main.bicep` to Azure on push to `main` when `infra/**` changes.
   - `deploy-event-grids.yml` — deploys Event Grid wiring on push to `main` when `infra/modules/event_grids.bicep` changes; looks up Function App and storage account, then applies event subscriptions.
   - `deploy-function-app-apps.yml` — deploys `src/python/` to the Function App on push to `main` when `src/python/**` changes; uses `Azure/functions-action@v1` with `sku: flexconsumption` and `remote-build: true`.
   - `python-lint.yml` — runs Ruff on Python files on PRs to `main`.
   - `security-scan.yml` — runs Bandit (static analysis) and pip-audit (CVE check) on all Python files.
   - `secret-scan.yml` — runs Gitleaks on every push and PR across full commit history.

   See `docs/workflows.md`.

## Key conventions specific to this repo

- **Branch naming is enforced in CI**: branch names must match `^(feature|bugfix|designfix|hotfix)\/[a-zA-Z0-9._-]+$`.
- **Bootstrap resource naming pattern**: `id-<repo>-prd-<location>-001` (identity), `rg-<repo>-prd-<location>-001` (resource group).
- **Infra resource naming pattern**: `<type>-<shortName>-<environment>-<regionShortName>-<instance>`, e.g. `rg-aiops-prd-weu-001`. Storage accounts use `stv2<shortName><environment><regionShortName>001` (no hyphens, max 24 chars).
- **Region references in Bicep**: always use `v.regions.<key>.location` from `helpers/variables.bicep` — never hardcode region strings.
- **Role definition IDs**: always use `v.roleDefinitionId.<key>` from `helpers/variables.bicep` — never hardcode GUIDs.
- **AVM modules**: resource modules are sourced from `br/public:avm/...` with pinned versions.
- **Optional Bicep parameters**: use the safe-access operator (`resource.?field`) when passing optional fields to AVM modules.
- **All Azure workflows use OIDC**: any workflow that calls Azure must include `id-token: write` permission and the `azure/login@v2` OIDC step.
- **Bootstrap scripts fail fast on missing dependencies** (`gh`, `az`, and `jq` for Bash).

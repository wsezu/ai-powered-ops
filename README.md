# ai-powered-ops

AI-driven FinOps and SecOps architecture advisor infrastructure on Azure.

## Repository scope

This repository contains Infrastructure as Code (Bicep, `infra\`) and a Python Azure Functions application (`python\`).

## What gets deployed

The deployment entrypoint is `infra\main.bicep` (subscription scope). It orchestrates:

1. Resource group creation using Azure Verified Modules (AVM).
2. Azure AI Foundry/Cognitive Services account creation (including model deployments).
3. Foundry project creation under the Foundry account.
4. Azure Function App infrastructure (Linux Flex Consumption) with managed identity and storage-backed package deployment.
5. Event Grid wiring from Storage BlobCreated events (`focus-exports` container) to the Function endpoint.

### Python function app

`python\function_app.py` contains `BlobCreatedEventGridFunction` (Event Grid trigger). When a new blob lands in `focus-exports` it:

1. Reads the FOCUS-format Parquet cost export.
2. Aggregates daily spend grouped by `SubAccountId`, `SubAccountName`, and `ServiceName`.
3. Runs anomaly detection per dimension/metric using z-score, IQR, and day-over-day thresholds.
4. Writes a JSON result to the `normalized` container as `latest.json` and `history/<timestamp>.json`.

### Current default environment

`infra\main.bicepparam` defines the default environment:

- Environment: `dev`
- Region: `swedencentral` (`swc`)
- Project short name: `aiops`
- Foundry model deployments:
  - `gpt-5.1` (`DataZoneStandard`, capacity `10`)
  - `gpt-5-mini` (`DataZoneStandard`, capacity `20`)

## Repository structure

- `infra\main.bicep` - subscription-scope orchestration template
- `infra\main.bicepparam` - default parameter set/environment manifest
- `infra\modules\foundry-project.bicep` - Foundry project child resource deployment
- `infra\modules\function-app.bicep` - Function App + plan + storage + lifecycle policy + identity + role assignment + Event Grid subscription
- `infra\helpers\types.bicep` - typed parameter contracts used by `main.bicep`
- `infra\helpers\variables.bicep` - shared region metadata and role definition IDs
- `python\function_app.py` - Azure Function source (`BlobCreatedEventGridFunction`)
- `python\requirements.txt` - Python runtime dependencies (`azure-functions`, `azure-storage-blob`, `pandas`, `pyarrow`, etc.)
- `python\host.json` - Azure Functions host configuration
- `.github\workflows\validate-branch-name.yml` - PR branch name validation
- `.github\workflows\lint.yml` - Ruff (Python) + Bicep lint on every PR and `main` push
- `.github\workflows\security-scan.yml` - Bandit + pip-audit on every PR and `main` push
- `.github\workflows\secret-scan.yml` - Gitleaks secret scanning on every PR and `main` push
- `.github\workflows\codeql.yml` - CodeQL Python analysis on PRs targeting `main` and pushes to `main`
- `.github\copilot-instructions.md` - Copilot repository instructions for future sessions

## Prerequisites

- Azure subscription with permission to deploy at subscription and resource-group scopes.
- Azure CLI with Bicep support.
- Logged in context:

```powershell
az login
az account set --subscription <subscription-id>
```

## Validate and preview changes

```powershell
az deployment sub validate --location swedencentral --template-file infra\main.bicep --parameters infra\main.bicepparam
az deployment sub what-if --location swedencentral --template-file infra\main.bicep --parameters infra\main.bicepparam
```

## Deploy

```powershell
az deployment sub create --location swedencentral --template-file infra\main.bicep --parameters infra\main.bicepparam
```

## Naming and conventions

Resource naming follows the `*-<shortName>-<environment>-<regionShort>-<index>` convention (for example `rg-aiops-dev-swc-001`), and helper logic in modules depends on this segment structure.

Region short names and shared role IDs are centralized in `infra\helpers\variables.bicep`.

## Pull request branch policy

PR branch names are validated in CI and must match:

`^(feature|bug|hotfix|release|develop|iac)\/[a-zA-Z0-9._-]+$`

Examples:

- `feature/PROJ-123-login-page`
- `bug/PROJ-456-nullpointer`
- `iac/terraform-state-hardening`

# Copilot instructions for `ai-powered-ops`

## Build, validate, and deployment commands

This repository contains Bicep infrastructure-as-code (`infra\`) and a Python Azure Functions application (`python\`). Use these commands to validate and lint:

```powershell
# Validate the full subscription-scope deployment
az deployment sub validate --location swedencentral --template-file infra\main.bicep --parameters infra\main.bicepparam

# Preview the full change set
az deployment sub what-if --location swedencentral --template-file infra\main.bicep --parameters infra\main.bicepparam
```

Module-level validation (single-unit equivalent):

```powershell
# Validate only the Foundry project module (resource-group scope)
az deployment group validate --resource-group <resource-group-name> --template-file infra\modules\foundry-project.bicep --parameters location=swedencentral foundryAccountName=<account-name> foundryProjectName=<project-name>

# Validate only the Function App module (resource-group scope)
az deployment group validate --resource-group <resource-group-name> --template-file infra\modules\function-app.bicep --parameters name=func-aiops-dev-swc-001
```

Python linting (Ruff — runs in CI on every PR and `main` push):

```powershell
ruff check python\
```

## High-level architecture

- `infra\main.bicep` is the orchestration entrypoint at **subscription scope**. It deploys:
  1. Resource groups via AVM (`br/public:avm/res/resources/resource-group`).
  2. Azure AI Foundry/Cognitive Services accounts via AVM (`br/public:avm/res/cognitive-services/account`) with model deployments.
  3. Foundry project children (`infra\modules\foundry-project.bicep`).
  4. Function App infrastructure (`infra\modules\function-app.bicep`).

- `infra\main.bicepparam` is the environment manifest. It defines:
  - Project metadata and tags.
  - Region/environment naming inputs.
  - Foundry model deployments (currently `gpt-5.1` and `gpt-5-mini`).
  - Resource arrays for account, project, function app, and resource group.

- `infra\modules\foundry-project.bicep` creates a project under an existing Foundry account and enables system-assigned identity on the project.

- `infra\modules\function-app.bicep` provisions the app runtime footprint:
  - Storage account + fixed blob containers (`app-package`, `focus-exports`, `normalized`, `results`).
  - Storage lifecycle management policy for short-lived blobs/snapshots/versions.
  - Linux Flex Consumption plan (`FC1`).
  - User-assigned managed identity.
  - Role assignment granting blob data owner on the storage account.
  - Linux Function App (`python` `3.12`) configured to deploy package from blob storage through managed identity.
  - Event Grid system topic + subscription for `Microsoft.Storage.BlobCreated` events on `focus-exports`.

- `python\function_app.py` is the Azure Function source. It registers `BlobCreatedEventGridFunction` (Event Grid trigger), reads FOCUS-format Parquet cost exports from the `focus-exports` container, runs cost anomaly detection (z-score, IQR, and day-over-day thresholds) grouped by `SubAccountId`/`SubAccountName`/`ServiceName`, and writes JSON results to the `normalized` container as both `latest.json` and `history/<timestamp>.json`.

## Key repository conventions

- Naming is pattern-driven and must stay compatible with split/segment logic used in modules. Current pattern is:
  - `rg-<shortName>-<environment>-<regionShort>-<index>`
  - `aif-<shortName>-<environment>-<regionShort>-<index>`
  - `proj-<shortName>-<environment>-<regionShort>-<index>`
  - `func-<shortName>-<environment>-<regionShort>-<index>`

- `infra\helpers\variables.bicep` is the source of truth for:
  - Allowed region short names (`swc`, `weu`, etc.).
  - Shared role definition IDs.
  Reuse these variables instead of hardcoding new region abbreviations or role IDs.

- Typed input objects in `infra\helpers\types.bicep` define the contract for `main.bicep` params. Keep new parameters aligned to these exported types.

- Security defaults are intentional and should be preserved unless explicitly changed:
  - Foundry account local auth disabled.
  - Managed identities used for workload/resource access.
  - Storage account hardening defaults enabled (TLS 1.2 minimum, blob public access disabled, shared key access disabled, cross-tenant replication disabled, infrastructure encryption required).

- CI workflows in `.github\workflows\`:
  - `validate-branch-name.yml` — PR branch name validation (see regex below).
  - `lint.yml` — Ruff (Python) + `az bicep build` (Bicep) on every PR and `main` push.
  - `security-scan.yml` — Bandit + pip-audit on every PR and `main` push.
  - `secret-scan.yml` — Gitleaks on every PR and `main` push.
  - `codeql.yml` — CodeQL Python analysis on PRs targeting `main` and pushes to `main`.

- PR branches must match the CI regex in `.github\workflows\validate-branch-name.yml`:
  - `^(feature|bug|hotfix|release|develop|iac)\/[a-zA-Z0-9._-]+$`

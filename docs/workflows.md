# Workflows Guide

## Overview

CI/CD automation is defined in `.github/workflows/`. There are **eight** workflows.

## Workflow summary

| Workflow | Trigger | Purpose |
|---|---|---|
| `validate-branch-name.yml` | PR opened/synchronized/reopened | Enforce branch naming convention |
| `bicep-lint.yml` | PR to `main` when `infra/**` changes | Lint + build Bicep and parameter files |
| `deploy-azure-resources.yml` | Push to `main` when `infra/**` changes | Deploy subscription-scoped infrastructure |
| `deploy-event-grids.yml` | Push to `main` when `infra/modules/event_grids.bicep` changes | Deploy Event Grid system topic + subscription wiring |
| `deploy-function-app.yml` | Push to `main` when `src/python/**` changes | Deploy Function App package |
| `python-lint.yml` | PR to `main` when `*.py` changes | Run Ruff |
| `security-scan.yml` | Push/PR when `*.py` changes | Run Bandit + pip-audit |
| `secret-scan.yml` | Every push/PR | Run Gitleaks against full history |

---

## Detailed workflows

### `validate-branch-name.yml`

- Regex: `^(feature|bugfix|designfix|hotfix)\/[a-zA-Z0-9._-]+$`
- Blocks PR on mismatch.

### `bicep-lint.yml`

- Uses OIDC Azure login with **repository variables**:
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
- Runs:
  - `az bicep lint`
  - `az bicep build`
  - `az bicep build-params`

### `deploy-azure-resources.yml`

- Uses OIDC Azure login with **repository variables**:
  - `vars.AZURE_CLIENT_ID`
  - `vars.AZURE_TENANT_ID`
  - `vars.AZURE_SUBSCRIPTION_ID`
- Uses `vars.DEPLOYMENT_LOCATION` for the deployment region.
- Exposes `AZURE_SUBSCRIPTION_ID` as runtime env var for Bicep param resolution.
- Runs subscription deployment of `infra/main.bicep` with `infra/main.bicepparam`.

### `deploy-event-grids.yml`

- Trigger: pushes to `main` affecting `infra/modules/event_grids.bicep`
- Uses OIDC Azure login with **repository variables** (`vars.*`)
- Looks up:
  - Function App `func-aiops-prd-weu-001`
  - Data storage account `stv2aiopsprdweu001` in the same resource group
- Runs resource-group deployment of `infra/modules/event_grids.bicep` with:
  - `functionAppResourceId`
  - `storageAccountResourceId`

### `deploy-function-app-apps.yml`

- Trigger: pushes to `main` affecting `src/python/**`
- Uses OIDC Azure login with **repository variables** (`vars.*`)
- Deploys with `Azure/functions-action@v1`:
  - `app-name: func-aiops-prd-weu-001`
  - `package: src/python`
  - `sku: flexconsumption`
  - `remote-build: true`

### `python-lint.yml`

- Python 3.12
- Installs Ruff
- Runs `ruff check .`

### `security-scan.yml`

- Python 3.12
- Installs `bandit`, `pip-audit`, and `src/python/requirements.txt`
- Runs:
  - `bandit -r . -x .venv,venv,.git,__pycache__`
  - `pip-audit`

### `secret-scan.yml`

- `actions/checkout@v6` with `fetch-depth: 0`
- Runs `gitleaks/gitleaks-action@v3`

---

## OIDC and GitHub configuration

All Azure-authenticating workflows (`bicep-lint.yml`, `deploy-azure-resources.yml`, `deploy-event-grids.yml`, `deploy-function-app-apps.yml`) read from the same **repository variables**:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `DEPLOYMENT_LOCATION` (used by infrastructure deployment)
- `FUNCTION_APP_NAME` (used by function-app deployment and Event Grid wiring)
- `DATA_STORAGE_ACCOUNT_NAME` (used by Event Grid wiring)

None of these three values are sensitive under OIDC — the actual trust boundary is the federated credential's `subject` claim, not the secrecy of a client ID, tenant ID, or subscription ID.

The OIDC identity must have federated credentials for:

- `ref:refs/heads/main` (push-based deployment workflows)
- `pull_request` (PR-based lint workflow)

---

## Suggested local-equivalent checks

```powershell
ruff check .
bandit -r . -x .venv,venv,.git,__pycache__
pip-audit
az bicep lint --file infra\main.bicep --diagnostics-format sarif
az bicep build --file infra\main.bicep
az bicep build-params --file infra\main.bicepparam
```

# Workflows Guide

## Overview

CI/CD automation is defined in `.github/workflows/`. There are **ten** workflows.

## Workflow summary

| Workflow | Trigger | Purpose |
|---|---|---|
| `validate-branch-name.yml` | PR opened/synchronized/reopened | Enforce branch naming convention |
| `bicep-lint.yml` | PR to `main` when `infra/**` changes | Lint + build Bicep and parameter files |
| `deploy-azure-resources.yml` | Push to `main` when `infra/**` changes | Deploy subscription-scoped infrastructure |
| `deploy-agent.yml` | Push to `main` when `agents/cost-efficiency-advisor/**` changes | Create/update the Foundry agent definition |
| `deploy-event-grids.yml` | Push to `main` when `infra/modules/event_grids.bicep` changes | Deploy Event Grid system topic + subscription wiring |
| `deploy-function-app-apps.yml` | Push to `main` when `src/python/**` changes | Deploy Function App package |
| `deploy-web-frontend.yml` | Push to `main` when `src/web/**` changes | Deploy the static web frontend to the Static Web App |
| `python-lint.yml` | PR to `main` when `*.py` changes | Run Ruff |
| `security-scan.yml` | Push/PR when `*.py` changes | Run Bandit + pip-audit |
| `secret-scan.yml` | Every push/PR | Run Gitleaks against full history |

---

## Detailed workflows

### `validate-branch-name.yml`

- Regex: `^(feature|bugfix|designfix|hotfix)\/[a-zA-Z0-9._-]+$`
- Blocks PR on mismatch.
- The branch name is passed through an environment variable (`env: BRANCH: ${{ github.head_ref }}`), not substituted directly into the inline script — `github.head_ref` is attacker-controllable on a PR from a fork, so direct substitution is a real script-injection vector, not just a style nit.

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
- Runs subscription deployment of `infra/main.bicep` with `infra/main.bicepparam`, capturing the deployment's outputs.
- Surfaces `functionAppName`, `dataStorageAccountName`, and `staticWebAppName` as a `::notice::` annotation in the run summary — **it deliberately does not write these to repository variables automatically.** `GITHUB_TOKEN` cannot write repository Variables under any `permissions:` grant — that scope simply doesn't exist for the auto-generated token, by design, to stop a workflow from being able to rewrite the credentials that control its own execution. The documented workaround (a Personal Access Token) would need write access to this repo's variables, including the ones that determine which Azure identity every other workflow authenticates as — a materially riskier credential to hold than the convenience of automating three occasional manual updates is worth. If any of the three names change (e.g. after switching `project.environment` or region), update the matching repository variable manually.

### `deploy-agent.yml`

- Trigger: pushes to `main` affecting `agents/cost-efficiency-advisor/**`
- Uses OIDC Azure login with **repository variables** (`vars.*`)
- Installs `agents/cost-efficiency-advisor/requirements.txt`, then runs `setup_agent.py` with `FOUNDRY_PROJECT_ENDPOINT` set from `vars.FOUNDRY_PROJECT_ENDPOINT`
- Exists specifically to close a real failure mode: `setup_agent.py` reads `tools.json`/`instructions.md` from whatever's on disk relative to itself, with zero awareness of what's actually merged on `origin/main`. Running it from a human's local clone means a stale, un-pulled local checkout can silently deploy old tool definitions while reporting success — which is exactly what happened once, costing a multi-step debugging session before the cause (a local checkout that hadn't been synced since before the fix was merged) was found. A fresh `actions/checkout@v4` on every run is definitionally never stale.
- The CI/CD identity already holds Foundry User at the Foundry account scope (granted in `infra/main.bicepparam`), so no new RBAC was needed for this workflow.
- `setup_agent.py` authenticates via `DefaultAzureCredential()`, which falls back to `AzureCliCredential` — the same session `azure/login@v2`'s OIDC exchange establishes, so no separate credential wiring is needed here either.

### `deploy-event-grids.yml`

- Trigger: pushes to `main` affecting `infra/modules/event_grids.bicep`
- Uses OIDC Azure login with **repository variables** (`vars.*`)
- Looks up, by name (not hardcoded resource group — resolved dynamically via `az functionapp list` / `az storage account show`):
  - Function App (`vars.FUNCTION_APP_NAME`)
  - Data storage account (`vars.DATA_STORAGE_ACCOUNT_NAME`) in the same resource group
- Fails fast with a clear error if either isn't found, rather than letting the Bicep deployment fail with a less obvious message
- Runs resource-group deployment of `infra/modules/event_grids.bicep` with:
  - `functionAppResourceId`
  - `storageAccountResourceId`
- Must run *after* the Function App code is actually deployed — the Event Grid destination references a specific function (`BlobCreatedEventGridFunction`), and creating the subscription before that function exists as a deployed sub-resource fails with "Destination endpoint not found."

### `deploy-function-app-apps.yml`

- Trigger: pushes to `main` affecting `src/python/**`
- Uses OIDC Azure login with **repository variables** (`vars.*`)
- Deploys with `Azure/functions-action@v1`:
  - `app-name: ${{ vars.FUNCTION_APP_NAME }}`
  - `package: src/python`
  - `sku: flexconsumption`
  - `remote-build: true`

### `deploy-web-frontend.yml`

- Trigger: pushes to `main` affecting `src/web/**`
- Uses OIDC Azure login with **repository variables** (`vars.*`)
- Looks up the Static Web App by name (`vars.STATIC_WEB_APP_NAME`) to resolve its resource group dynamically — same pattern as `deploy-event-grids.yml`
- Fetches a **fresh deployment token at runtime** (`az staticwebapp secrets list`, authenticated via the same OIDC login) rather than storing one as a persisted secret — masked immediately via `::add-mask::`, used once, never written anywhere
- Deploys via `Azure/static-web-apps-deploy@v1` with `app_location: src/web`, `skip_app_build: true`, no `api_location` (the app uses the linked backend, not SWA's own managed Functions)

### `python-lint.yml`

- Python 3.12
- Installs Ruff, **pinned** (`ruff==0.16.1`) — an earlier run of this workflow failed with zero code changes because ruff's own default rule selection expanded between runs, newly flagging pre-existing code. Pinning the version, and adding an explicit `pyproject.toml` documenting *why* one rule (`BLE001`) is deliberately disabled, prevents that recurring.
- Runs `ruff check .`

### `security-scan.yml`

- Python 3.12
- Installs `bandit` and `pip-audit`, both pinned (`bandit~=1.9.4`, `pip-audit~=2.10.1`) for the same reason as the Ruff pin above, plus `src/python/requirements.txt`
- Runs:
  - `bandit -r . -x .venv,venv,.git,__pycache__`
  - `pip-audit`

### `secret-scan.yml`

- `actions/checkout@v6` with `fetch-depth: 0`
- Runs `gitleaks/gitleaks-action@v3`

---

## OIDC and GitHub configuration

All Azure-authenticating workflows (`bicep-lint.yml`, `deploy-agent.yml`, `deploy-azure-resources.yml`, `deploy-event-grids.yml`, `deploy-function-app-apps.yml`, `deploy-web-frontend.yml`) read from the same **repository variables**:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `DEPLOYMENT_LOCATION` — used by infrastructure deployment; genuinely can't be auto-published the way the four below can, since it's needed *before* the deployment starts, not produced by it
- `FUNCTION_APP_NAME` — used by function-app deployment, Event Grid wiring
- `DATA_STORAGE_ACCOUNT_NAME` — used by Event Grid wiring
- `STATIC_WEB_APP_NAME` — used by the web frontend deployment
- `FOUNDRY_PROJECT_ENDPOINT` — used by agent deployment

None of these values are sensitive under OIDC — the actual trust boundary is the federated credential's `subject` claim, not the secrecy of a client ID, tenant ID, or subscription ID.

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

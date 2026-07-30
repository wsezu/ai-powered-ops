# Workflows Guide

## Overview

All CI/CD automation lives in `.github/workflows/`. There are six workflows covering branch governance, code quality, security, infrastructure validation, and deployment. All workflows that interact with Azure use OIDC federated authentication — no static credentials are stored.

## Summary

| Workflow file | Trigger | Purpose |
|---|---|---|
| `validate-branch-name.yml` | PR opened / updated | Enforce branch naming convention |
| `bicep-lint.yml` | PR to `main` on `infra/**` | Lint and compile all Bicep files |
| `deploy-azure-resources.yml` | Push to `main` on `infra/**` | Deploy infrastructure to Azure |
| `python-lint.yml` | PR to `main` on `*.py` | Lint Python with Ruff |
| `security-scan.yml` | Push / PR on `*.py` | Security scan Python with Bandit and pip-audit |
| `secret-scan.yml` | Every push / PR | Scan for hardcoded secrets with Gitleaks |

---

## Workflow Details

### `validate-branch-name.yml` — Validate branch name

**Triggers:** Pull request `opened`, `synchronize`, `reopened`

**Purpose:** Blocks PRs from branches that do not follow the enforced naming convention.

**Branch name regex:** `^(feature|bugfix|hotfix)/[a-zA-Z0-9._-]+$`

**Valid prefixes:** `feature/`, `bugfix/`, `hotfix/`

**Examples of valid names:**
```
feature/PROJ-123-login-page
bugfix/fix-null-pointer
hotfix/urgent-patch
```

**Behaviour:** Exits with code `1` on mismatch, blocking the PR. No Azure authentication or secrets required.

---

### `bicep-lint.yml` — Bicep lint

**Triggers:**
- Pull request targeting `main` when any `infra/**/*.bicep` or `infra/**/*.bicepparam` file changes
- Manual (`workflow_dispatch`)

**Permissions:** `contents: read`, `id-token: write` (for OIDC Azure login)

**Purpose:** Ensures all Bicep files are syntactically valid and free of lint issues before merge or deployment.

**Steps:**
1. Checkout repository
2. Azure login via OIDC using `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` secrets
3. Install Bicep CLI (`az bicep install`)
4. **Lint** every `*.bicep` file with `az bicep lint --diagnostics-format sarif`
5. **Compile** every `*.bicep` file with `az bicep build`
6. **Validate** every `*.bicepparam` file with `az bicep build-params`

**Notes:**
- Scoped to `infra/**` — changes outside the infra folder do not trigger this workflow
- Azure login is required because Bicep templates reference public AVM registry modules (`br/public:...`) that need token resolution during compilation
- Runs on PRs only (not on push); the deployment workflow handles post-merge validation

---

### `deploy-azure-resources.yml` — Deploy Azure resources

**Triggers:**
- Push to `main` when any file under `infra/**/*.bicep` or `infra/**/*.bicepparam` changes
- Manual (`workflow_dispatch`)

**Permissions:** `contents: read`, `id-token: write`

**Purpose:** Deploys the subscription-scoped Bicep infrastructure to Azure after changes land on `main`.

**Steps:**
1. Checkout repository
2. Azure login via OIDC
3. Set active subscription: `a525b25c-14fc-42cb-a55f-9dedea6bffaa`
4. Run `az deployment sub create` with:
   - Deployment name: `aiops-infra-<run-id>` (unique per run)
   - Location: `westeurope`
   - Template: `infra/main.bicep`
   - Parameters: `infra/main.bicepparam`
   - `--only-show-errors` (suppresses verbose ARM output)

**Secrets required:**

| Secret | Purpose |
|--------|---------|
| `AZURE_CLIENT_ID` | Managed identity client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Default subscription for OIDC login |

**Notes:**
- The deployment subscription is hardcoded in the workflow (`az account set`) as well as defined in `main.bicepparam`
- The deployment runs at subscription scope (`az deployment sub create`) matching `main.bicep`'s `targetScope = 'subscription'`
- Only changes inside `infra/` trigger this workflow; changes to other folders (docs, bootstrap, etc.) do not

---

### `python-lint.yml` — Python lint

**Triggers:**
- Pull request targeting `main` when any `*.py` file changes
- Manual (`workflow_dispatch`)

**Permissions:** `contents: read`

**Purpose:** Enforces Python code style and correctness across all Python files using [Ruff](https://docs.astral.sh/ruff/).

**Steps:**
1. Checkout repository
2. Set up Python 3.12
3. Install Ruff (`pip install ruff`)
4. Run `ruff check .` across the entire repository

**Notes:**
- Ruff is a fast, drop-in replacement for Flake8/isort/pyflakes
- No Azure authentication required

---

### `security-scan.yml` — Security Scan

**Triggers:**
- Push or PR when any `*.py` file changes
- Manual (`workflow_dispatch`)

**Permissions:** `contents: read`

**Purpose:** Performs two independent Python security checks on every Python change:

1. **[Bandit](https://bandit.readthedocs.io/)** — static analysis for common security vulnerabilities in Python code
   - Excludes: `.venv`, `venv`, `.git`, `__pycache__`
   - Scans recursively from repository root

2. **[pip-audit](https://pypi.org/project/pip-audit/)** — audits installed packages against known vulnerability databases (CVE/OSV)

**Steps:**
1. Checkout repository
2. Set up Python 3.12
3. Install Bandit and pip-audit
4. Run Bandit (`bandit -r . -x .venv,venv,.git,__pycache__`)
5. Run pip-audit

**Notes:**
- Runs independently from `python-lint.yml`; both trigger on `*.py` changes
- No Azure authentication required

---

### `secret-scan.yml` — Secret Scan

**Triggers:** Every push and every PR (no path filter), manual (`workflow_dispatch`)

**Purpose:** Scans the entire commit history for hardcoded secrets, credentials, API keys, and tokens using [Gitleaks](https://github.com/gitleaks/gitleaks).

**Steps:**
1. Checkout with full history (`fetch-depth: 0`) to scan all commits, not just the latest
2. Run `gitleaks/gitleaks-action@v3`

**Secrets required:** `GITHUB_TOKEN` (built-in, no configuration needed)

**Notes:**
- This workflow has **no path filter** — it runs on every push and PR regardless of which files changed
- Full history checkout (`fetch-depth: 0`) is critical; without it, secrets committed in earlier history would be missed

---

## Azure Authentication (OIDC)

Workflows that access Azure (`bicep-lint`, `deploy-azure-resources`) authenticate using OIDC federated credentials — no static secrets are stored. The managed identity has two federated credentials: one scoped to the `main` branch (used by the deploy workflow) and one scoped to pull requests (used by the lint workflow). See [docs/bootstrap.md](bootstrap.md) for setup details.

Required repository secrets:

| Secret | Set by |
|--------|--------|
| `AZURE_CLIENT_ID` | Bootstrap script |
| `AZURE_TENANT_ID` | Bootstrap script |
| `AZURE_SUBSCRIPTION_ID` | Bootstrap script |

## Adding a New Workflow

- Path filters (`paths:`) should be used to avoid running expensive or deployment workflows on unrelated changes
- Workflows that call Azure must include `id-token: write` permission and the OIDC login step
- Always pin action versions (e.g., `actions/checkout@v4`) for reproducibility
- Avoid hardcoding subscription IDs where possible — prefer the `AZURE_SUBSCRIPTION_ID` secret

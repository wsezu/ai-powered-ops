# Bootstrap Guide

## Overview

`bootstrap/` contains one-time setup scripts to create the GitHub + Azure foundation required by this repository’s workflows.

- `Bootstrap.ps1` (PowerShell)
- `bootstrap.sh` (Bash)

Bootstrap is optional, but useful when creating a new repo/subscription setup from scratch.

## What bootstrap creates

1. GitHub repository (`gh repo create`)
2. Azure resource group: `rg-<repo>-prd-<location>-001`
3. User-assigned managed identity: `id-<repo>-prd-<location>-001`
4. Two federated credentials on that identity:
   - `branch-main` (`ref:refs/heads/main`)
   - `pull-request` (`pull_request`)
5. GitHub **secrets**:
   - `AZURE_CLIENT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_TENANT_ID`
6. Reader role assignment at subscription scope for the identity principal

## Prerequisites

### CLI tools

- GitHub CLI (`gh`)
- Azure CLI (`az`)
- `jq` (Bash script only)

### Permissions

- GitHub org/repo creation permissions
- Azure permission to create identity/resources + role assignments

## Usage

### PowerShell

```powershell
.\bootstrap\Bootstrap.ps1 -Org <org> -Repo <repo> -SubscriptionId <subscription-id> -Location <location>
```

### Bash

```bash
./bootstrap/bootstrap.sh --org <org> --repo <repo> --subscription <subscription-id> --location <location>
```

## OIDC subjects used

- `repo:<org>@<org-id>/<repo>@<repo-id>:ref:refs/heads/main`
- `repo:<org>@<org-id>/<repo>@<repo-id>:pull_request`

These are built dynamically from GitHub repository metadata.

## Important workflow alignment note

Bootstrap currently writes Azure values to **GitHub secrets**.

Some workflows in this repo (`deploy-azure-resources.yml`, `deploy-function-app.yml`) currently read Azure values from **GitHub repository variables** (`vars.*`) rather than secrets.

After bootstrap, ensure repository variables are also set:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

You can either:

1. set these variables manually in repository settings, or
2. standardize workflows to use secrets only.

## Security model

- No static Azure client secret is stored.
- GitHub Actions authenticate using OIDC token exchange to the managed identity.
- Scope is constrained by federated credential subjects (main branch + pull request contexts).

## Troubleshooting

### Common failures

- Missing CLI dependency (`gh`, `az`, `jq`)
- Insufficient GitHub/Azure permissions
- Repository already exists
- OIDC mismatch (missing/incorrect federated credential subject)
- Workflow failures due to missing repo variables (`vars.AZURE_*`)

## Cleanup

```bash
gh repo delete <org>/<repo>
az group delete --name rg-<repo>-prd-<location>-001 --subscription <subscription-id>
```

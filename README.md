# ai-powered-ops

AI-driven FinOps and SecOps architecture advisor infrastructure on Azure.

## Repository scope

This repository currently contains Infrastructure as Code only (Bicep). There is no application source code, runtime services, or test suite in-repo yet.

## What gets deployed

The deployment entrypoint is `infra\main.bicep` (subscription scope). It orchestrates:

1. Resource group creation using Azure Verified Modules (AVM).
2. Azure AI Foundry/Cognitive Services account creation (including model deployments).
3. Foundry project creation under the Foundry account.
4. Azure Function App infrastructure (Linux Flex Consumption) with managed identity and storage-backed package deployment.

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
- `infra\modules\function-app.bicep` - Function App + plan + storage + identity + role assignment
- `infra\helpers\types.bicep` - typed parameter contracts used by `main.bicep`
- `infra\helpers\variables.bicep` - shared region metadata and role definition IDs
- `.github\workflows\validate-branch-name.yml` - PR branch naming policy
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

`^(feature|bug|hotfix|release|develop)\/[a-zA-Z0-9._-]+$`

Examples:

- `feature/PROJ-123-login-page`
- `bug/PROJ-456-nullpointer`

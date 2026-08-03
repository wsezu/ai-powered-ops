# Infrastructure Guide

## Overview

Infrastructure is defined under `infra/` and deployed at **subscription scope** via `main.bicep`. The template creates/uses a single primary resource group and deploys platform resources through three modules:

1. `supporting_resources.bicep`
2. `function-app_resources.bicep`
3. `foundry_resources.bicep`

## Folder structure

```text
infra/
├── main.bicep
├── main.bicepparam
├── helpers/
│   ├── types.bicep
│   └── variables.bicep
└── modules/
    ├── supporting_resources.bicep
    ├── function-app_resources.bicep
    └── foundry_resources.bicep
```

## Deployment flow

### `main.bicep`

- `targetScope = 'subscription'`
- Deploys resource groups via AVM (`avm/res/resources/resource-group:0.4.3`)
- Then deploys:
  - supporting resources (`sr`)
  - function app resources (`far`)
  - foundry resources (`fr`)

The function module consumes outputs from supporting resources:
- Application Insights resource ID
- two storage account resource IDs
- user-assigned identity resource ID
- virtual network subnet resource ID

## Parameters and naming (`main.bicepparam`)

### Project constants

- `project.shortName = aiops`
- `project.environment = prd`
- `project.location = swedencentral`

### Subscription resolution

`subscriptionId` is sourced from environment variable `AZURE_SUBSCRIPTION_ID` with a fallback default.

### Resource naming

- Standard pattern: `<type>-<shortName>-<environment>-<regionShortName>-<instance>`
- Private storage: `stv2<suffix>001`
- Public/system storage: `stv2<suffix>002`
- Storage names are truncated to 24 chars when needed.

### Current configured resources

- Resource group: `rg-aiops-prd-swc-001`
- App Insights: `appi-aiops-prd-swc-001`
- Log Analytics: `log-aiops-prd-swc-001`
- NSG: `nsg-aiops-prd-swc-001`
- VNet: `vnet-aiops-prd-swc-001`
- Function App: `func-aiops-prd-swc-001`
- App Service plan: `asp-aiops-prd-swc-001`
- Identity: `id-aiops-prd-swc-001`
- AI Foundry account: `fa-aiops-prd-swc-001`
- AI Foundry project: `proj-aiops-prd-swc-001`

### Storage account intent

`storageAccounts` is an array with two entries:

1. **Data storage** (`...001`)
   - containers: `focus-exports`, `normalized`
   - network ACL default deny + VNet rule
2. **System/package storage** (`...002`)
   - container: `app-packages`
   - network ACL default allow

## Module details

### `modules/supporting_resources.bicep`

Deploys:
- network watcher (optional flag)
- network security group
- virtual network with subnets:
  - `FunctionApps` (`10.107.1.0/24`, delegated `Microsoft.App/environments`, storage service endpoint)
  - `StorageAccounts` (`10.107.2.0/24`)
  - `Main` (`10.107.77.0/24`)
- Log Analytics
- Application Insights (connected to workspace)
- User-assigned identity
- Storage accounts (loop over `storageAccounts`)

Security/constraints on storage:
- `allowBlobPublicAccess: false`
- `allowSharedKeyAccess: false`
- `allowCrossTenantReplication: false`
- `minimumTlsVersion: TLS1_2`
- `supportsHttpsTrafficOnly: true`
- `requireInfrastructureEncryption: true`

Role assignments for each storage account are bound to the deployed managed identity principal.

### `modules/function-app_resources.bicep`

Deploys:
- Linux App Service plan (`FC1`)
- Function App (`kind: functionapp,linux`)

Function app wiring:
- Uses user-assigned identity only (`systemAssigned: false`)
- `AzureWebJobsStorage__*` points to **system storage** account
- `DataStorage__*` points to **data storage** account
- Deployment package source: `https://<system-storage>.blob.<suffix>/app-packages`
- Runtime: Python `3.12`
- VNet integration via `virtualNetworkSubnetResourceId`
- Outbound VNet routing enabled (`allTraffic: true`)
- HTTPS only

### `modules/foundry_resources.bicep`

Deploys AI Foundry via AVM pattern module `avm/ptn/ai-ml/ai-foundry:0.7.0`.

Configured model deployments:
- `gpt-5.1` (`DataZoneStandard`, capacity 10)
- `gpt-5-mini` (`DataZoneStandard`, capacity 20)

## Shared helpers

### `helpers/types.bicep`

Defines exported types for:
- `applicationInsights`
- `foundryAccount`
- `functionApp`
- `logAnalyticsWorkspace`
- `networkSecurityGroup`
- `networkWatcher`
- `resourceGroup`
- `serverFarm`
- `storageAccount`
- `userAssignedIdentity`
- `virtualNetwork`

Notable conventions:
- Role assignments use `roleDefinitionId`
- Storage supports ACLs, blob containers, and role assignment arrays

### `helpers/variables.bicep`

- Region map with short names (e.g., `swedencentral -> swc`)
- Role definition ID constants, including:
  - `StorageBlobDataOwner`
  - `StorageBlobDataContributor`
  - `StorageQueueDataContributor`
  - `StorageTableDataContributor`

## Validation and deployment commands

```powershell
az bicep lint --file infra\main.bicep --diagnostics-format sarif
az bicep build --file infra\main.bicep
az bicep build-params --file infra\main.bicepparam
```

```powershell
az deployment sub create --name "aiops-infra-<run-id>" --location "westeurope" --template-file infra\main.bicep --parameters infra\main.bicepparam --only-show-errors
```

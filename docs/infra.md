# Infrastructure Guide

## Overview

The `infra/` folder contains Bicep infrastructure-as-code templates for deploying Azure resources at subscription scope. The structure separates configuration (parameters), reusable type definitions (helpers), and deployment logic (modules) to keep each file focused.

## Folder Structure

```
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

## Entry Point

### `main.bicep`

- **Scope:** `subscription`
- **Purpose:** Deploys resource groups first, then deploys supporting platform resources, a Linux Function App stack, and AI Foundry resources into the first resource group.
- **Imports:** `helpers/types.bicep`

**Parameters**

| Parameter | Type | Description |
|---|---|---|
| `applicationInsights` | `applicationInsights` | Application Insights configuration |
| `foundryAccount` | `foundryAccount` | AI Foundry account and model deployment configuration |
| `functionApp` | `functionApp` | Function App configuration |
| `logAnalyticsWorkspace` | `logAnalyticsWorkspace` | Log Analytics Workspace configuration |
| `resourceGroups` | `resourceGroup[]` | Resource groups to deploy |
| `serverFarm` | `serverFarm` | App Service plan configuration |
| `storageAccount` | `storageAccount` | Storage account configuration |
| `userAssignedIdentity` | `userAssignedIdentity` | User-assigned managed identity configuration |

**Deployment flow**

1. Resource groups are deployed with `br/public:avm/res/resources/resource-group:0.4.3`, each scoped to its own subscription via `az.subscription(resourceGroup.subscriptionId)`.
2. `supporting_resources.bicep` runs in the first resource group and deploys Log Analytics, Application Insights, a user-assigned identity, and a hardened storage account.
3. `function-app_resources.bicep` runs in the same resource group and deploys the Linux App Service plan and Function App, wiring it to the supporting resources.
4. `foundry_resources.bicep` runs in the same resource group and deploys the AI Foundry account and model deployments.

---

## Parameters File

### `main.bicepparam`

Defines the concrete values passed to `main.bicep`.

**Project variables**

| Variable | Value | Purpose |
|---|---|---|
| `project.description` | `AI Powered FinOps and SecOps` | Used in tags |
| `project.environment` | `prd` | Environment suffix |
| `project.location` | `swedencentral` | Primary Azure region |
| `project.name` | `AI powered ops` | Used in tags |
| `project.shortName` | `aiops` | Resource name prefix |

**Naming patterns**

| Resource | Pattern | Example |
|---|---|---|
| Standard resources | `<type>-<shortName>-<environment>-<regionShortName>-<instance>` | `rg-aiops-prd-swc-001` |
| Storage account | `stv2<shortName><environment><regionShortName>001` | `stv2aiopsprdswc001` |
| AI Foundry account | `fa-<shortName>-<environment>-<regionShortName>-<instance>` | `fa-aiops-prd-swc-001` |
| AI Foundry project | `proj-<shortName>-<environment>-<regionShortName>-<instance>` | `proj-aiops-prd-swc-001` |
| Function App | `func-<shortName>-<environment>-<regionShortName>-<instance>` | `func-aiops-prd-swc-001` |
| App Service plan | `asp-<shortName>-<environment>-<regionShortName>-<instance>` | `asp-aiops-prd-swc-001` |

**Deployed resources**

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-aiops-prd-swc-001` | Deployed to subscription `a525b25c-14fc-42cb-a55f-9dedea6bffaa` |
| Log Analytics Workspace | `log-aiops-prd-swc-001` | 30-day retention, `PerGB2018` SKU |
| Application Insights | `appi-aiops-prd-swc-001` | Linked to the Log Analytics workspace |
| User-assigned identity | `id-aiops-prd-swc-001` | Used by the Function App for storage access |
| Storage account | `stv2aiopsprdswc001` | `StorageV2`, `Standard_LRS`, hot tier |
| App Service plan | `asp-aiops-prd-swc-001` | Linux, `FC1`, reserved |
| Function App | `func-aiops-prd-swc-001` | Python 3.12, managed identity auth |
| AI Foundry account | `fa-aiops-prd-swc-001` | `S0` SKU |
| AI Foundry project | `proj-aiops-prd-swc-001` | Project description: AI powered FinOps and SecOps architecture advisor infrastructure on Azure |

**AI model deployments**

| Name | Model | Version | SKU | Capacity |
|---|---|---|---|---|
| `gpt-5.1` | `gpt-5.1` | `2025-11-13` | `DataZoneStandard` | `10` |
| `gpt-5-mini` | `gpt-5-mini` | `2025-08-07` | `DataZoneStandard` | `20` |

**Tags**

| Tag | Value |
|---|---|
| `description` | `AI Powered FinOps and SecOps` |
| `environment` | `prd` |
| `project` | `AI powered ops` |

---

## Helpers

### `helpers/types.bicep`

Shared types used by the Bicep templates.

#### `resourceGroup`

```bicep
type resourceGroup = {
  location: string?
  name: string
  roleAssignments: roleAssignment[]?
  subscriptionId: string
  tags: object?
}
```

#### `logAnalyticsWorkspace`

```bicep
type logAnalyticsWorkspace = {
  dataRetention: int?
  location: string?
  name: string
  roleAssignments: roleAssignment[]?
  skuName: 'CapacityReservation' | 'LACluster' | 'PerGB2018'?
  tags: object?
}
```

#### `applicationInsights`

```bicep
type applicationInsights = {
  location: string?
  name: string
  roleAssignments: roleAssignment[]?
  tags: object?
  workspaceResourceId: string?
}
```

#### `storageAccount`

```bicep
type storageAccount = {
  accessTier: 'Cold' | 'Cool' | 'Hot' | 'Premium'?
  kind: 'BlobStorage' | 'BlockBlobStorage' | 'FileStorage' | 'Storage' | 'StorageV2'?
  location: string?
  name: string
  roleAssignments: roleAssignment[]?
  skuName: 'Premium_LRS' | 'Premium_ZRS' | 'PremiumV2_LRS' | 'PremiumV2_ZRS' | 'Standard_GRS' | 'Standard_GZRS' | 'Standard_LRS' | 'Standard_RAGRS' | 'Standard_RAGZRS' | 'Standard_ZRS' | 'StandardV2_GRS' | 'StandardV2_GZRS' | 'StandardV2_LRS' | 'StandardV2_ZRS'?
  tags: object?
}
```

#### `userAssignedIdentity`

```bicep
type userAssignedIdentity = {
  location: string?
  name: string
  tags: object?
}
```

#### `functionApp`

```bicep
type functionApp = {
  kind: 'functionapp,linux'
  location: string?
  managedIdentities: managedIdentity?
  name: string
  serverFarmResourceId: string?
  tags: object?
}
```

#### `serverFarm`

```bicep
type serverFarm = {
  location: string?
  name: string
  tags: object?
}
```

#### `foundryAccount`

```bicep
type foundryAccount = {
  aiFoundryConfiguration: aiFoundryConfiguration?
  aiModelDeployments: {
    model: {
      name: string
      format: string
      version: string
    }
    name: string?
    sku: {
      capacity: int?
      name: string
    }?
    versionUpgradeOption: string?
  }[]?
  baseName: string
  location: string?
  tags: object?
}
```

**Foundry configuration**

- Account name: `fa-<shortName>-<environment>-<regionShortName>-<instance>`
- Project name: `proj-<shortName>-<environment>-<regionShortName>-<instance>`
- Project display name: `AI powered Ops`
- Project description: `AI powered FinOps and SecOps architecture advisor infrastructure on Azure.`
- SKU: `S0`
- Project management enabled

---

### `helpers/variables.bicep`

Shared constants used across the templates.

#### `regions`

| Key | `location` | `shortName` |
|---|---|---|
| `francecentral` | `francecentral` | `frc` |
| `germanywestcentral` | `germanywestcentral` | `gwc` |
| `northeurope` | `northeurope` | `neu` |
| `swedencentral` | `swedencentral` | `swc` |
| `westeurope` | `westeurope` | `weu` |

#### `roleDefinitionId`

| Key | GUID |
|---|---|
| `CostManagementReaderRoleId` | `72fafb9e-0641-4937-9268-a91bfd8191a3` |
| `ReaderRoleId` | `acdd72a7-3385-48ef-bd42-f606fba81ae7` |
| `SecurityReaderRoleId` | `39bc4728-0917-49c7-9d2c-d95423bc2eb4` |
| `StorageBlobDataContributor` | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` |
| `StorageBlobDataOwner` | `b7e6dc6d-f1e8-4753-8033-0f276bb0955b` |
| `StorageBlobDataReader` | `2a2b9908-6ea1-4ae2-8e65-a410df84e7d1` |
| `StorageQueueDataContributor` | `974c5e8b-45b9-4653-ba55-5f855dd0fb88` |
| `StorageTableDataContributor` | `0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3` |

---

## Modules

### `modules/supporting_resources.bicep`

- **Scope:** `resourceGroup`
- **Purpose:** Deploys Log Analytics Workspace, Application Insights, a user-assigned identity, and a hardened storage account.
- **AVM modules:** `avm/res/operational-insights/workspace:0.16.0`, `avm/res/insights/component:0.8.0`, `avm/res/managed-identity/user-assigned-identity:0.6.0`, `avm/res/storage/storage-account:0.33.0`

**Storage containers**

- `app-packages`
- `focus-exports`
- `normalized`

**Storage hardening**

- `allowBlobPublicAccess: true`
- `allowCrossTenantReplication: false`
- `allowSharedKeyAccess: false`
- `minimumTlsVersion: TLS1_2`
- `publicNetworkAccess: Enabled`
- `requireInfrastructureEncryption: true`
- `supportsHttpsTrafficOnly: true`

**Role assignments**

- `StorageBlobDataContributor`
- `StorageQueueDataContributor`
- `StorageTableDataContributor`

### `modules/function-app_resources.bicep`

- **Scope:** `resourceGroup`
- **Purpose:** Deploys a Linux App Service plan and Python Function App.
- **AVM modules:** `avm/res/web/serverfarm:0.7.0`, `avm/res/web/site:0.24.0`

**Inputs**

- Existing storage account resource ID
- Existing user-assigned identity resource ID
- Application Insights resource ID from `supporting_resources.bicep`

**Function App configuration**

- Runtime: Python 3.12
- `kind: functionapp,linux`
- Managed identity only for Azure WebJobs storage access
- App settings point to the storage account using managed identity
- Deployment package is loaded from the `app-packages` blob container
- `AzureWebJobsStorage` uses the storage account blob, queue, and table endpoints
- CORS allows `https://portal.azure.com`
- `httpsOnly: true`

### `modules/foundry_resources.bicep`

- **Scope:** `resourceGroup`
- **Purpose:** Deploys the AI Foundry account using the public AVM pattern module.
- **AVM module:** `br/public:avm/ptn/ai-ml/ai-foundry:0.7.0`

**Model deployments**

- `gpt-5.1`
- `gpt-5-mini`

---

## Conventions

- Resource names use the `<type>-<shortName>-<environment>-<regionShortName>-<instance>` pattern unless a service has a stricter rule.
- Storage accounts use the `stv2<shortName><environment><regionShortName>001` format and are truncated to 24 characters when needed.
- Region names come from `v.regions.<key>.location`.
- Role definition GUIDs come from `v.roleDefinitionId.<key>`.
- Bicep modules use AVM public registry modules with pinned versions.
- Optional module inputs use safe access (`resource.?field`).
- All Azure resources are deployed through `resourceGroup().location` within resource-group-scoped modules.

---

## Deployment

```bash
az deployment sub create \
  --name "aiops-infra-$(date +%s)" \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

```powershell
New-AzSubscriptionDeployment `
  -Name "aiops-infra-$(Get-Date -Format 'yyyyMMddHHmmss')" `
  -Location swedencentral `
  -TemplateFile infra/main.bicep `
  -TemplateParameterFile infra/main.bicepparam
```

### Validate without deploying

```bash
az bicep build --file infra/main.bicep
az bicep build-params --file infra/main.bicepparam
```

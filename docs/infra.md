# Infrastructure Guide

## Overview

The `infra/` folder contains Bicep infrastructure-as-code templates for deploying Azure resources at subscription scope. The structure separates configuration (parameters), reusable type definitions (helpers), and deployment logic (modules) to keep each file focused.

## Folder Structure

```
infra/
├── main.bicep                      # Entry point; orchestrates all deployments
├── main.bicepparam                 # Environment-specific configuration values
├── helpers/
│   ├── types.bicep                 # Shared custom Bicep types
│   └── variables.bicep             # Shared constants (regions, role definition IDs)
└── modules/
    └── supporting_resources.bicep  # Deploys Log Analytics, App Insights, Identity, Storage
```

## Entry Point

### `main.bicep`

- **Scope:** `subscription` — deployed at Azure subscription level
- **Purpose:** Creates resource groups, then calls `modules/supporting_resources.bicep` for the remaining resources inside the first resource group.
- **Imports:** `helpers/types.bicep`

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `applicationInsights` | `applicationInsights` | Application Insights instance configuration |
| `logAnalyticsWorkspace` | `logAnalyticsWorkspace` | Log Analytics workspace configuration |
| `resourceGroups` | `resourceGroup[]` | Array of resource group definitions to deploy |
| `storageAccount` | `storageAccount` | Storage account configuration |
| `userAssignedIdentity` | `userAssignedIdentity` | User-assigned managed identity configuration |

**Deployment flow:**
1. Resource groups are deployed in a loop using `br/public:avm/res/resources/resource-group:0.4.3`, each scoped to its target subscription (`az.subscription(resourceGroup.subscriptionId)`). This allows creating groups across multiple subscriptions in one deployment.
2. The `supporting_resources` module runs after (`dependsOn: [rgs]`), scoped to `resourceGroups[0]`, and deploys all other resources into that resource group.

---

## Parameters File

### `main.bicepparam`

Defines concrete values for all parameters. Uses `helpers/variables.bicep` for consistent region and naming references.

**Local variables:**

| Variable | Value | Purpose |
|----------|-------|---------|
| `project.description` | `AI Powered FinOps and SecOps` | Applied as `description` tag |
| `project.environment` | `prd` | Used in resource naming and tags |
| `project.location` | `swedencentral` | Primary Azure region |
| `project.name` | `AI powered ops` | Applied as `project` tag |
| `project.shortName` | `aiops` | Abbreviated name used in all resource names |

**Resource suffix pattern:** `<shortName>-<environment>-<regionShortName>`
- Example: `aiops-prd-swc`

**Storage account naming:** `stv2` + suffix with hyphens removed + `001`, truncated to 24 characters if needed.
- Example: `stv2aiopsprdswc001`

**Tags applied to all resources:**

| Tag | Value |
|-----|-------|
| `description` | `AI Powered FinOps and SecOps` |
| `environment` | `prd` |
| `project` | `AI powered ops` |

**Deployed resources:**

| Resource | Name | Notes |
|----------|------|-------|
| Resource group | `rg-aiops-prd-swc-001` | Subscription `a525b25c-...`, region `swedencentral` |
| Log Analytics Workspace | `log-aiops-prd-swc-001` | 30-day retention, `PerGB2018` SKU |
| Application Insights | `appi-aiops-prd-swc-001` | Linked to Log Analytics workspace |
| User-Assigned Identity | `id-aiops-prd-swc-001` | Used for storage access |
| Storage Account | `stv2aiopsprdswc001` | Hot, StorageV2, Standard_LRS |

---

## Helpers

### `helpers/types.bicep`

Defines and exports five custom types. All types support optional `roleAssignments`, `location`, and `tags` fields.

#### `resourceGroup` (exported)

```bicep
type resourceGroup = {
  location: string?
  name: string
  roleAssignments: roleAssignment[]?
  subscriptionId: string
  tags: object?
}
```

#### `logAnalyticsWorkspace` (exported)

```bicep
type logAnalyticsWorkspace = {
  dataRetention: int?
  location: string?
  name: string
  resourceGroupName: string
  roleAssignments: roleAssignment[]?
  skuName: 'CapacityReservation' | 'LACluster' | 'PerGB2018'?
  tags: object?
}
```

#### `applicationInsights` (exported)

```bicep
type applicationInsights = {
  location: string?
  name: string
  resourceGroupName: string
  roleAssignments: roleAssignment[]?
  tags: object?
  workspaceResourceId: string?
}
```

#### `storageAccount` (exported)

```bicep
type storageAccount = {
  accessTier: 'Cold' | 'Cool' | 'Hot' | 'Premium'?
  kind: 'BlobStorage' | 'BlockBlobStorage' | 'FileStorage' | 'Storage' | 'StorageV2'?
  location: string?
  name: string
  resourceGroupName: string
  roleAssignments: roleAssignment[]?
  skuName: 'Premium_LRS' | 'Premium_ZRS' | 'Standard_GRS' | 'Standard_LRS' | 'Standard_ZRS' | ...?
  tags: object?
}
```

#### `userAssignedIdentity` (exported)

```bicep
type userAssignedIdentity = {
  location: string?
  name: string
  resourceGroupName: string
  tags: object?
}
```

#### `roleAssignment` (internal)

```bicep
type roleAssignment = {
  principalId: string
  principalType: 'Device' | 'ForeignGroup' | 'Group' | 'ServicePrincipal' | 'User'
  roleDefinitionIdOrName: string
}
```

---

### `helpers/variables.bicep`

Exports two constants used across all Bicep files and the parameters file.

#### `regions` (exported)

| Key | `location` | `shortName` |
|-----|-----------|-------------|
| `francecentral` | `francecentral` | `frc` |
| `germanywestcentral` | `germanywestcentral` | `gwc` |
| `northeurope` | `northeurope` | `neu` |
| `swedencentral` | `swedencentral` | `swc` |
| `westeurope` | `westeurope` | `weu` |

Usage: `v.regions.swedencentral.location` → `'swedencentral'`

#### `roleDefinitionId` (exported)

| Key | GUID |
|-----|------|
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

- **Scope:** `resourceGroup` — deploys into the resource group created by `main.bicep`
- **Purpose:** Deploys Log Analytics Workspace, Application Insights, User-Assigned Managed Identity, and Storage Account as a cohesive set of supporting infrastructure.
- **Imports:** `helpers/types.bicep`, `helpers/variables.bicep`

**Parameters:**

| Parameter | Type |
|-----------|------|
| `applicationInsights` | `type.applicationInsights` |
| `logAnalticsWorkspace` | `type.logAnalyticsWorkspace` |
| `storageAccount` | `type.storageAccount` |
| `userAssignedIdentity` | `type.userAssignedIdentity` |

**Deployment order and dependencies:**

```
log (Log Analytics Workspace)
 └─► appi (Application Insights)  ← workspaceResourceId = log.outputs.resourceId
id  (User-Assigned Identity)
 └─► sa (Storage Account)         ← role assignments use id.outputs.principalId
```

**AVM modules used:**

| Resource | AVM module | Version |
|----------|-----------|---------|
| Log Analytics Workspace | `avm/res/operational-insights/workspace` | `0.16.0` |
| Application Insights | `avm/res/insights/component` | `0.8.0` |
| User-Assigned Identity | `avm/res/managed-identity/user-assigned-identity` | `0.6.0` |
| Storage Account | `avm/res/storage/storage-account` | `0.33.0` |

**Storage account security hardening (applied automatically):**

| Setting | Value |
|---------|-------|
| `minimumTlsVersion` | `TLS1_2` |
| `allowSharedKeyAccess` | `false` |
| `allowCrossTenantReplication` | `false` |
| `supportsHttpsTrafficOnly` | `true` |
| `requireInfrastructureEncryption` | `true` |

**Storage role assignments (automatically granted to the managed identity):**

| Role | Purpose |
|------|---------|
| `StorageBlobDataContributor` | Read/write blob data |
| `StorageQueueDataContributor` | Read/write queue data |
| `StorageTableDataContributor` | Read/write table data |

**Outputs:**

| Output | Type | Contents |
|--------|------|---------|
| `applicationInsights` | `object` | `name`, `resourceId` |
| `logAnalyticsWorkspace` | `object` | `name`, `resourceId` |
| `storageAccount` | `object` | `name`, `resourceId` |
| `userAssignedIdentity` | `object` | `name`, `resourceId` |

---

## Conventions

- **Resource naming pattern:** `<type>-<shortName>-<environment>-<regionShortName>-<instance>`, e.g. `rg-aiops-prd-swc-001`
- **Storage account naming:** Prefix `stv2`, remove hyphens from suffix, append `001`; truncate to 24 characters
- **Region references:** Always use `v.regions.<key>.location` — never hardcode region strings
- **Role definition IDs:** Always use `v.roleDefinitionId.<key>` — never hardcode GUIDs
- **AVM modules:** All resource modules sourced from `br/public:avm/...` with pinned versions
- **Optional parameters:** Use safe-access operator (`resource.?field`) when passing optional fields to AVM modules
- **All resources use `resourceGroup().location`** inside modules (not a passed-in location), so location is always inherited from the scope

---

## Deployment

**Deploy from the parameters file:**

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

**Validate without deploying:**

```bash
az bicep build --file infra/main.bicep
az bicep build-params --file infra/main.bicepparam
```
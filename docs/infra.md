# Infrastructure Guide

## Overview

The `infra/` folder contains Bicep infrastructure-as-code templates for deploying Azure resources at subscription scope. The structure separates configuration (parameters), reusable type definitions (helpers), and deployment logic (modules) to keep each file focused.

## Folder Structure

```
infra/
├── main.bicep           # Entry point; receives parameters and calls modules
├── main.bicepparam      # Environment-specific configuration values
├── helpers/
│   ├── types.bicep      # Shared custom Bicep types
│   └── variables.bicep  # Shared constants (regions, role definition IDs)
└── modules/
    └── resourceGroups.bicep  # Deploys one or more resource groups via AVM
```

## Entry Point

### `main.bicep`

- **Scope:** `subscription` — deployed at Azure subscription level
- **Purpose:** Iterates over the `resourceGroups` parameter array and calls the `resourceGroups` module once per item, scoped to the correct subscription.
- **Imports:** `helpers/types.bicep` for the `resourceGroup` type used in the parameter declaration.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `resourceGroups` | `resourceGroup[]` | Array of resource group definitions to deploy |

**Key behaviour:** Each module deployment is scoped to `az.subscription(resourceGroup.subscriptionId)`, which means a single deployment can create resource groups across multiple subscriptions simultaneously.

## Parameters File

### `main.bicepparam`

Defines the concrete values passed to `main.bicep`. Uses the `helpers/variables.bicep` imports for consistent naming and location references.

**Project configuration variables (local to the params file):**

| Variable | Value | Purpose |
|----------|-------|---------|
| `project.description` | `AI Powered FinOps and SecOps` | Human-readable description, applied as tag |
| `project.environment` | `prd` | Environment identifier, used in naming and tags |
| `project.location` | `swedencentral` | Primary Azure region |
| `project.name` | `AI powered ops` | Full project name, applied as tag |
| `project.shortName` | `aiops` | Abbreviated name used in resource naming |

**Resource suffix pattern:** `<shortName>-<environment>-<regionShortName>`
- Example: `aiops-prd-swc`

**Deployed resource groups:**

| Resource group name | Subscription ID | Location |
|---------------------|-----------------|----------|
| `rg-aiops-prd-swc-001` | `a525b25c-14fc-42cb-a55f-9dedea6bffaa` | `swedencentral` |

**Tags applied to all resources:**

| Tag | Value |
|-----|-------|
| `description` | `AI Powered FinOps and SecOps` |
| `environment` | `prd` |
| `project` | `AI powered ops` |

## Helpers

### `helpers/types.bicep`

Defines and exports shared custom types used across the Bicep files.

#### `resourceGroup` (exported)

```bicep
type resourceGroup = {
  location: string?           // Azure region (optional — defaults to deployment scope)
  name: string                // Resource group name (required)
  roleAssignments: roleAssignment[]?   // Optional RBAC assignments
  subscriptionId: string      // Target subscription ID (required)
  tags: object?               // Resource tags (optional)
}
```

#### `roleAssignment` (internal)

```bicep
type roleAssignment = {
  principalId: string
  principalType: 'Device' | 'ForeignGroup' | 'Group' | 'ServicePrincipal' | 'User'
  roleDefinitionIdOrName: string   // Can be a GUID or a built-in role name
}
```

### `helpers/variables.bicep`

Defines and exports shared constants used across Bicep files and the parameters file.

#### `regions` (exported)

Maps region names to a structured object with `location` (ARM value) and `shortName` (used in resource naming):

| Key | `location` | `shortName` |
|-----|-----------|-------------|
| `francecentral` | `francecentral` | `frc` |
| `germanywestcentral` | `germanywestcentral` | `gwc` |
| `northeurope` | `northeurope` | `neu` |
| `swedencentral` | `swedencentral` | `swc` |
| `westeurope` | `westeurope` | `weu` |

Usage example: `v.regions.swedencentral.location` → `'swedencentral'`

#### `roleDefinitionId` (exported)

Maps friendly names to Azure built-in role definition GUIDs:

| Key | GUID |
|-----|------|
| `CostManagementReaderRoleId` | `72fafb9e-0641-4937-9268-a91bfd8191a3` |
| `ReaderRoleId` | `acdd72a7-3385-48ef-bd42-f606fba81ae7` |
| `SecurityReaderRoleId` | `39bc4728-0917-49c7-9d2c-d95423bc2eb4` |
| `StorageBlobDataContributor` | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` |
| `StorageBlobDataOwner` | `b7e6dc6d-f1e8-4753-8033-0f276bb0955b` |
| `StorageBlobDataReader` | `2a2b9908-6ea1-4ae2-8e65-a410df84e7d1` |

These GUIDs should be passed as `roleDefinitionIdOrName` in `roleAssignment` objects.

## Modules

### `modules/resourceGroups.bicep`

- **Scope:** `subscription`
- **Purpose:** Deploys one or more resource groups using the [Azure Verified Modules (AVM)](https://aka.ms/avm) public registry module `avm/res/resources/resource-group` at version `0.4.3`.
- **Imports:** `helpers/types.bicep`

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `resourceGroups` | `resourceGroup[]` | Array of resource group definitions |

**Deployment loop:** Creates one deployment per element in the `resourceGroups` array. Deployment names are prefixed `deploy-<resource-group-name>` to avoid naming collisions.

**AVM module settings:**
- `enableTelemetry: true` — Microsoft AVM telemetry enabled (standard AVM default)
- All optional fields (`location`, `roleAssignments`, `tags`) use the `?` safe-access operator, so they are only passed if present

**Outputs:**

| Output | Type | Description |
|--------|------|-------------|
| `resourceGroups` | `array` | Array of objects containing `index`, `location`, `name`, and `resourceId` for each deployed resource group |

## Conventions

- **Resource naming pattern:** `<resource-type>-<shortName>-<environment>-<regionShortName>-<instance>`, e.g. `rg-aiops-prd-swc-001`
- **Region references:** Always use `v.regions.<key>.location` (not hardcoded strings) to stay consistent with the `shortName` used in naming
- **Role assignments:** Always reference `v.roleDefinitionId.<key>` for built-in roles rather than hardcoding GUIDs
- **Optional parameters:** Use the `?` safe-access operator (`resourceGroup.?location`) for all optional fields passed to AVM modules
- **AVM modules:** Resource modules are sourced from the public AVM Bicep registry (`br/public:avm/...`) with pinned versions

## Deployment

To deploy the infrastructure from the parameters file:

```bash
az deployment sub create \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

Or using PowerShell:

```powershell
New-AzSubscriptionDeployment `
  -Location swedencentral `
  -TemplateFile infra/main.bicep `
  -TemplateParameterFile infra/main.bicepparam
```

To validate (compile) without deploying:

```bash
az bicep build --file infra/main.bicep
az bicep build-params --file infra/main.bicepparam
```

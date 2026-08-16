# Infrastructure Guide

## Overview

Infrastructure is defined under `infra/` and deployed at **subscription scope** via `main.bicep`. The template creates/uses a primary resource group and deploys platform resources through four modules:

1. `supporting_resources.bicep`
2. `function-app_resources.bicep`
3. `foundry_resources.bicep`
4. `web_frontend_resources.bicep`

A fifth module, `event_grids.bicep`, is maintained in `infra/modules/` and deployed separately by workflow (`deploy-event-grids.yml`) after the Function App exists — its destination references a specific function by name, so it fails with "Destination endpoint not found" if the function code hasn't been deployed yet.

## Folder structure

```text
infra/
├── main.bicep
├── main.bicepparam
├── helpers/
│   ├── types.bicep
│   └── variables.bicep
└── modules/
    ├── event_grids.bicep
    ├── supporting_resources.bicep
    ├── function-app_resources.bicep
    ├── foundry_resources.bicep
    └── web_frontend_resources.bicep
```

## Deployment flow

### `main.bicep`

- `targetScope = 'subscription'`
- Deploys resource groups via AVM (`avm/res/resources/resource-group:0.4.3`)
- Then deploys, in dependency order inferred from output references (not explicit `dependsOn` except where noted):
  - supporting resources (`sr`)
  - foundry resources (`fr`) — depends on `sr` for the user-assigned identity's `principalId`
  - function app resources (`far`) — depends on `sr` and `fr` (needs the Foundry project endpoint)
  - web frontend resources (`wfr`) — depends on `far` (needs the Function App's resource ID for the linked backend)

The function module consumes outputs from supporting resources and foundry resources:
- Application Insights resource ID
- two storage account resource IDs
- user-assigned identity resource ID
- virtual network subnet resource ID
- Foundry project endpoint (constructed from the account and project names)

The web frontend module consumes the Function App's resource ID as its linked backend.

### Top-level outputs

`main.bicep` outputs three resource names, surfaced by `deploy-azure-resources.yml` as a `::notice::` annotation after each deploy (not auto-written to repository variables — see `docs/workflows.md` for why):

- `functionAppName`
- `dataStorageAccountName`
- `staticWebAppName`

## Parameters and naming (`main.bicepparam`)

### Project constants

- `project.shortName = aiops`
- `project.environment` — e.g. `prd` or `dev`; multiple environments can coexist side by side since every resource name derives from this value
- `project.location = westeurope`

### Subscription resolution

`subscriptionId` is sourced from environment variable `AZURE_SUBSCRIPTION_ID` with a fallback default.

### Resource naming

- Standard pattern: `<type>-<shortName>-<environment>-<regionShortName>-<instance>`
- Private storage: `stv2<suffix>001`
- Public/system storage: `stv2<suffix>002`
- Storage and Key Vault names are truncated/adjusted as needed to satisfy platform length limits.

### Current configured resources (for `project.environment = prd`)

- Resource group: `rg-aiops-prd-weu-001`
- App Insights: `appi-aiops-prd-weu-001`
- Log Analytics: `log-aiops-prd-weu-001`
- NSG: `nsg-aiops-prd-weu-001`
- VNet: `vnet-aiops-prd-weu-001`
- Function App: `func-aiops-prd-weu-001`
- App Service plan: `asp-aiops-prd-weu-001` (Flex Consumption, `FC1`)
- Identity: `id-aiops-prd-weu-001`
- AI Foundry account: `fa-aiops-prd-weu-001`
- AI Foundry project: `proj-aiops-prd-weu-001`
- Key Vault: `kv-aiops-prd-weu-001`
- Static Web App: `stapp-aiops-prd-weu-001` (Standard tier)

The deployed Foundry account currently includes two model deployments:

- `gpt-5.1` (`GlobalStandard`, capacity 10)
- `gpt-5-mini` (`GlobalStandard`, capacity 20)

### Storage account intent

`storageAccounts` is an array with two entries:

1. **Data storage** (`...001`)
   - containers: `focus-exports`, `normalized`
   - network ACL default deny + VNet rule for the `FunctionApps` subnet
2. **System/package storage** (`...002`)
   - container: `app-packages`
   - network ACL default allow

### Foundry role assignments

`foundryAccount.aiFoundryConfiguration.roleAssignments` grants `FoundryUserRoleId` (the role that covers both agent management and runtime invocation) to two principals, at the **Foundry account scope** — not the project scope, which is a real, easy-to-hit mistake since RBAC assignments made from the project blade in the Portal can land at the narrower project scope instead:

1. The Function App's user-assigned identity — wired automatically as a module output (`sr.outputs.userAssignedIdentity.principalId`), not a manually-pasted value, since it's created in this same deployment.
2. The CI/CD identity (the one GitHub Actions authenticates as via OIDC) — this one genuinely can't be automated the same way, since it's created by `bootstrap.sh`, a separate process this template has no visibility into. Still a manually-pasted `principalId` in `main.bicepparam`.

### Key Vault role assignments

`keyVault.roleAssignments` grants `KeyVaultSecretsOfficerRoleId` (write access, needed to populate the secret) to your own account — also a manually-pasted value, since it's an external identity Bicep can't discover. The Static Web App's own system-assigned identity is granted `KeyVaultSecretsUserRoleId` (read-only) automatically, in-module, for the same reason as the Foundry grant above.

**The Key Vault's network access is deliberately set to allow all networks.** This isn't an oversight — Key Vault references (the `@Microsoft.KeyVault(...)` syntax used in the Static Web App's app settings) cannot resolve secrets from a network-restricted vault when the calling app is a Static Web App. Microsoft's documentation describes a workaround (VNet integration + vault network rules) for App Service and Azure Functions, but it doesn't extend to Static Web Apps — confirmed by direct, repeated testing, not assumption. RBAC (the two grants above) is the real access control for this vault.

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

Note: a NAT Gateway was provisioned here at one point to solve a `Sync Web Apps Function Triggers: Forbidden` error caused by `outboundVnetRouting.allTraffic: true` routing platform-internal calls through the VNet subnet with no reliable egress. It was later removed after directly testing (via Activity Log and Sentinel query, both showing zero occurrences of the error over an extended window) that it was no longer needed — the real root cause of the broader "0 functions found" saga turned out to be unrelated (see `docs/function-app.md`), and the NAT Gateway's ~$35-40/month cost wasn't buying anything once that was fixed.

Security/constraints on storage:
- `allowBlobPublicAccess: false`
- `allowSharedKeyAccess: false`
- `allowCrossTenantReplication: false`
- `minimumTlsVersion: TLS1_2`
- `supportsHttpsTrafficOnly: true`
- `requireInfrastructureEncryption: true`

Role assignments for each storage account are bound to the deployed managed identity principal.

Output includes `principalId` for the user-assigned identity, enabling other modules (Foundry) to grant it roles without a manually-pasted GUID.

### `modules/function-app_resources.bicep`

Deploys:
- Linux App Service plan (`FC1`, Flex Consumption)
- Function App (`kind: functionapp,linux`)

Function app wiring:
- Uses user-assigned identity only (`systemAssigned: false`)
- `AzureWebJobsStorage__*` points to **system storage** account
- `DataStorage__*` points to **data storage** account
- `FOUNDRY_PROJECT_ENDPOINT` — the Foundry project's OpenAI-compatible endpoint, needed by `ChatWithAgent` to construct an `AIProjectClient`
- Deployment package source: `https://<system-storage>.blob.<suffix>/app-packages`
- Runtime: Python `3.12`
- VNet integration via `virtualNetworkSubnetResourceId`, outbound VNet routing enabled (`allTraffic: true`) — needed for the data storage account's VNet-rule-based firewall exception
- HTTPS only

Output includes the Function App's `resourceId`, consumed by `web_frontend_resources.bicep` as the linked backend target.

### `modules/foundry_resources.bicep`

Deploys AI Foundry via AVM pattern module `avm/ptn/ai-ml/ai-foundry:0.7.0`. Takes the Function App's user-assigned identity `principalId` as a standalone parameter (not bundled into the `foundryAccount` type) so it can be wired as a module output rather than requiring a manually-pasted value — the CI/CD identity's grant still comes through `foundryAccount.aiFoundryConfiguration.roleAssignments` in `main.bicepparam`, since that identity is external to this deployment.

**Also connects the existing Application Insights resource (from `supporting_resources.bicep`) to the Foundry account**, via a `Microsoft.CognitiveServices/accounts/connections` child resource (`category: AppInsights`). Reuses the existing resource rather than provisioning a second one — App Insights holds multiple distinct telemetry streams in separate tables without issue. Both the App Insights resource and the Foundry account are declared `existing` here (even though the account is created moments earlier in this same module) since the AVM pattern module doesn't expose a way to attach this connection as a parameter — an explicit `dependsOn` is required as a result, since `existing` declarations don't create an implicit ordering dependency the way referencing a module output does. The connection string is read directly from the existing resource's own properties and never passed through a module output or `.bicepparam` value.

Server-side agent tracing activates automatically the moment this connection exists — confirmed working via real trace data in Application Insights, including Foundry's own hosting details (compute platform, cluster name) that weren't configured by anything in this repo.

**The connection alone isn't sufficient for the Foundry portal to display traces** — a Foundry *project* has its own distinct managed identity (separate from the account's, and not exposed by the AVM module's own outputs — obtained here via an `existing` reference to the project sub-resource and reading `.identity.principalId` directly). That identity needs `Reader` on the App Insights resource specifically, granted via a `Microsoft.Authorization/roleAssignments` resource scoped to the App Insights resource itself, not this module's default resource-group scope. Without this grant, the Foundry portal shows "Setup incomplete: Assign the Foundry project's managed identity the Reader role on Application Insights to access traces" even though the connection itself shows as successfully "Connected."

### `modules/multi_subscription_role_assignments.bicep`

Grants a single role, individually, across each subscription in a list — a generalized, reusable module rather than a role-specific one. `main.bicep` invokes it twice, once per role, both passing the same `familieZuidingaSubscriptionIds` (`main.bicepparam`):

- `SecurityReaderRoleId` — needed for `GetSecurityRecommendations`'s Resource Graph query.
- `ReaderRoleId` — needed for `GetAdvisorRecommendations`'s Resource Graph query. Advisor recommendations specifically require access to the resource each one is about, not just a subscription-wide security-posture role, per Advisor's own permissions documentation.

(See `docs/agents.md` and `docs/function-app.md` for what each tool actually does with this access.)

Originally written as a security-specific module (`security_reader_role_assignments.bicep`) and generalized when the Advisor grant needed the identical pattern with a different role — rather than duplicating a near-copy of the same module, `roleDefinitionId` became a parameter instead of a hardcoded constant.

**Deliberately four separate subscription-scoped role assignments per role, not one management-group-scoped assignment**, even though all four subscriptions sit under a single management group (`Familie Zuidinga`) that would make one assignment look simpler. A subscription-scoped deployment (which `main.bicep` is) can only reach *downward* in the scope hierarchy — to subscriptions or resource groups at or below its own scope — not upward to a parent management group. Every documented example of cross-scope Bicep deployment goes downward from wherever the outermost deployment command is anchored; there's no example anywhere of a subscription deploying up to a management group, and the AVM role-assignment module is correspondingly split into separate `mg-scope`, `rg-scope`, and `sub-scope` variants rather than one unified module. This module uses the `sub-scope` variant, once per subscription per role, in a loop.

### `modules/web_frontend_resources.bicep`

Deploys:
- Key Vault (`br/public:avm/res/key-vault/vault:0.14.0`), network access open (see above), RBAC-authorized
- Static Web App (`br/public:avm/res/web/static-site:0.9.5`), Standard tier, with:
  - a linked backend pointing at the Function App (takes `linkedBackendResourceId` as a standalone parameter, populated from `far.outputs.functionApp.resourceId` — same pattern as the Foundry identity wiring, for the same reason: the value only exists once the Function App module has run)
  - a system-assigned identity, granted `KeyVaultSecretsUserRoleId` on the Key Vault automatically, in-module

Linking a "bring your own" backend to a Static Web App automatically configures App Service Authentication on the Function App itself (an identity provider named "Azure Static Web Apps (Linked)") — this is what actually prevents the Function App's own direct URL from being reachable without going through the SWA's authenticated proxy, confirmed by testing (navigating directly to the Function App's URL returns `Login not supported for provider azureStaticWebApps` rather than succeeding).

### `modules/event_grids.bicep`

Resource-group scoped module that wires blob-created events from the data storage account to the Function App:

- Creates an Event Grid **system topic** for the storage account
- Creates an Event Grid **event subscription** that:
  - routes to the specific function `BlobCreatedEventGridFunction` (the destination `resourceId` must include `/functions/<name>` — pointing at just the site returns "Destination endpoint not found")
  - filters to container path prefix `/blobServices/default/containers/focus-exports/blobs/`
  - filters to `.parquet` blobs
  - uses retry policy (`maxDeliveryAttempts: 30`, TTL 1440 minutes)

## Shared helpers

### `helpers/types.bicep`

Defines exported types for:
- `applicationInsights`
- `foundryAccount`
- `functionApp`
- `keyVault`
- `logAnalyticsWorkspace`
- `networkSecurityGroup`
- `networkWatcher`
- `resourceGroup`
- `serverFarm`
- `staticWebApp`
- `storageAccount`
- `userAssignedIdentity`
- `virtualNetwork`

Notable conventions:
- Role assignments use `roleDefinitionId`
- Storage supports ACLs, blob containers, and role assignment arrays
- Values that are only knowable as another module's output (a linked backend's resource ID, an identity's `principalId`) are deliberately *not* bundled into these shared types — they're passed as standalone module parameters instead, so `.bicepparam` is never asked to supply something it structurally can't know

### `helpers/variables.bicep`

- Region map with short names (e.g., `swedencentral -> swc`)
- Role definition ID constants:
  - `FoundryUserRoleId`
  - `KeyVaultSecretsOfficerRoleId`
  - `KeyVaultSecretsUserRoleId`
  - `ReaderRoleId`
  - `SecurityReaderRoleId`
  - `StorageBlobDataOwner`
  - `StorageBlobDataContributor`
  - `StorageBlobDataReader`
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

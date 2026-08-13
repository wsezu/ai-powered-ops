targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'
import * as variable from '../helpers/variables.bicep'

param foundryAccount type.foundryAccount
param functionAppUserAssignedIdentityPrincipalId string
param applicationInsightsResourceId string

var additionalFoundryRoleAssignments = [for ra in (foundryAccount.?aiFoundryConfiguration.?roleAssignments ?? []): {
  principalId: ra.principalId
  principalType: ra.?principalType
  roleDefinitionIdOrName: ra.roleDefinitionId
}]

module aif 'br/public:avm/ptn/ai-ml/ai-foundry:0.7.0' = {
  name: 'deploy-${foundryAccount.baseName}'
  params: {
    aiFoundryConfiguration: {
      accountName: foundryAccount.?aiFoundryConfiguration.?accountName
      allowProjectManagement: foundryAccount.?aiFoundryConfiguration.?allowProjectManagement
      project: foundryAccount.?aiFoundryConfiguration.?project
      roleAssignments: concat(
        [
          {
            // The Function App's own user-assigned identity — needed so the
            // ChatWithAgent endpoint can invoke the agent at runtime. Always
            // granted; not sourced from bicepparam, since this identity is
            // created in this same deployment and its principalId is only
            // knowable as a module output, not something to hand-copy.
            principalId: functionAppUserAssignedIdentityPrincipalId
            principalType: 'ServicePrincipal'
            roleDefinitionIdOrName: variable.roleDefinitionId.FoundryUserRoleId
          }
        ],
        additionalFoundryRoleAssignments
      )
      sku: foundryAccount.?aiFoundryConfiguration.?sku
    }
    aiModelDeployments: foundryAccount.?aiModelDeployments
    baseName: foundryAccount.baseName
    location: foundryAccount.?location
    tags: foundryAccount.?tags
  }
}

// Reuses the App Insights resource already created in supporting_resources.bicep
// (the same one the Function App logs to) rather than provisioning a second one —
// App Insights holds multiple distinct telemetry streams in separate tables just
// fine. Declared `existing` by name since the AVM Foundry pattern module doesn't
// expose a parameter for adding this connection, so it has to be attached directly.
resource existingAppInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: last(split(applicationInsightsResourceId, '/'))
}

// Also declared `existing`, even though `aif` creates it moments earlier in this
// same deployment — the AVM module doesn't output a usable child-resource handle,
// so this is the only way to attach a connections/ sub-resource to it. `existing`
// declarations don't create an implicit dependency the way referencing a module
// output does, so the explicit dependsOn below is required, not optional.
resource existingFoundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccount.?aiFoundryConfiguration.?accountName!
}

// Server-side agent tracing activates automatically the moment this connection
// exists — no code changes anywhere, confirmed specifically for prompt agents
// (which cost-efficiency-advisor is). The connection string is read directly from
// the existing resource's own properties, never passed through a module output or
// bicepparam value.
resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  name: '${foundryAccount.?aiFoundryConfiguration.?accountName}-appinsights'
  parent: existingFoundryAccount
  properties: {
    category: 'AppInsights'
    target: existingAppInsights.id
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: existingAppInsights.properties.ConnectionString
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: existingAppInsights.id
    }
  }
  dependsOn: [
    aif
  ]
}

output foundry object = {
  project: {
    endpoint: 'https://${foundryAccount.?aiFoundryConfiguration.?accountName}.services.ai.azure.com/api/projects/${aif.outputs.aiProjectName}'
  }
}

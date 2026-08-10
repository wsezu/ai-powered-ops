targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'
import * as variable from '../helpers/variables.bicep'

param foundryAccount type.foundryAccount
param functionAppUserAssignedIdentityPrincipalId string

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

output foundry object = {
  project: {
    endpoint: 'https://${foundryAccount.?aiFoundryConfiguration.?accountName}.services.ai.azure.com/api/projects/${aif.outputs.aiProjectName}'
  }
}

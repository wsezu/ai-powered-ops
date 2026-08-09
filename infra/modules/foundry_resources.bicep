targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'

param foundryAccount type.foundryAccount

module aif 'br/public:avm/ptn/ai-ml/ai-foundry:0.7.0' = {
  name: 'deploy-${foundryAccount.baseName}'
  params: {
    aiFoundryConfiguration: {
      accountName: foundryAccount.?aiFoundryConfiguration.?accountName
      allowProjectManagement: foundryAccount.?aiFoundryConfiguration.?allowProjectManagement
      project: foundryAccount.?aiFoundryConfiguration.?project
      roleAssignments: [for ra in (foundryAccount.?aiFoundryConfiguration.?roleAssignments ?? []): {
        principalId: ra.principalId
        principalType: ra.?principalType
        roleDefinitionIdOrName: ra.roleDefinitionId
      }]
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

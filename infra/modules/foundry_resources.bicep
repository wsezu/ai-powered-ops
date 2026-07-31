targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'

param foundryAccount type.foundryAccount

module aif 'br/public:avm/ptn/ai-ml/ai-foundry:0.7.0' = {
  name: 'deploy-${foundryAccount.baseName}'
  params: {
    aiFoundryConfiguration: foundryAccount.?aiFoundryConfiguration
    aiModelDeployments: foundryAccount.?aiModelDeployments
    baseName: foundryAccount.baseName
    location: foundryAccount.?location
    tags: foundryAccount.?tags
  }
}

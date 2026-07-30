targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'

param applicationInsights type.applicationInsights[]

module appis 'br/public:avm/res/insights/component:0.8.0' = [for applicationInsight in applicationInsights: {
  name: 'deploy-${applicationInsight.name}'
  params: {
    enableTelemetry: true
    location: applicationInsight.location
    name: applicationInsight.name
    roleAssignments: applicationInsight.?roleAssignments
    tags: applicationInsight.?tags
    workspaceResourceId: applicationInsight.workspaceResourceId
  }
}]

output applicationInsightNames array = [for (applicationInsight, i) in applicationInsights: {
  index: i
  name: appis[i].outputs.name
  resourceId: appis[i].outputs.resourceId
}]

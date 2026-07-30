targetScope = 'subscription'

import * as type from '../helpers/types.bicep'

param resourceGroups type.resourceGroup[]

module rgs 'br/public:avm/res/resources/resource-group:0.4.3' = [for resourceGroup in resourceGroups: {
  name: 'deploy-${resourceGroup.name}'
  params: {
    enableTelemetry: true
    location: resourceGroup.?location
    name: resourceGroup.name
    roleAssignments: resourceGroup.?roleAssignments
    tags: resourceGroup.?tags
  }
}]

output resourceGroups array = [for (resourceGroup, i) in resourceGroups: {
  index: i
  location: rgs[i].outputs.location
  name: rgs[i].outputs.name
  resourceId: rgs[i].outputs.resourceId
}]

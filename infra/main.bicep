targetScope = 'subscription'

import * as type from 'helpers/types.bicep'

param resourceGroups type.resourceGroup[]

module rgs 'modules/resourceGroups.bicep' = [for resourceGroup in resourceGroups: {
  name: 'deploy-resource-groups'
  params: {
    resourceGroups: resourceGroups
  }
  scope: az.subscription(resourceGroup.subscriptionId)
}]

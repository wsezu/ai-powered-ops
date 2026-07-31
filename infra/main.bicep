targetScope = 'subscription'

import * as type from 'helpers/types.bicep'

param applicationInsights type.applicationInsights
param foundryAccount type.foundryAccount
param logAnalyticsWorkspace type.logAnalyticsWorkspace
param resourceGroups type.resourceGroup[]
param storageAccount type.storageAccount
param userAssignedIdentity type.userAssignedIdentity

module rgs 'br/public:avm/res/resources/resource-group:0.4.3' = [for resourceGroup in resourceGroups: {
  name: 'deploy-${resourceGroup.name}'
  params: {
    enableTelemetry: true
    location: resourceGroup.?location
    name: resourceGroup.name
    tags: resourceGroup.?tags
  }
  scope: az.subscription(resourceGroup.subscriptionId)
}]

module sr 'modules/supporting_resources.bicep' = {
  dependsOn: [ rgs ]
  name: 'deploy-supporting-resources'
  params: {
    applicationInsights: applicationInsights
    logAnalticsWorkspace: logAnalyticsWorkspace
    storageAccount: storageAccount
    userAssignedIdentity: userAssignedIdentity
  }
  scope: az.resourceGroup(resourceGroups[0].name)
}

module fr 'modules/foundry_resources.bicep' = {
  dependsOn: [ sr ]
  name: 'deploy-foundry-resources'
  params: {
    foundryAccount: foundryAccount
  }
  scope: az.resourceGroup(resourceGroups[0].name)
}

targetScope = 'subscription'

import * as type from 'helpers/types.bicep'

param applicationInsights type.applicationInsights
param foundryAccount type.foundryAccount
param functionApp type.functionApp
param keyVault type.keyVault
param logAnalyticsWorkspace type.logAnalyticsWorkspace
param networkSecurityGroup type.networkSecurityGroup
param resourceGroups type.resourceGroup[]
param serverFarm type.serverFarm
param staticWebApp type.staticWebApp
param storageAccounts type.storageAccount[]
param userAssignedIdentity type.userAssignedIdentity
param virtualNetwork type.virtualNetwork

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
    networkSecurityGroup: networkSecurityGroup
    networkWatcher: {
      deploy: false
      name: ''
    }
    storageAccounts: storageAccounts
    userAssignedIdentity: userAssignedIdentity
    virtualNetwork: virtualNetwork
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

module far 'modules/function-app_resources.bicep' = {
  dependsOn: [ rgs ]
  name: 'deploy-function-app-resources'
  params: {
    applicationInsightsResourceId: sr.outputs.applicationInsights.resourceId
    dataStorageAccountResourceId: sr.outputs.storageAccounts[0].resourceId
    foundryProjectEndpoint: fr.outputs.foundry.project.endpoint
    functionApp: functionApp
    serverFarm: serverFarm
    systemStorageAccountResourceId: sr.outputs.storageAccounts[1].resourceId
    userAssignedIdentityResourceId: sr.outputs.userAssignedIdentity.resourceId
    virtualNetworkSubnetResourceId: sr.outputs.virtualNetwork.subnetResourceIds[0]
  }
  scope: az.resourceGroup(resourceGroups[0].name)
}

module wfr 'modules/web_frontend_resources.bicep' = {
  name: 'deploy-web-frontend-resources'
  params: {
    keyVault: keyVault
    linkedBackendResourceId: far.outputs.functionApp.resourceId
    staticWebApp: staticWebApp
  }
  scope: az.resourceGroup(resourceGroups[0].name)
}

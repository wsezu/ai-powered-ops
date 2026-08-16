targetScope = 'subscription'

import * as type from 'helpers/types.bicep'
import * as variable from 'helpers/variables.bicep'

param applicationInsights type.applicationInsights
param foundryAccount type.foundryAccount
param functionApp type.functionApp
param keyVault type.keyVault
param logAnalyticsWorkspace type.logAnalyticsWorkspace
param networkSecurityGroup type.networkSecurityGroup
param resourceGroups type.resourceGroup[]
param familieZuidingaSubscriptionIds string[]
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
  name: 'deploy-foundry-resources'
  params: {
    applicationInsightsResourceId: sr.outputs.applicationInsights.resourceId
    foundryAccount: foundryAccount
    functionAppUserAssignedIdentityPrincipalId: sr.outputs.userAssignedIdentity.principalId
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

module srra 'modules/multi_subscription_role_assignments.bicep' = {
  name: 'deploy-security-reader-role-assignments'
  params: {
    principalId: sr.outputs.userAssignedIdentity.principalId
    roleDefinitionId: variable.roleDefinitionId.SecurityReaderRoleId
    subscriptionIds: familieZuidingaSubscriptionIds
  }
}

module arra 'modules/multi_subscription_role_assignments.bicep' = {
  name: 'deploy-advisor-reader-role-assignments'
  params: {
    principalId: sr.outputs.userAssignedIdentity.principalId
    roleDefinitionId: variable.roleDefinitionId.ReaderRoleId
    subscriptionIds: familieZuidingaSubscriptionIds
  }
}

output dataStorageAccountName string = sr.outputs.storageAccounts[0].name
output foundryProjectEndpoint string = fr.outputs.foundry.project.endpoint
output functionAppName string = far.outputs.functionApp.name
output staticWebAppName string = wfr.outputs.staticWebApp.name

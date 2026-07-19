targetScope = 'subscription'

import * as t from 'helpers/types.bicep'

param applicationInsights t.applicationInsights[]
param foundryAccounts t.foundryAccount[]
param foundryProjects t.foundryProject[]
param functionApps t.functionApp[]
param logAnalyticsWorkspaces t.logAnalyticsWorkspace[]
param resourceGroups t.resourceGroup[]

module rgs 'br/public:avm/res/resources/resource-group:0.4.3' = [for rg in resourceGroups: {
  name: 'deploy_${rg.name}'
  params: {
    enableTelemetry: true
    location: rg.location
    name: rg.name
    tags: rg.?tags
  }
}]

module laws 'br/public:avm/res/operational-insights/workspace:0.15.1' = [for law in logAnalyticsWorkspaces: {
  dependsOn: [ rgs ]
  name: 'deploy_${law.name}'
  params: {
    dataRetention: law.dataRetention
    enableTelemetry: true
    location: law.location
    name: law.name
    skuName: law.skuName
    tags: law.?tags
  }
  scope: az.resourceGroup(law.resourceGroupName)
}]

module appis 'br/public:avm/res/insights/component:0.7.2' = [for ai in applicationInsights: {
  dependsOn: [ laws, rgs ]
  name: 'deploy_${ai.name}'
  params: {
    applicationType: ai.applicationType
    enableTelemetry: true
    flowType: ai.flowType
    ingestionMode: ai.ingestionMode
    kind: ai.kind
    location: ai.location
    name: ai.name
    retentionInDays: ai.retentionInDays
    tags: ai.?tags
    workspaceResourceId: laws[0].outputs.resourceId
  }
  scope: az.resourceGroup(ai.resourceGroupName)
}]

module fas 'br/public:avm/res/cognitive-services/account:0.15.0' = [for fa in foundryAccounts: {
  dependsOn: [ rgs ]
  name: 'deploy_${fa.name}'
  params: {
    allowProjectManagement: true
    customSubDomainName: toLower(fa.name)
    deployments: fa.?deployments
    disableLocalAuth: true
    dynamicThrottlingEnabled: true
    enableTelemetry: true
    kind: fa.kind
    location: fa.location
    managedIdentities: {
      systemAssigned: true
    }
    name: fa.name
    publicNetworkAccess: fa.publicNetworkAccess ? 'Enabled' : 'Disabled'
    sku: fa.sku
    tags: fa.?tags
  }
  scope: az.resourceGroup(fa.resourceGroupName)
}]

module fps 'modules/foundry-project.bicep' = [for fp in foundryProjects: {
  dependsOn: [ rgs, fas ]
  name: 'deploy_${fp.name}'
  params: {
    location: fp.location
    foundryAccountName: fp.parent
    foundryProjectName: fp.name
  }
  scope: az.resourceGroup(fp.resourceGroupName)
}]

module fus 'modules/function-app.bicep' = [for fu in functionApps: {
  name: 'deploy_function-apps'
  params: {
    applicationInsightsConnectionString: appis[0].outputs.connectionString
    applicationInsightsInstrumentationKey: appis[0].outputs.instrumentationKey
    name: fu.name
  }
  scope: az.resourceGroup(fu.resourceGroupName)
}]

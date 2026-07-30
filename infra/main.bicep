targetScope = 'subscription'

import * as type from 'helpers/types.bicep'

param logAnalyticsWorkspaces type.logAnalyticsWorkspace[]
param resourceGroups type.resourceGroup[]

module rgs 'modules/resourceGroups.bicep' = [for resourceGroup in resourceGroups: {
  name: 'deploy-resource-groups'
  params: {
    resourceGroups: resourceGroups
  }
  scope: az.subscription(resourceGroup.subscriptionId)
}]

module laws 'modules/logAnalyticsWorkspaces.bicep' = [for logAnalyticsWorkspace in logAnalyticsWorkspaces: {
  name: 'deploy-log-analytics-workspaces'
  params: {
    logAnalyticsWorkspaces: logAnalyticsWorkspaces
  }
  scope: az.resourceGroup(logAnalyticsWorkspace.resourceGroupName)
}]

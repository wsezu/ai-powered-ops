targetScope = 'subscription'

import * as type from 'helpers/types.bicep'

param applicationInsights type.applicationInsights[]
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

module appis 'modules/applicationInsights.bicep' = [for applicationInsight in applicationInsights: {
  name: 'deploy-application-insights'
  params: {
    applicationInsights: [
      {
        location: applicationInsight.location
        name: applicationInsight.name
        roleAssignments: applicationInsight.?roleAssignments
        tags: applicationInsight.?tags
        workspaceResourceId: laws[0].outputs.logAnalyticsWorkspaces.resourceId
      }
    ]
  }
  scope: az.resourceGroup(applicationInsight.resourceGroupName)
}]

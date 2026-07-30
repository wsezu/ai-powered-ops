targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'

param logAnalyticsWorkspaces type.logAnalyticsWorkspace[]

module laws 'br/public:avm/res/operational-insights/workspace:0.16.0' = [for logAnalyticsWorkspace in logAnalyticsWorkspaces: {
  name: 'deploy-${logAnalyticsWorkspace.name}'
  params: {
    dataRetention: logAnalyticsWorkspace.?dataRetention
    location: logAnalyticsWorkspace.?location
    name: logAnalyticsWorkspace.name
    publicNetworkAccessForIngestion: logAnalyticsWorkspace.?publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: logAnalyticsWorkspace.?publicNetworkAccessForQuery
    roleAssignments: logAnalyticsWorkspace.?roleAssignments
    skuName: logAnalyticsWorkspace.?skuName
    tags: logAnalyticsWorkspace.?tags
  }
}]

output logAnalyticsWorkspaces array = [for (logAnalyticsWorkspace, i) in logAnalyticsWorkspaces: {
  index: i
  name: laws[i].outputs.name
  resourceId: laws[i].outputs.resourceId
}]

targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'

param applicationInsights type.applicationInsights
param logAnalticsWorkspace type.logAnalyticsWorkspace

module log 'br/public:avm/res/operational-insights/workspace:0.16.0' = {
  name: 'deploy-${logAnalticsWorkspace.name}'
  params: {
    dataRetention: logAnalticsWorkspace.?dataRetention
    enableTelemetry: true
    location: resourceGroup().location
    name: logAnalticsWorkspace.name
    skuName: logAnalticsWorkspace.?skuName
    tags: logAnalticsWorkspace.?tags
  }
}

module appi 'br/public:avm/res/insights/component:0.8.0' = {
  name: 'deploy-${applicationInsights.name}'
  params: {
    enableTelemetry: true
    location: resourceGroup().location
    name: applicationInsights.name
    tags: applicationInsights.?tags
    workspaceResourceId: log.outputs.resourceId
  }
}

output applicationInsights object = { name: appi.outputs.name,  resourceId: appi.outputs.resourceId}
output logAnalyticsWorkspace object = { name: log.outputs.name, resourceId: log.outputs.resourceId}

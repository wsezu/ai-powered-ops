targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'
import * as variable from '../helpers/variables.bicep'

param applicationInsights type.applicationInsights
param logAnalticsWorkspace type.logAnalyticsWorkspace
param storageAccount type.storageAccount
param userAssignedIdentity type.userAssignedIdentity

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

module id 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'deploy-${userAssignedIdentity.name}'
  params: {
    enableTelemetry: true
    location: resourceGroup().location
    name: userAssignedIdentity.name
    tags: userAssignedIdentity.?tags
  }
}

module st 'br/public:avm/res/storage/storage-account:0.33.0' = {
  name: 'deploy-${storageAccount.name}'
  params: {
    accessTier: storageAccount.?accessTier
    allowBlobPublicAccess: true
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    blobServices: {
      containers: [
        {
          name: 'app-packages'
        }
        {
          name: 'focus-exports'
        }
        {
          name: 'normalized'
        }
      ]
    }
    enableTelemetry: true
    kind: storageAccount.?kind
    location: resourceGroup().location
    minimumTlsVersion: 'TLS1_2'
    name: storageAccount.name
    publicNetworkAccess: 'Enabled'
    requireInfrastructureEncryption: true
    roleAssignments: [
      {
        principalId: id.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: variable.roleDefinitionId.StorageBlobDataContributor
      }
      {
        principalId: id.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: variable.roleDefinitionId.StorageQueueDataContributor
      }
      {
        principalId: id.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: variable.roleDefinitionId.StorageTableDataContributor
      }
    ]
    skuName: storageAccount.?skuName
    supportsHttpsTrafficOnly: true
    tags: storageAccount.?tags
  }
}

output applicationInsights object = { name: appi.outputs.name,  resourceId: appi.outputs.resourceId }
output logAnalyticsWorkspace object = { name: log.outputs.name, resourceId: log.outputs.resourceId }
output storageAccount object = { name: st.outputs.name, resourceId: st.outputs.resourceId }
output userAssignedIdentity object = { name: id.outputs.name, resourceId: id.outputs.resourceId }

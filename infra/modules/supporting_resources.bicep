targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'

param applicationInsights type.applicationInsights
param logAnalticsWorkspace type.logAnalyticsWorkspace
param networkSecurityGroup type.networkSecurityGroup
param networkWatcher type.networkWatcher
param storageAccounts type.storageAccount[]
param userAssignedIdentity type.userAssignedIdentity
param virtualNetwork type.virtualNetwork

module nw 'br/public:avm/res/network/network-watcher:0.5.1' = if(networkWatcher.?deploy!) {
  name: 'deploy-${networkWatcher.?name!}'
  params: {
    enableTelemetry: true
    location: resourceGroup().location
    name: networkWatcher.?name!
    tags: networkWatcher.?tags
  }
}

module nsg 'br/public:avm/res/network/network-security-group:0.5.3' = {
  name: 'deploy-${networkSecurityGroup.name}'
  params: {
    enableTelemetry: true
    location: resourceGroup().location
    name: networkSecurityGroup.name
    securityRules: networkSecurityGroup.?securityRules
    tags: networkSecurityGroup.?tags
  }
}

module vnet 'br/public:avm/res/network/virtual-network:0.10.0' = {
  name: 'deploy-${virtualNetwork.name}'
  params: {
    addressPrefixes: [
      '10.107.0.0/16'
    ]
    enableTelemetry: true
    location: resourceGroup().location
    name: virtualNetwork.name
    subnets: [
      {
        addressPrefixes: [ '10.107.1.0/24' ]
        defaultOutboundAccess: true
        delegation: 'Microsoft.App/environments'
        name: 'FunctionApps'
        networkSecurityGroupResourceId: nsg.outputs.resourceId
        serviceEndpoints: [
          'Microsoft.Storage'
        ]
      }
      {
        addressPrefixes: [ '10.107.2.0/24' ]
        defaultOutboundAccess: true
        name: 'StorageAccounts'
        networkSecurityGroupResourceId: nsg.outputs.resourceId
      }
      {
        addressPrefixes: [ '10.107.77.0/24' ]
        defaultOutboundAccess: true
        name: 'Main'
        networkSecurityGroupResourceId: nsg.outputs.resourceId
      }
    ]
    tags: virtualNetwork.?tags
    vnetEncryption: true
  }
}

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

module st 'br/public:avm/res/storage/storage-account:0.33.0' = [for storageAccount in storageAccounts: {
  dependsOn: [ vnet ]
  name: 'deploy-${storageAccount.name}'
  params: {
    accessTier: storageAccount.?accessTier
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    blobServices: storageAccount.?blobServices
    enableTelemetry: true
    kind: storageAccount.?kind
    location: resourceGroup().location
    minimumTlsVersion: 'TLS1_2'
    name: storageAccount.name
    networkAcls: storageAccount.?networkAcls
    publicNetworkAccess: 'Enabled'
    requireInfrastructureEncryption: true
    roleAssignments: [for roleAssignment in storageAccount.?roleAssignments!: {
      principalId: id.outputs.principalId
      principalType: roleAssignment.?principalType
      roleDefinitionIdOrName: roleAssignment.roleDefinitionId
    }]
    skuName: storageAccount.?skuName
    supportsHttpsTrafficOnly: true
    tags: storageAccount.?tags
  }
}]

output applicationInsights object = { name: appi.outputs.name,  resourceId: appi.outputs.resourceId }
output logAnalyticsWorkspace object = { name: log.outputs.name, resourceId: log.outputs.resourceId }
output networkSecurityGroup object = { name: nsg.outputs.name, resourceId: nsg.outputs.resourceId }
output storageAccounts array = [for (storageAccount, i) in storageAccounts: { name: st[i].outputs.name, resourceId: st[i].outputs.resourceId }]
output userAssignedIdentity object = { name: id.outputs.name, principalId: id.outputs.principalId, resourceId: id.outputs.resourceId }
output virtualNetwork object = { name: vnet.outputs.name, resourceId: vnet.outputs.resourceId, subnetResourceIds: vnet.outputs.subnetResourceIds }

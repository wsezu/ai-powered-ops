targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'

param applicationInsightsResourceId string
param dataStorageAccountResourceId string
param functionApp type.functionApp
param serverFarm type.serverFarm
param systemStorageAccountResourceId string
param userAssignedIdentityResourceId string
param virtualNetworkSubnetResourceId string

resource data_st 'Microsoft.Storage/storageAccounts@2026-04-01' existing = {
  name: last(split(dataStorageAccountResourceId, '/'))
}

resource system_st 'Microsoft.Storage/storageAccounts@2026-04-01' existing = {
  name: last(split(systemStorageAccountResourceId, '/'))
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: last(split(userAssignedIdentityResourceId, '/'))
}

module asp 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'deploy-${serverFarm.name}'
  params: {
    enableTelemetry: true
    kind:'linux'
    location: resourceGroup().location
    name: serverFarm.name
    reserved: true
    skuCapacity: 1
    skuName: 'B1'
    tags: serverFarm.?tags
    zoneRedundant: false
  }
}

module func 'br/public:avm/res/web/site:0.24.0' = {
  name: 'deploy-${functionApp.name}'
  params: {
    clientAffinityEnabled: false
    configs: [
      {
        applicationInsightResourceId: applicationInsightsResourceId
        name: 'appsettings'
        properties: {
          AzureWebJobsStorage__credential: 'managedidentity'
          AzureWebJobsStorage__blobServiceUri: 'https://${system_st.name}.blob.${az.environment().suffixes.storage}'
          AzureWebJobsStorage__queueServiceUri: 'https://${system_st.name}.queue.${az.environment().suffixes.storage}'
          AzureWebJobsStorage__tableServiceUri: 'https://${system_st.name}.table.${az.environment().suffixes.storage}'
          AzureWebJobsStorage__clientId: uami.properties.clientId
          DataStorage__blobServiceUri: 'https://${data_st.name}.blob.${az.environment().suffixes.storage}'
          DataStorage__clientId: uami.properties.clientId
          FUNCTIONS_EXTENSION_VERSION: '~4'
          FUNCTIONS_WORKER_RUNTIME: 'python'
          WEBSITE_RUN_FROM_PACKAGE: '1'
        }
        storageAccountResourceId: system_st.id
        storageAccountUseIdentityAuthentication: true
      }
    ]
    enableTelemetry: true
    httpsOnly: true
    kind: functionApp.kind
    location: resourceGroup().location
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        uami.id
      ]
    }
    name: functionApp.name
    outboundVnetRouting: {
      allTraffic: true
    }
    publicNetworkAccess: 'Enabled'
    serverFarmResourceId: asp.outputs.resourceId
    siteConfig: {
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      linuxFxVersion: 'PYTHON|3.12'
    }
    tags: functionApp.?tags
    virtualNetworkSubnetResourceId: virtualNetworkSubnetResourceId
  }
}

output functionApp object = { name: func.outputs.name,  resourceId: func.outputs.resourceId }
output serverFarm object = { name: asp.outputs.name,  resourceId: asp.outputs.resourceId }

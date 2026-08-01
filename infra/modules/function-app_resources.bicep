targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'

param applicationInsightsResourceId string
param functionApp type.functionApp
param serverFarm type.serverFarm
param storageAccountResourceId string
param userAssignedIdentityResourceId string

resource st 'Microsoft.Storage/storageAccounts@2026-04-01' existing = {
  name: last(split(storageAccountResourceId, '/'))
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
    skuName: 'FC1'
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
          AzureWebJobsStorage__blobServiceUri: 'https://${st.name}.blob.${az.environment().suffixes.storage}'
          AzureWebJobsStorage__queueServiceUri: 'https://${st.name}.queue.${az.environment().suffixes.storage}'
          AzureWebJobsStorage__tableServiceUri: 'https://${st.name}.table.${az.environment().suffixes.storage}'
          AzureWebJobsStorage__clientId: uami.properties.clientId
        }
        storageAccountResourceId: st.id
        storageAccountUseIdentityAuthentication: true
      }
    ]
    enableTelemetry: true
    functionAppConfig: {
      deployment: {
        storage: {
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: uami.id
          }
          type: 'blobContainer'
          value: 'https://${st.name}.blob.${az.environment().suffixes.storage}/app-packages'
        }
      }
      runtime: {
        name: 'python'
        version: '3.12'
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 10
      }
    }
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
    siteConfig: {
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    publicNetworkAccess: 'Enabled'
    serverFarmResourceId: asp.outputs.resourceId
    tags: functionApp.?tags
  }
}

output functionApp object = { name: func.outputs.name,  resourceId: func.outputs.resourceId }
output serverFarm object = { name: asp.outputs.name,  resourceId: asp.outputs.resourceId }

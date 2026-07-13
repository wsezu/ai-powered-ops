targetScope = 'resourceGroup'

import * as v from '../helpers/variables.bicep'

param name string

var bscs = [ 'app-package', 'focus-exports', 'normalized', 'results' ]
var nameSegments = sys.split(name, '-')
var resourceNameSuffix = '${nameSegments[1]}-${nameSegments[2]}-${nameSegments[3]}-${nameSegments[4]}'

resource sa 'Microsoft.Storage/storageAccounts@2026-04-01' = {
  kind: 'StorageV2'
  location: resourceGroup().location
  name: 'sav2${sys.toLower(sys.replace(resourceNameSuffix, '-', ''))}'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: true
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
        queue: {
          enabled: true
        }
        table: {
          enabled: true
        }
      }
    }
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices, Logging, Metrics'
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
  sku: {
    name: 'Standard_LRS'
  }
}

resource bs 'Microsoft.Storage/storageAccounts/blobServices@2026-04-01' = {
  name: 'default'
  parent: sa
}

resource bsc 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01' = [for bscName in bscs: {
  name: bscName
  parent: bs
}]

resource sf 'Microsoft.Web/serverfarms@2025-03-01' = {
  kind: 'linux'
  location: resourceGroup().location
  name: 'asp-${resourceNameSuffix}'
  properties: {
    reserved: true
    zoneRedundant: false
  }
  sku: {
    family: 'FC'
    name: 'FC1'
    size: 'FC1'
    tier: 'FlexConsumption'
  }
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  location: resourceGroup().location
  name: 'uami-${nameSegments[1]}_func-${nameSegments[2]}-${nameSegments[3]}-${nameSegments[4]}'
}


resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(az.tenant().tenantId, az.subscription().subscriptionId, sa.id, fa.id, v.roleDefinitionId.StorageBlobDataOwner)
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: az.subscriptionResourceId('Microsoft.Authorization/roleDefinitions', v.roleDefinitionId.StorageBlobDataOwner)
  }
  scope: sa
}

resource fa 'Microsoft.Web/sites@2025-03-01' = {
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  kind: 'functionapp,linux'
  location: resourceGroup().location
  name: 'func-${resourceNameSuffix}'
  properties: {
    clientAffinityEnabled: false
    functionAppConfig: {
      deployment: {
        storage: {
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: uami.id
          }
          type: 'blobContainer'
          value: 'https://${sa.name}.blob.${environment().suffixes.storage}/app-package'
        }
      }
      runtime: {
        name: 'python'
        version: '3.12'
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 100
      }
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    serverFarmId: sf.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: sa.properties.primaryEndpoints.blob
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: sa.properties.primaryEndpoints.queue
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: sa.properties.primaryEndpoints.table
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
  }
}

using './main.bicep'

import * as variable from 'helpers/variables.bicep'

var project = {
  description: 'AI Powered FinOps and SecOps'
  environment: 'prd'
  location: variable.regions.westeurope.location
  name: 'AI powered ops'
  shortName: 'aiops'
}

var tags = {
  description: project.description
  environment: project.environment
  project: project.name
}

var resourceSuffix = '${project.shortName}-${project.environment}-${variable.regions[project.location].shortName}'
var privateStorageAccountName = 'stv2${replace(resourceSuffix, '-', '')}001'
var publicStorageAccountName = 'stv2${replace(resourceSuffix, '-', '')}002'
var subscriptionId = readEnvironmentVariable('AZURE_SUBSCRIPTION_ID', 'a525b25c-14fc-42cb-a55f-9dedea6bffaa')

param applicationInsights = {
  name: 'appi-${resourceSuffix}-001'
  tags: tags
}

param functionApp = {
  kind: 'functionapp,linux'
  name: 'func-${resourceSuffix}-001'
  tags: tags
}

param foundryAccount = {
  aiFoundryConfiguration: {
    accountName: 'fa-${resourceSuffix}-001'
    allowProjectManagement: true
    project: {
      desc: 'AI powered FinOps and SecOps architecture advisor infrastructure on Azure.'
      displayName: 'AI powered Ops'
      name: 'proj-${resourceSuffix}-001'
    }
    sku: 'S0'
  }
  aiModelDeployments: [
    {
      model: {
        format: 'OpenAI'
        name: 'gpt-5.1'
        version: '2025-11-13'
      }
      name: 'gpt-5.1'
      sku: {
        capacity: 10
        name: 'GlobalStandard'
      }
      versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    }
    {
      model: {
        format: 'OpenAI'
        name: 'gpt-5-mini'
        version: '2025-08-07'
      }
      name: 'gpt-5-mini'
      sku: {
        capacity: 20
        name: 'GlobalStandard'
      }
      versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    }
  ]
  baseName: 'aiops'
  location: project.location
  tags: tags
}

param logAnalyticsWorkspace = {
  dataRetention: 30
  name: 'log-${resourceSuffix}-001'
  skuName: 'PerGB2018'
  tags: tags
}

param networkSecurityGroup = {
  location: project.location
  name: 'nsg-${resourceSuffix}-001'
  tags: tags
}

param resourceGroups = [
  {
    location: project.location
    name: 'rg-${resourceSuffix}-001'
    subscriptionId: subscriptionId
    tags: tags
  }
]

param serverFarm = {
  name: 'asp-${resourceSuffix}-001'
  tags: tags
}

param storageAccounts = [
  {
    accessTier: 'Hot'
    blobServices: {
      containers: [
        {
          name: 'focus-exports'
        }
        {
          name: 'normalized'
        }
      ]
    }
    kind: 'StorageV2'
    location: project.location
    name: (length(privateStorageAccountName) <= 24) ? privateStorageAccountName : take(privateStorageAccountName, 24)
    networkAcls: {
      bypass: 'AzureServices, Logging, Metrics'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          action: 'Allow'
          id: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroups[0].name}/providers/Microsoft.Network/virtualNetworks/${virtualNetwork.name}/subnets/FunctionApps'
        }
      ]
    }
    roleAssignments: [
      {
        roleDefinitionId: variable.roleDefinitionId.StorageBlobDataOwner
      }
    ]
    skuName: 'Standard_LRS'
    tags: tags
  }
  {
    accessTier: 'Hot'
    blobServices: {
      containers: [
        {
          name: 'app-packages'
        }
      ]
    }
    kind: 'StorageV2'
    location: project.location
    name: (length(publicStorageAccountName) <= 24) ? publicStorageAccountName : take(publicStorageAccountName, 24)
    networkAcls: {
      bypass: 'AzureServices, Logging, Metrics'
      defaultAction: 'Allow'
    }
    roleAssignments: [
      {
        roleDefinitionId: variable.roleDefinitionId.StorageBlobDataOwner
      }
      {
        roleDefinitionId: variable.roleDefinitionId.StorageQueueDataContributor
      }
      {
        roleDefinitionId: variable.roleDefinitionId.StorageTableDataContributor
      }
    ]
    skuName: 'Standard_LRS'
    tags: tags
  }
]

param userAssignedIdentity = {
  location: project.location
  name: 'id-${resourceSuffix}-001'
  tags: tags
}

param virtualNetwork = {
  addressPrefixes: [
    '10.107.0.0/16'
  ]
  location: project.location
  name: 'vnet-${resourceSuffix}-001'
  tags: tags
}

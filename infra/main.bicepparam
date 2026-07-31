using './main.bicep'

import * as v from 'helpers/variables.bicep'

var project = {
  description: 'AI Powered FinOps and SecOps'
  environment: 'prd'
  location: v.regions.swedencentral.location
  name: 'AI powered ops'
  shortName: 'aiops'
}

var tags = {
  description: project.description
  environment: project.environment
  project: project.name
}

var resourceSuffix = '${project.shortName}-${project.environment}-${v.regions[project.location].shortName}'
var storageAccountName = 'stv2${replace(resourceSuffix, '-', '')}001'

param applicationInsights = {
  name: 'appi-${resourceSuffix}-001'
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
        name: 'DataZoneStandard'
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
        name: 'DataZoneStandard'
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

param resourceGroups = [
  {
    location: project.location
    name: 'rg-${resourceSuffix}-001'
    subscriptionId: 'a525b25c-14fc-42cb-a55f-9dedea6bffaa'
    tags: tags
  }
]

param storageAccount = {
  accessTier: 'Hot'
  kind: 'StorageV2'
  location: project.location
  name: (length(storageAccountName) <= 24) ? storageAccountName : take(storageAccountName, 24)
  skuName: 'Standard_LRS'
  tags: tags
}

param userAssignedIdentity = {
  location: project.location
  name: 'id-${resourceSuffix}-001'
  tags: tags
}

using './main.bicep'

import * as v from 'helpers/variables.bicep'

var project = {
  description: 'AI Powered FinOps and SecOps'
  environment: 'dev'
  name: 'ai-driven-ops'
  shortName: 'aiops'
}

var tags = {
  description: project.description
  environment: project.environment
  project: project.name
}

param foundryAccounts = [
  {
    deployments: [
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
    kind: 'AIServices'
    location: resourceGroups[0].location
    name: 'aif-${project.shortName}-${project.environment}-${v.regions.swedencentral.shortName}-001'
    publicNetworkAccess: true
    resourceGroupName: resourceGroups[0].name
    sku: 'S0'
    tags: tags
  }
]

param foundryProjects = [
  {
    location: foundryAccounts[0].location
    name: 'proj-${project.shortName}-${project.environment}-${v.regions.swedencentral.shortName}-001'
    parent: foundryAccounts[0].name
    resourceGroupName: resourceGroups[0].name
  }
]

param functionApps = [
  {
    name: 'func-${project.shortName}-${project.environment}-${v.regions.swedencentral.shortName}-001'
    resourceGroupName: resourceGroups[0].name
  }
]

param resourceGroups = [
  {
    location: v.regions.swedencentral.location
    name: 'rg-${project.shortName}-${project.environment}-${v.regions.swedencentral.shortName}-001'
    tags: tags
  }
]

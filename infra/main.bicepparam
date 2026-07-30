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

param applicationInsights = {
  name: 'appi-${resourceSuffix}-001'
  resourceGroupName: resourceGroups[0].name
  tags: tags
}


param logAnalyticsWorkspace = {
  dataRetention: 30
  name: 'log-${resourceSuffix}-001'
  resourceGroupName: resourceGroups[0].name
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

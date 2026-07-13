targetScope = 'resourceGroup'

param location string
param foundryAccountName string
param foundryProjectName string

resource fa 'Microsoft.CognitiveServices/accounts@2026-03-01' existing = {
  name: foundryAccountName
}

resource fp 'Microsoft.CognitiveServices/accounts/projects@2026-03-01' = {
  location: location
  name: foundryProjectName
  identity: {
    type: 'SystemAssigned'
  }
  parent: fa
  properties: {
    description: 'Multi-agent advisor: cost, advisor, architecture, security and operational risk agents.'
    displayName: 'AI Powered Operations'
  }
}

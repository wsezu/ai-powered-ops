@export()
type applicationInsights = {
  applicationType: 'web' | 'other'
  flowType: 'Bluefield' | 'Redfield'
  ingestionMode: 'ApplicationInsights' | 'ApplicationInsightsWithDiagnosticSettings' | 'LogAnalytics'
  kind: 'web'
  location: string
  name: string
  resourceGroupName: string
  retentionInDays: 120 | 180 | 270 | 30 | 365 | 550 | 60 | 730 | 90
  tags: object?
  workspaceResourceId: string
}

@export()
type foundryAccount = {
  deployments: foundryDeployment[]?
  kind: 'AIServices'
  location: string
  name: string
  publicNetworkAccess: bool
  resourceGroupName: string
  sku: 'S0'
  tags: object?
}

@export()
type foundryProject = {
  location: string
  name: string
  parent: string
  resourceGroupName: string
}

@export()
type functionApp = {
  name: string
  resourceGroupName: string
}

@export()
type logAnalyticsWorkspace = {
  location: string
  name: string
  resourceGroupName: string
  dataRetention: int
  skuName: 'CapacityReservation' | 'Free' | 'LACluster' | 'PerGB2018'
}

@export()
type resourceGroup = {
  location: string
  name: string
  tags: object?
}

type foundryDeployment = {
  model: foundryDeploymentModel
  name: string
  sku: {
    capacity: int
    name: 'DataZoneStandard' | 'GlobalStandard' | 'Standard'
  }
  versionUpgradeOption: 'NoAutoUpgrade' | 'OnceCurrentVersionExpired' | 'OnceNewDefaultVersionAvailable'
}

type foundryDeploymentModel = {
  format: string
  name: string
  version: string
}

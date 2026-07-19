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

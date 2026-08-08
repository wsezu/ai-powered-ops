type aiFoundryConfiguration = {
  accountName: string?
  allowProjectManagement: bool?
  project: {
    desc: string
    displayName: string
    name: string
  }?
  roleAssignments: roleAssignment[]?
  sku: 'S0'?
}

type managedIdentity = {
  systemAssigned: bool?
  userAssignedResourceIds: string[]?
}

type roleAssignment = {
  principalId: string
  principalType: 'Device' | 'ForeignGroup' | 'Group' | 'ServicePrincipal' | 'User'
  roleDefinitionId: string
}

@export()
type applicationInsights = {
  location: string?
  name: string
  roleAssignments: roleAssignment[]?
  tags: object?
  workspaceResourceId: string?
}

@export()
type functionApp = {
  kind: 'functionapp,linux'
  location: string?
  managedIdentities: managedIdentity?
  name: string
  serverFarmResourceId: string?
  tags: object?
}

@export()
type foundryAccount = {
  aiFoundryConfiguration: aiFoundryConfiguration?
  aiModelDeployments: {
    model: {
      name: string
      format: string
      version: string
    }
    name: string?
    sku: {
      capacity: int?
      name: string
    }?
    versionUpgradeOption: string?
  }[]?
  baseName: string
  location: string?
  tags: object?
}

@export()
type logAnalyticsWorkspace = {
  dataRetention: int?
  location: string?
  name: string
  roleAssignments: roleAssignment[]?
  skuName: 'CapacityReservation' | 'LACluster' | 'PerGB2018'?
  tags: object?
}

@export()
type networkSecurityGroup = {
  location: string?
  name: string
  securityRules: {
    name: string
    properties: {
      access: 'Allow' | 'Deny'
      destinationAddressPrefixes: string[]?
      destinationPortRanges: string[]?
      direction: 'Inbound' | 'Outbound'
      priority: int
      protocol: '*' | 'Ah' | 'Esp' | 'Icmp' | 'Tcp' | 'Udp'
      sourceAddressPrefixes: string[]?
      sourcePortRanges: string[]?
    }
  }[]?
  tags: object?
}

@export()
type networkWatcher = {
  deploy: bool
  location: string?
  name: string
  tags: object?
}

@export()
type resourceGroup = {
  location: string?
  name: string
  roleAssignments: roleAssignment[]?
  subscriptionId: string
  tags: object?
}

@export()
type serverFarm = {
  location: string?
  name: string
  tags: object?
}

@export()
type storageAccount = {
  accessTier: 'Cold' | 'Cool' | 'Hot' | 'Premium'?
  blobServices: {
    containers: {
      name: string
    }[]
  }?
  kind: 'BlobStorage' | 'BlockBlobStorage' | 'FileStorage' | 'Storage' | 'StorageV2'?
  location: string?
  name: string
    roleAssignments: {
    principalId: string?
    principalType: 'Device' | 'ForeignGroup' | 'Group' | 'ServicePrincipal' | 'User'?
    roleDefinitionId: string
  }[]?
  networkAcls: {
    bypass: 'AzureServices, Logging, Metrics' | 'None'
    defaultAction: 'Allow' | 'Deny'
    ipRules: {
      action: 'Allow' | 'Deny'
      value: string
    }[]?
    virtualNetworkRules: {
      action: 'Allow' | 'Deny'
      id: string
    }[]?
  }?
  skuName: 'Premium_LRS' | 'Premium_ZRS' | 'PremiumV2_LRS' | 'PremiumV2_ZRS' | 'Standard_GRS' | 'Standard_GZRS' | 'Standard_LRS' | 'Standard_RAGRS' | 'Standard_RAGZRS' | 'Standard_ZRS' | 'StandardV2_GRS' | 'StandardV2_GZRS' | 'StandardV2_LRS' | 'StandardV2_ZRS'?
  tags: object?
}

@export()
type userAssignedIdentity = {
  location: string?
  name: string
  tags: object?
}

@export()
type virtualNetwork = {
  addressPrefixes: string[]
  location: string?
  name: string
  subnets:{
    addressPrefixes: string[]?
    defaultOutboundAccess: bool?
    name: string
    networkSecurityGroupResourceId: string?
    routeTableResourceId: string?
    serviceEndpoints: string[]?
  }[]?
  tags: object?
}

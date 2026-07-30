type roleAssignment = {
  principalId: string
  principalType: 'Device' | 'ForeignGroup' | 'Group' | 'ServicePrincipal' | 'User'
  roleDefinitionIdOrName: string
}

@export()
type applicationInsights = {
  location: string?
  name: string
  resourceGroupName: string
  roleAssignments: roleAssignment[]?
  tags: object?
  workspaceResourceId: string?
}

@export()
type logAnalyticsWorkspace = {
  dataRetention: int?
  location: string?
  name: string
  roleAssignments: roleAssignment[]?
  resourceGroupName: string
  skuName: 'CapacityReservation' | 'LACluster' | 'PerGB2018'?
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
type storageAccount = {
  accessTier: 'Cold' | 'Cool' | 'Hot' | 'Premium'?
  kind: 'BlobStorage' | 'BlockBlobStorage' | 'FileStorage' | 'Storage' | 'StorageV2'?
  location: string?
  name: string
  resourceGroupName: string
  roleAssignments: roleAssignment[]?
  skuName: 'Premium_LRS' | 'Premium_ZRS' | 'PremiumV2_LRS' | 'PremiumV2_ZRS' | 'Standard_GRS' | 'Standard_GZRS' | 'Standard_LRS' | 'Standard_RAGRS' | 'Standard_RAGZRS' | 'Standard_ZRS' | 'StandardV2_GRS' | 'StandardV2_GZRS' | 'StandardV2_LRS' | 'StandardV2_ZRS'?
  tags: object?
}

@export()
type userAssignedIdentity = {
  location: string?
  name: string
  resourceGroupName: string
  tags: object?
}

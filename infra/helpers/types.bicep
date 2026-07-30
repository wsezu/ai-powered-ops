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

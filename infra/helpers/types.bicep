type roleAssignment = {
  principalId: string
  principalType: 'Device' | 'ForeignGroup' | 'Group' | 'ServicePrincipal' | 'User'
  roleDefinitionIdOrName: string
}

@export()
type resourceGroup = {
  location: string?
  name: string
  roleAssignments: roleAssignment[]?
  tags: object?
}

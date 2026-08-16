targetScope = 'subscription'

@description('Grants a single role to a single principal across multiple subscriptions individually. Not management-group-scoped: a subscription-scoped deployment can only reach downward in the scope hierarchy, to subscriptions/resource groups at or below its own scope — never upward to a parent management group, confirmed against every documented Bicep cross-scope example before this was written. See docs/infra.md for the full reasoning.')
param principalId string
param roleDefinitionId string
param subscriptionIds string[]

module roleAssignments 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = [for subscriptionId in subscriptionIds: {
  name: 'deploy-role-assignment-${uniqueString(roleDefinitionId, subscriptionId)}'
  scope: subscription(subscriptionId)
  params: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionIdOrName: roleDefinitionId
  }
}]

targetScope = 'subscription'

import * as variable from '../helpers/variables.bicep'

param principalId string
param subscriptionIds string[]

module securityReaderAssignments 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = [for subscriptionId in subscriptionIds: {
  name: 'deploy-security-reader-${subscriptionId}'
  scope: subscription(subscriptionId)
  params: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionIdOrName: variable.roleDefinitionId.SecurityReaderRoleId
  }
}]

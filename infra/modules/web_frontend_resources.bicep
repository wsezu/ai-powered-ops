targetScope = 'resourceGroup'

import * as type from '../helpers/types.bicep'
import * as variable from '../helpers/variables.bicep'

param keyVault type.keyVault
param linkedBackendResourceId string
param staticWebApp type.staticWebApp

var additionalKeyVaultRoleAssignments = [for ra in (keyVault.?roleAssignments ?? []): {
  principalId: ra.principalId
  principalType: ra.?principalType
  roleDefinitionIdOrName: ra.roleDefinitionId
}]

module swa 'br/public:avm/res/web/static-site:0.9.5' = {
  name: 'deploy-${staticWebApp.name}'
  params: {
    enableTelemetry: true
    linkedBackend: {
      location: resourceGroup().location
      resourceId: linkedBackendResourceId
    }
    location: resourceGroup().location
    managedIdentities: {
      systemAssigned: true
    }
    name: staticWebApp.name
    sku: staticWebApp.?sku ?? 'Standard'
    tags: staticWebApp.?tags
  }
}

module kv 'br/public:avm/res/key-vault/vault:0.14.0' = {
  name: 'deploy-${keyVault.name}'
  params: {
    enableTelemetry: true
    location: resourceGroup().location
    name: keyVault.name
    roleAssignments: concat(
      [
        {
          // The Static Web App's own system-assigned identity — needed so it can
          // read the Entra ID client secret referenced from staticwebapp.config.json.
          // Always granted; not something that belongs in bicepparam, since a brand
          // new identity's principalId isn't known until the SWA above is created.
          principalId: swa.outputs.systemAssignedMIPrincipalId!
          principalType: 'ServicePrincipal'
          roleDefinitionIdOrName: variable.roleDefinitionId.KeyVaultSecretsUserRoleId
        }
      ],
      additionalKeyVaultRoleAssignments
    )
    sku: 'standard'
    tags: keyVault.?tags
  }
}

output keyVault object = {
  name: kv.outputs.name
  resourceId: kv.outputs.resourceId
  uri: kv.outputs.uri
}

output staticWebApp object = {
  defaultHostname: swa.outputs.defaultHostname
  name: swa.outputs.name
  resourceId: swa.outputs.resourceId
}

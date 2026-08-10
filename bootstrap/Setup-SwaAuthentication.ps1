[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$StaticWebAppName,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory=$false)]
    [switch]$AppendSecret
)

$ErrorActionPreference = 'Stop'

# Verify prerequisites
foreach ($cmd in 'gh', 'az') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd is required."
    }
}

$appRegId = ''
$appRegDisplayName = "$StaticWebAppName-auth"
$appRegSecretValue = ''
$keyVaultSecretName = 'swa-entra-client-secret'
$swaHostname = (az staticwebapp show --name $StaticWebAppName --resource-group $ResourceGroupName --query "defaultHostname" --output tsv)
$redirectUri = "https://$swaHostname/.auth/login/aad/callback"
$settingName = 'AAD_CLIENT_SECRET'

$existingAppRegId = (az ad app list --display-name $appRegDisplayName --query "[0].appId" --output tsv)
if($null -ne $existingAppRegId) {
    Write-Output "Existing app registration found with ID: $existingAppRegId"
    $appRegId = $existingAppRegId
} else {
    Write-Output "Creating new app registration with display name: $appRegDisplayName"
    $appRegId = (az ad app create --display-name $appRegDisplayName --sign-in-audience AzureADMyOrg --web-redirect-uris $redirectUri --query "appId" --output tsv)
    Write-Output 'Adding User.Read delegated permission to the app registration'
    az ad app permission add --id $appRegId --api 00000003-0000-0000-c000-000000000000 --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
    Write-Output 'Granting admin consent for the app registration'
    az ad app permission grant --id $appRegId --api 00000003-0000-0000-c000-000000000000
    Write-Output 'Creating the service principal for the app registration'
    az ad sp create --id $appRegId
}

if($AppendSecret) {
    Write-Output 'Creating a new client secret for the app registration'
    $appRegSecretValue = (az ad app credential reset --id $appRegId --append --years 1 --query "password" --output tsv)
} else {
    Write-Output 'Creating a new client secret for the app registration (replacing any existing secrets)'
    $appRegSecretValue = (az ad app credential reset --id $appRegId --years 1 --query "password" --output tsv)
}


Write-Output 'Storing the client secret in Azure Key Vault'
az keyvault secret set --vault-name $KeyVaultName --name $keyVaultSecretName --value $appRegSecretValue | Out-Null

$keyVaultUri = (az keyvault show --name $KeyVaultName --query "properties.vaultUri" --output tsv)
$keyVaultReference = "@Microsoft.KeyVault(SecretUri=$keyVaultUri/secrets/$keyVaultSecretName)"

Write-Output 'Updating the Static Web App configuration with the Key Vault reference'
az staticwebapp appsettings set --name $StaticWebAppName --setting-names "AAD_CLIENT_ID=$appRegId" "$settingName=$keyVaultReference" | Out-Null
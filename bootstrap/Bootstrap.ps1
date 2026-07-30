[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Org,

    [Parameter(Mandatory)]
    [string]$Repo,

    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$Location
)

$ErrorActionPreference = 'Stop'

# Verify prerequisites
foreach ($cmd in 'gh', 'az') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd is required."
    }
}

$identityName = "id-$Repo-prd-$Location-001"
$resourceGroup = "rg-$Repo-prd-$Location-001"

Write-Output "Creating GitHub repository..."
gh repo create "$Org/$Repo" --add-readme --gitignore VisualStudio --license gpl-3.0 --public

Write-Output "Getting OIDC subject..."
$subject = gh api "repos/$Org/$Repo" --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id):ref:refs/heads/main"'

Write-Output "Creating resource group..."
az group create --location $Location --name $resourceGroup --subscription $SubscriptionId | Out-Null

Write-Output "Creating managed identity..."
az identity create --location $Location --name $identityName --resource-group $resourceGroup --subscription $SubscriptionId | Out-Null

Write-Output "Creating federated credential..."
az identity federated-credential create `
    --name branch-main `
    --identity-name $identityName `
    --resource-group $resourceGroup `
    --subscription $SubscriptionId `
    --audience api://AzureADTokenExchange `
    --issuer https://token.actions.githubusercontent.com `
    --subject $subject | Out-Null

Write-Output "Reading identity..."
$identity = az identity show `
    --name $identityName `
    --resource-group $resourceGroup `
    --subscription $SubscriptionId |
    ConvertFrom-Json

Write-Output "Creating GitHub secrets..."
gh secret set AZURE_CLIENT_ID `
    --repo "$Org/$Repo" `
    --body $identity.clientId

gh secret set AZURE_SUBSCRIPTION_ID `
    --repo "$Org/$Repo" `
    --body $SubscriptionId

gh secret set AZURE_TENANT_ID `
    --repo "$Org/$Repo" `
    --body $identity.tenantId

Write-Output "Assigning Reader role..."
az role assignment create `
    --assignee-object-id $identity.principalId `
    --assignee-principal-type ServicePrincipal `
    --role Reader `
    --scope "/subscriptions/$SubscriptionId" | Out-Null

Write-Output "Done!"
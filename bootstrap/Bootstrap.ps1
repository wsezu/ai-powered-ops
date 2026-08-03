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
$branch_subject = gh api "repos/$Org/$Repo" --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id):ref:refs/heads/main"'
$pr_subject = gh api "repos/$Org/$Repo" --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id):pull_request"'

Write-Output "Creating resource group..."
az group create --location $Location --name $resourceGroup --subscription $SubscriptionId | Out-Null

Write-Output "Creating managed identity..."
az identity create --location $Location --name $identityName --resource-group $resourceGroup --subscription $SubscriptionId | Out-Null

Write-Output "Creating federated credentials..."
az identity federated-credential create `
    --name branch-main `
    --identity-name $identityName `
    --resource-group $resourceGroup `
    --subscription $SubscriptionId `
    --audience api://AzureADTokenExchange `
    --issuer https://token.actions.githubusercontent.com `
    --subject $branch_subject | Out-Null

az identity federated-credential create `
    --name pull-request `
    --identity-name $identityName `
    --resource-group $resourceGroup `
    --subscription $SubscriptionId `
    --audience api://AzureADTokenExchange `
    --issuer https://token.actions.githubusercontent.com `
    --subject $pr_subject | Out-Null

Write-Output "Reading identity..."
$identity = az identity show `
    --name $identityName `
    --resource-group $resourceGroup `
    --subscription $SubscriptionId |
    ConvertFrom-Json

Write-Output "Creating GitHub repository variables..."
gh variable set AZURE_CLIENT_ID `
    --repo "$Org/$Repo" `
    --body $identity.clientId

gh variable set AZURE_SUBSCRIPTION_ID `
    --repo "$Org/$Repo" `
    --body $SubscriptionId

gh variable set AZURE_TENANT_ID `
    --repo "$Org/$Repo" `
    --body $identity.tenantId

Write-Output "Assigning Reader role..."
az role assignment create `
    --assignee-object-id $identity.principalId `
    --assignee-principal-type ServicePrincipal `
    --role Reader `
    --scope "/subscriptions/$SubscriptionId" | Out-Null

Write-Output "Done!"
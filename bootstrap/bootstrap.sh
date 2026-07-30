#!/usr/bin/env bash
set -euo pipefail

command -v gh >/dev/null || { echo "GitHub CLI is required."; exit 1; }
command -v az >/dev/null || { echo "Azure CLI is required."; exit 1; }
command -v jq >/dev/null || { echo "jq is required."; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --org)
            ORG="$2"
            shift 2
            ;;
        --repo)
            REPO="$2"
            shift 2
            ;;
        --subscription)
            AZURE_SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --org <org> --repo <repo> --subscription <subscription_id> --location <location>"
            echo "  --org <org>                       GitHub organization name"
            echo "  --repo <repo>                     GitHub repository name"
            echo "  --subscription <subscription_id>  Azure subscription ID that will host the resource group and the user assigned managed identity"
            echo "  --location <location>             Azure location for the resource group and user assigned managed identity (e.g., westeurope)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --org <org> --repo <repo> --subscription <subscription_id> --location <location>"
            exit 1
            ;;
    esac
done

# Validate required parameters
: "${ORG:?--org is required}"
: "${REPO:?--repo is required}"
: "${AZURE_SUBSCRIPTION_ID:?--subscription is required}"
: "${LOCATION:?--location is required}"

IDENTITY_NAME="id-$REPO-prd-$LOCATION-001"
RESOURCE_GROUP="rg-$REPO-prd-$LOCATION-001"

echo "Creating GitHub repository '$ORG/$REPO'..."
gh repo create "$ORG/$REPO" --add-readme --gitignore VisualStudio --license gpl-3.0 --public > /dev/null
branch_subject=$(gh api "repos/$ORG/$REPO" --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id):ref:refs/heads/main"')
pr_subject=$(gh api "repos/$ORG/$REPO" --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id):pull_request"')

echo "Creating Azure resource group '$RESOURCE_GROUP' in location '$LOCATION'..."
az group create --location "$LOCATION" --name "$RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" > /dev/null

echo "Creating Azure user-assigned managed identity '$IDENTITY_NAME' in resource group '$RESOURCE_GROUP'..."
az identity create --location "$LOCATION" --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" > /dev/null
az identity federated-credential create --name "branch-main" --identity-name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" --audience 'api://AzureADTokenExchange' --issuer 'https://token.actions.githubusercontent.com' --subject "$branch_subject" > /dev/null
az identity federated-credential create --name "pull-request" --identity-name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" --audience 'api://AzureADTokenExchange' --issuer 'https://token.actions.githubusercontent.com' --subject "$pr_subject" > /dev/null

echo "Setting GitHub secrets for Azure credentials..."
IDENTITY_JSON=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID")
gh secret set AZURE_CLIENT_ID --repo "$ORG/$REPO" --body "$(jq -r '.clientId' <<<"$IDENTITY_JSON")" > /dev/null
gh secret set AZURE_SUBSCRIPTION_ID --repo "$ORG/$REPO" --body "$AZURE_SUBSCRIPTION_ID" > /dev/null
gh secret set AZURE_TENANT_ID --repo "$ORG/$REPO" --body "$(jq -r '.tenantId' <<<"$IDENTITY_JSON")" > /dev/null

echo "Assigning 'Reader' role to the managed identity for subscription '$AZURE_SUBSCRIPTION_ID'..."
az role assignment create --assignee-object-id "$(jq -r '.principalId' <<<"$IDENTITY_JSON")" --assignee-principal-type ServicePrincipal --role Reader --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID" > /dev/null
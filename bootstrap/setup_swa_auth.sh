#!/usr/bin/env bash
set -euo pipefail

# One-time (and re-runnable-to-rotate) setup: creates the Entra ID App
# Registration used for Static Web Apps' built-in Entra ID authentication,
# stores its client secret in Key Vault, and points the Static Web App's own
# application setting at that Key Vault secret via a Key Vault reference.
#
# Why this isn't part of the main Bicep deployment: creating an App
# Registration via Bicep requires the still-experimental Microsoft Graph
# extension, which has a documented, unresolved redeployment-idempotency bug.
# Given how often this repo's infra gets redeployed, that's not a risk worth
# taking for something that only needs to run once (or occasionally, to
# rotate the secret) — same reasoning as why the CI/CD identity itself is
# created by bootstrap.sh rather than the repeatable core Bicep.

command -v az >/dev/null || { echo "Azure CLI is required."; exit 1; }
command -v jq >/dev/null || { echo "jq is required."; exit 1; }

APPEND_SECRET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --swa-name)
            SWA_NAME="$2"
            shift 2
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --key-vault-name)
            KEY_VAULT_NAME="$2"
            shift 2
            ;;
        --append-secret)
            # Use when rotating an existing secret, so the old one keeps
            # working until you've confirmed the new one and removed it
            # yourself — avoids an outage mid-rotation.
            APPEND_SECRET=true
            shift 1
            ;;
        -h|--help)
            echo "Usage: $0 --swa-name <name> --resource-group <rg> --key-vault-name <kv>"
            echo "  --swa-name <name>          Name of the existing Static Web App"
            echo "  --resource-group <rg>      Resource group containing the Static Web App and Key Vault"
            echo "  --key-vault-name <kv>      Name of the existing Key Vault to store the client secret in"
            echo "  --append-secret            Add a new secret alongside the existing one, rather than replacing it (use when rotating)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

: "${SWA_NAME:?--swa-name is required}"
: "${RESOURCE_GROUP:?--resource-group is required}"
: "${KEY_VAULT_NAME:?--key-vault-name is required}"

APP_DISPLAY_NAME="${SWA_NAME}-auth"
SECRET_NAME="swa-entra-client-secret"
SETTING_NAME="AAD_CLIENT_SECRET"

echo "Looking up Static Web App hostname..."
SWA_HOSTNAME=$(az staticwebapp show \
    --name "$SWA_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query defaultHostname \
    --output tsv)
REDIRECT_URI="https://${SWA_HOSTNAME}/.auth/login/aad/callback"

echo "Checking for an existing app registration named '$APP_DISPLAY_NAME'..."
EXISTING_APP_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" --output tsv)

if [ -n "$EXISTING_APP_ID" ]; then
    echo "Found existing app registration ($EXISTING_APP_ID) — reusing it."
    APP_ID="$EXISTING_APP_ID"
else
    echo "Creating app registration..."
    APP_ID=$(az ad app create \
        --display-name "$APP_DISPLAY_NAME" \
        --sign-in-audience AzureADMyOrg \
        --web-redirect-uris "$REDIRECT_URI" \
        --query appId \
        --output tsv)

    echo "Adding User.Read delegated permission..."
    az ad app permission add \
        --id "$APP_ID" \
        --api 00000003-0000-0000-c000-000000000000 \
        --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope \
        > /dev/null

    echo "Granting the permission (as the signed-in user — sufficient for a single-tenant setup where you administer your own tenant)..."
    az ad app permission grant \
        --id "$APP_ID" \
        --api 00000003-0000-0000-c000-000000000000 \
        > /dev/null

    echo "Creating the service principal..."
    az ad sp create --id "$APP_ID" > /dev/null
fi

echo "Enabling ID token issuance — required for Static Web Apps' EasyAuth-based"
echo "sign-in flow to complete; without it, login silently loops back on itself"
echo "after you select an account, rather than showing an explicit error."
az ad app update --id "$APP_ID" --enable-id-token-issuance true

echo "Generating a client secret..."
if [ "$APPEND_SECRET" = true ]; then
    CLIENT_SECRET=$(az ad app credential reset \
        --id "$APP_ID" \
        --append \
        --years 1 \
        --query password \
        --output tsv)
else
    CLIENT_SECRET=$(az ad app credential reset \
        --id "$APP_ID" \
        --years 1 \
        --query password \
        --output tsv)
fi

echo "Storing the secret in Key Vault..."
az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "$SECRET_NAME" \
    --value "$CLIENT_SECRET" \
    --query id \
    --output tsv

KEY_VAULT_URI=$(az keyvault show --name "$KEY_VAULT_NAME" --query properties.vaultUri --output tsv)
KEY_VAULT_REFERENCE="@Microsoft.KeyVault(SecretUri=${KEY_VAULT_URI}secrets/${SECRET_NAME}/)"

echo "Setting the Static Web App's application settings (client ID plain, secret via Key Vault reference)..."
# Deliberately NOT using `az staticwebapp appsettings set` here — it has two
# separate, documented Azure CLI bugs that both apply directly to this exact
# call: it truncates any value after its first "=" sign (our Key Vault
# reference has one inside it), and when given multiple key=value pairs in
# one call, silently applies only the last one. Both are real, open issues
# on Azure/azure-cli and Azure/static-web-apps. Calling the REST API directly
# with a properly-constructed JSON body sidesteps both — there's no
# key=value string parsing involved at all.
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

jq -n \
    --arg secretSettingName "$SETTING_NAME" \
    --arg clientId "$APP_ID" \
    --arg secretRef "$KEY_VAULT_REFERENCE" \
    '{properties: {AAD_CLIENT_ID: $clientId, ($secretSettingName): $secretRef}}' \
    > /tmp/swa-appsettings.json

az rest \
    --method put \
    --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/staticSites/${SWA_NAME}/config/appsettings?api-version=2025-03-01" \
    --body @/tmp/swa-appsettings.json \
    > /dev/null

rm -f /tmp/swa-appsettings.json

TENANT_ID=$(az account show --query tenantId --output tsv)

echo ""
echo "Done. Both application settings are configured on the Static Web App."
echo "Values needed in staticwebapp.config.json:"
echo "  Application (client) ID:      $APP_ID"
echo "  Tenant ID:                     $TENANT_ID"
echo "  clientIdSettingName:           AAD_CLIENT_ID"
echo "  clientSecretSettingName:       $SETTING_NAME"
echo ""
echo "Client secrets expire after 1 year. Re-run this script with --append-secret before then to rotate it without an outage."
# Bootstrap Guide

## Overview

The bootstrap scripts automate the setup of a GitHub repository and Azure infrastructure required for AI-driven FinOps/SecOps operations. They configure OIDC federated authentication between GitHub Actions and Azure, enabling secure, keyless deployment without storing credentials in secrets.

**Note:** Bootstrap is optional. It provides a one-time setup utility to create the foundational infrastructure and GitHub/Azure integration needed for this repository to deploy resources to Azure.

## Prerequisites

### Required Tools

Before running bootstrap, ensure the following CLI tools are installed and authenticated:

- **GitHub CLI (`gh`)** — for repository and secret management
  - Install: https://cli.github.com/
  - Authenticate: `gh auth login`
  
- **Azure CLI (`az`)** — for Azure resource provisioning
  - Install: https://learn.microsoft.com/cli/azure/
  - Authenticate: `az login`

**Bash only:**
- **jq** — for JSON parsing in bootstrap.sh
  - Install: https://stedolan.github.io/jq/

### Permissions

- **GitHub:** Owner or admin rights to the organization where the repo will be created
- **Azure:** Owner or User Access Administrator role on the target subscription

## Usage

### Windows (PowerShell)

```powershell
.\bootstrap\Bootstrap.ps1 -Org <github-org> -Repo <repo-name> -SubscriptionId <azure-subscription-id> -Location <azure-location>
```

**Parameters:**
- `-Org` — GitHub organization name (e.g., `wsezu`)
- `-Repo` — Repository name (e.g., `ai-powered-ops`)
- `-SubscriptionId` — Azure subscription ID (e.g., `12345678-1234-1234-1234-123456789012`)
- `-Location` — Azure region (e.g., `westeurope`, `eastus`)

**Example:**
```powershell
.\bootstrap\Bootstrap.ps1 -Org wsezu -Repo ai-powered-ops -SubscriptionId "12345678-1234-1234-1234-123456789012" -Location westeurope
```

### Bash

```bash
./bootstrap/bootstrap.sh --org <github-org> --repo <repo-name> --subscription <azure-subscription-id> --location <azure-location>
```

**Parameters:**
- `--org` — GitHub organization name
- `--repo` — Repository name
- `--subscription` — Azure subscription ID
- `--location` — Azure region
- `-h, --help` — Show usage information

**Example:**
```bash
./bootstrap/bootstrap.sh --org wsezu --repo ai-powered-ops --subscription "12345678-1234-1234-1234-123456789012" --location westeurope
```

## What Bootstrap Creates

### 1. GitHub Repository

Creates a public GitHub repository with:
- Initial README file
- `.gitignore` configured for Visual Studio projects
- GPL-3.0 license

### 2. Azure Resources

#### Resource Group
- **Name pattern:** `rg-<repo>-prd-<location>-001`
- **Location:** User-specified (e.g., `westeurope`)
- **Purpose:** Container for all Azure resources related to this deployment

#### User-Assigned Managed Identity
- **Name pattern:** `id-<repo>-prd-<location>-001`
- **Purpose:** Azure service principal used by GitHub Actions for authentication
- **Advantage:** No credentials stored; authentication via OIDC token exchange

#### Federated Credential (GitHub OIDC)
- **Name:** `branch-main`
- **Subject:** Constructed from GitHub repository metadata for the `main` branch
- **Subject format:** `repo:<org>@<org-id>/<repo>@<repo-id>:ref:refs/heads/main`
- **Purpose:** Links GitHub's OIDC token provider to the Azure managed identity, enabling keyless authentication

### 3. GitHub Secrets

The bootstrap script creates three repository secrets required for GitHub Actions workflows:

| Secret | Value | Purpose |
|--------|-------|---------|
| `AZURE_CLIENT_ID` | Managed identity client ID | Identifies the Azure service principal |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | Targets the Azure subscription for deployments |
| `AZURE_TENANT_ID` | Azure tenant ID | Identifies the Azure AD tenant |

These secrets are referenced by GitHub Actions workflows to authenticate to Azure without storing credentials.

### 4. Role Assignment

- **Role:** Reader
- **Scope:** Entire Azure subscription
- **Assignee:** The managed identity created above
- **Purpose:** Allows the identity to read existing Azure resources; workflows can extend permissions with resource-specific role assignments as needed

## Security Model: OIDC Federated Authentication

Bootstrap configures **OpenID Connect (OIDC)** federated authentication, eliminating the need to store Azure credentials as GitHub secrets:

### How It Works

1. GitHub Actions workflow runs on the `main` branch
2. GitHub generates an OIDC token signed by GitHub's OIDC provider
3. Workflow exchanges the GitHub OIDC token for an Azure access token
4. Access token is used to authenticate to Azure, scoped to the federated credential's subject
5. No secrets are ever exposed in logs or stored long-term

### Benefits

- **No credential rotation required** — OIDC tokens are short-lived
- **Audit trail** — All deployments trace back to GitHub's OIDC token
- **Scope control** — Only the `main` branch can assume the identity; other branches are denied
- **No secrets management overhead** — No periodic credential updates or leakage risk

## Naming Convention

All Azure resources follow a consistent naming pattern:

```
<resource-type>-<repo>-<environment>-<location>-<instance>
```

For example:
- `id-ai-powered-ops-prd-westeurope-001` — Managed identity
- `rg-ai-powered-ops-prd-westeurope-001` — Resource group

**Components:**
- `<resource-type>` — Resource abbreviation (e.g., `id` for identity, `rg` for resource group)
- `<repo>` — Repository name
- `<environment>` — Fixed to `prd` (production)
- `<location>` — Azure region abbreviation or full name
- `<instance>` — Sequential instance number (e.g., `001`)

This naming convention is enforced in the bootstrap scripts and should be followed for consistency when manually creating additional resources.

## Post-Bootstrap Steps

After bootstrap completes successfully:

1. **Clone the repository** — Clone the newly created GitHub repo to your local machine
2. **Customize Bicep templates** — Add your infrastructure-as-code definitions in Bicep format
3. **Define GitHub Actions workflows** — Create workflows that use the `AZURE_*` secrets to deploy infrastructure
4. **Test deployment** — Create a PR with a test Bicep file and verify the CI workflow validates it
5. **Deploy** — Merge to `main` to trigger deployments (if deployment workflows are configured)

## Troubleshooting

### Bootstrap Script Fails

**Missing CLI Tools**
```
gh is required.
az is required.
jq is required. (Bash only)
```
Install the missing tool and authenticate before re-running bootstrap.

**Authentication Errors**
```
Error: You are not authorized to perform this action.
```
Verify you are logged in with sufficient permissions:
- GitHub: `gh auth status` (should show organization admin or owner)
- Azure: `az account show` (should show the correct subscription)

**Repository Already Exists**
```
Error: Repository already exists
```
Either delete the repository and re-run bootstrap, or manually configure it following the steps below.

### Manual Setup (If Bootstrap Fails)

If bootstrap cannot be run or fails partway through, you can perform these steps manually:

1. **Create GitHub repository:**
   ```bash
   gh repo create <org>/<repo> --add-readme --gitignore VisualStudio --license gpl-3.0 --public
   ```

2. **Get OIDC subject** (for the managed identity):
   ```bash
   gh api repos/<org>/<repo> --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id):ref:refs/heads/main"'
   ```

3. **Create Azure resource group:**
   ```bash
   az group create --location <location> --name rg-<repo>-prd-<location>-001 --subscription <subscription-id>
   ```

4. **Create managed identity:**
   ```bash
   az identity create --location <location> --name id-<repo>-prd-<location>-001 --resource-group rg-<repo>-prd-<location>-001 --subscription <subscription-id>
   ```

5. **Create federated credential:**
   ```bash
   az identity federated-credential create \
     --name branch-main \
     --identity-name id-<repo>-prd-<location>-001 \
     --resource-group rg-<repo>-prd-<location>-001 \
     --subscription <subscription-id> \
     --audience api://AzureADTokenExchange \
     --issuer https://token.actions.githubusercontent.com \
     --subject "repo:<org>@<org-id>/<repo>@<repo-id>:ref:refs/heads/main"
   ```

6. **Retrieve identity details:**
   ```bash
   az identity show --name id-<repo>-prd-<location>-001 --resource-group rg-<repo>-prd-<location>-001 --subscription <subscription-id>
   ```

7. **Create GitHub secrets:**
   ```bash
   gh secret set AZURE_CLIENT_ID --repo <org>/<repo> --body <client-id>
   gh secret set AZURE_SUBSCRIPTION_ID --repo <org>/<repo> --body <subscription-id>
   gh secret set AZURE_TENANT_ID --repo <org>/<repo> --body <tenant-id>
   ```

8. **Assign Reader role:**
   ```bash
   az role assignment create \
     --assignee-object-id <principal-id> \
     --assignee-principal-type ServicePrincipal \
     --role Reader \
     --scope /subscriptions/<subscription-id>
   ```

## Cleanup

To remove all resources created by bootstrap:

1. **Delete GitHub repository:**
   ```bash
   gh repo delete <org>/<repo>
   ```

2. **Delete Azure resource group** (removes managed identity and all resources within):
   ```bash
   az group delete --name rg-<repo>-prd-<location>-001 --subscription <subscription-id>
   ```

## References

- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Azure Managed Identities](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [GitHub CLI Docs](https://cli.github.com/manual/)
- [Azure CLI Docs](https://learn.microsoft.com/cli/azure/)

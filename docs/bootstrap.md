# Bootstrap Guide

## Overview

`bootstrap/` contains one-time (and, for the second pair, occasionally re-run) setup scripts for things that fall outside what the repeatable Bicep deployment can create on its own:

| Purpose | Bash | PowerShell |
|---|---|---|
| GitHub + Azure foundation, OIDC | `bootstrap.sh` | `Bootstrap.ps1` |
| Entra ID app registration for Static Web App auth | `setup_swa_auth.sh` | `Setup-SwaAuthentication.ps1` |

Both are optional in the sense that they're not part of the normal CI/CD deploy path, but both are required at least once for a new environment to actually work end to end.

## Why these are separate scripts, not part of the Bicep deployment

Both create things Bicep genuinely cannot: an Azure AD application registration (the Microsoft Graph Bicep extension for this exists, but is explicitly preview/experimental and has a documented, unresolved redeployment-idempotency bug — not worth the risk given how often this repo's infra gets redeployed), and a CI/CD identity that the *rest* of the deployment depends on already existing before it can authenticate at all.

## `bootstrap.sh` / `Bootstrap.ps1`

### What it creates

1. GitHub repository (`gh repo create`)
2. Azure resource group: `rg-<repo>-prd-<location>-001`
3. User-assigned managed identity: `id-<repo>-prd-<location>-001`
4. Two federated credentials on that identity:
   - `branch-main` (`ref:refs/heads/main`)
   - `pull-request` (`pull_request`)
5. GitHub repository **variables**:
   - `AZURE_CLIENT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_TENANT_ID`
6. Reader role assignment at subscription scope for the identity principal

Deliberately *not* set here: `DEPLOYMENT_LOCATION`, `FUNCTION_APP_NAME`, `DATA_STORAGE_ACCOUNT_NAME`, `STATIC_WEB_APP_NAME`. These depend on the Bicep deployment's own naming logic, which this script has no visibility into and shouldn't try to replicate — see `docs/workflows.md` for how the latter three actually get surfaced instead.

### Prerequisites

**CLI tools:**
- GitHub CLI (`gh`)
- Azure CLI (`az`)
- `jq` (Bash script only)

**Permissions:**
- GitHub org/repo creation permissions
- Azure permission to create identity/resources + role assignments

### Usage

```powershell
.\bootstrap\Bootstrap.ps1 -Org <org> -Repo <repo> -SubscriptionId <subscription-id> -Location <location>
```

```bash
./bootstrap/bootstrap.sh --org <org> --repo <repo> --subscription <subscription-id> --location <location>
```

**If you've forked this repo, or used GitHub's "Use this template" feature, rather than starting from nothing**: add `--skip-repo-creation` (bash) or `-SkipRepoCreation` (PowerShell). Without it, this script tries to create a brand-new, empty GitHub repository — which is correct for the very first setup of a new project, but wrong for anyone who already has a populated copy of this repo and just needs the Azure identity and OIDC federation set up for it. With the flag, the script verifies the repository you named actually exists and is accessible, then skips straight to the Azure identity steps.

### OIDC subjects used

- `repo:<org>@<org-id>/<repo>@<repo-id>:ref:refs/heads/main`
- `repo:<org>@<org-id>/<repo>@<repo-id>:pull_request`

These are built dynamically from GitHub repository metadata.

### Security model

- No static Azure client secret is stored.
- GitHub Actions authenticate using OIDC token exchange to the managed identity.
- Scope is constrained by federated credential subjects (main branch + pull request contexts).

## `setup_swa_auth.sh` / `Setup-SwaAuthentication.ps1`

### What it creates

1. An Entra ID App Registration (single-tenant, `AzureADMyOrg`), named `<swa-name>-auth` — reused on re-run rather than duplicated, so this script is safe to run again
2. The `User.Read` Microsoft Graph delegated permission on that app registration
3. **ID token issuance enabled** (`--enable-id-token-issuance true`) — required for the sign-in flow to complete at all; without it, login silently loops back to the account picker after consent rather than showing an explicit error
4. A client secret, generated fresh each run, stored in Key Vault as `<swa-name>-entra-client-secret` (named per-SWA, so multiple environments' secrets are distinguishable at a glance even though each lives in its own vault already)
5. Two application settings on the Static Web App: `AAD_CLIENT_ID` (plain) and `AAD_CLIENT_SECRET` (a Key Vault reference — set via a direct `az rest` call with a `jq`-constructed JSON body, not `az staticwebapp appsettings set`, which has two separate, documented CLI bugs that both apply directly here: it truncates any value after its first `=` character, and silently applies only the last of multiple key=value pairs passed in one call)
6. The redirect URI, derived from the Static Web App's actual current hostname (looked up fresh each run, not assumed) — self-corrects if the SWA is ever recreated and gets a new hostname

**Deliberately not done**: admin-consent (`az ad app permission grant`). That step exists purely to skip the individual consent prompt for every user in a tenant, and requires Global Admin rights to run. For a single-user app it solves a problem that doesn't exist — signing in without it still works, via the standard individual consent prompt on first login, which grants the same permission to your own account.

### Usage

```bash
./bootstrap/setup_swa_auth.sh \
  --swa-name <static-web-app-name> \
  --resource-group <resource-group-name> \
  --key-vault-name <key-vault-name>
```

Optional: `--append-secret`, for rotating an existing secret without an outage (adds a new one alongside the existing one, rather than replacing it outright).

### Prerequisites

- Azure CLI (`az`), `jq`
- Sufficient rights in the Azure AD tenant to create an app registration (does not require Global Admin, given the admin-consent step above is skipped)
- `Key Vault Secrets Officer` on the target Key Vault (see `docs/infra.md` — this is a data-plane RBAC role, separate from subscription-level Owner/Contributor, which does *not* grant Key Vault data access on its own)

### A real, non-obvious platform limitation this depends on

The Key Vault this script writes to must have open network access. Key Vault references cannot resolve secrets from a network-restricted vault when the calling app is a Static Web App — confirmed by direct, repeated testing (toggling the setting back and forth reproduced the failure and the fix cleanly each time), not just documentation. See `docs/infra.md` for the full reasoning.

## Cleanup

```bash
gh repo delete <org>/<repo>
az group delete --name rg-<repo>-prd-<location>-001 --subscription <subscription-id>
```

Deleting the resource group removes the Static Web App and Key Vault along with everything else, but the Entra ID app registration `setup_swa_auth.sh` created is *not* tied to any Azure resource and will need to be removed separately (`az ad app delete --id <app-id>`) if you want a fully clean tear-down.

## Troubleshooting

### Common failures

- Missing CLI dependency (`gh`, `az`, `jq`)
- Insufficient GitHub/Azure permissions
- Repository already exists
- `--skip-repo-creation`/`-SkipRepoCreation` used but the named repository doesn't exist or isn't accessible — the script checks for this explicitly and fails with a clear message before attempting anything else; double-check the org/repo name, or omit the flag if you actually need the repo created
- OIDC mismatch (missing/incorrect federated credential subject)
- Workflow failures due to missing repo variables (`vars.AZURE_*`)
- `setup_swa_auth.sh` failing with a CRLF-related shebang error (`/usr/bin/env: 'bash\r': No such file or directory`) on Windows — this means `.gitattributes` either hasn't been merged yet or your local checkout hasn't been renormalized against it. Fix: ensure `.gitattributes` is present on `main`, then run `git add --renormalize .` and commit.
- Login loops on the Static Web App after running `setup_swa_auth.sh` — check the Key Vault's network access setting first (must allow all networks, see above) before assuming it's an app registration problem.

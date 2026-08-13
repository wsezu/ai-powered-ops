# Copilot instructions for this repository

## Documentation

Detailed docs live in `docs/`:
- [`docs/bootstrap.md`](../docs/bootstrap.md) — one-time setup of GitHub repo + Azure OIDC infrastructure, and the Entra ID app registration for web frontend auth
- [`docs/infra.md`](../docs/infra.md) — Bicep infrastructure layout, types, variables, modules, and deployment commands
- [`docs/workflows.md`](../docs/workflows.md) — all nine CI/CD workflows: triggers, steps, variables, and conventions
- [`docs/function-app.md`](../docs/function-app.md) — Python Function App functions, endpoints, anomaly detection logic, and configuration
- [`docs/agents.md`](../docs/agents.md) — Foundry agent assets, setup script, and tool surface
- [`docs/web-frontend.md`](../docs/web-frontend.md) — chat frontend, authentication, and Markdown rendering

## Build, test, and lint commands

There is no application build system or unit-test runner. Validation is Bicep linting and Python linting.

**Bicep:**

| Purpose | Command |
|---|---|
| Lint one Bicep file | `az bicep lint --file <path-to-file.bicep> --diagnostics-format sarif` |
| Validate (compile) one Bicep file | `az bicep build --file <path-to-file.bicep>` |
| Validate one Bicep parameter file | `az bicep build-params --file <path-to-file.bicepparam>` |
| Lint all Bicep files (PowerShell) | `Get-ChildItem -Recurse -Filter *.bicep \| ForEach-Object { az bicep lint --file $_.FullName --diagnostics-format sarif }` |
| Validate all Bicep files (PowerShell) | `Get-ChildItem -Recurse -Filter *.bicep \| ForEach-Object { az bicep build --file $_.FullName }` |
| Validate all Bicep param files (PowerShell) | `Get-ChildItem -Recurse -Filter *.bicepparam \| ForEach-Object { az bicep build-params --file $_.FullName }` |

**Python:**

| Purpose | Command |
|---|---|
| Lint all Python files | `ruff check .` (config in `pyproject.toml` — `BLE001` is deliberately disabled there, not an oversight; see the comment in that file before re-enabling it) |
| Security scan Python files | `bandit -r . -x .venv,venv,.git,__pycache__` |
| Audit Python dependencies | `pip-audit` |

## High-level architecture

This repository is an AI-driven FinOps/SecOps architecture advisor on Azure: infrastructure-as-code, a Python anomaly-detection Function App, a Microsoft Foundry agent, and a web chat interface with Entra ID login. The core advisory loop is complete and working end to end; expansion (Advisor integration, Defender for Cloud, multi-agent) is ongoing.

1. **Bootstrap automation (`bootstrap/`)**: two script pairs. `Bootstrap.ps1`/`bootstrap.sh` perform the initial GitHub + Azure OIDC setup (repo, resource group, user-assigned identity, two federated credentials, repository variables, Reader role). `Setup-SwaAuthentication.ps1`/`setup_swa_auth.sh` create the Entra ID app registration the web frontend's auth depends on, store its client secret in Key Vault, and configure the Static Web App's app settings — re-runnable to rotate the secret. Neither creates the app registration via the Microsoft Graph Bicep extension; that extension is explicitly preview/experimental with a documented redeployment-idempotency bug. See `docs/bootstrap.md`.

2. **Infrastructure as code (`infra/`)**: subscription-scoped Bicep templates. Entry point is `infra/main.bicep` with `infra/main.bicepparam`. Deploys resource groups via AVM, then orchestrates four resource-group-scoped modules: `supporting_resources.bicep` (Log Analytics, Application Insights, user-assigned identity, hardened storage accounts, VNet/NSG), `function-app_resources.bicep` (Flex Consumption Function App), `foundry_resources.bicep` (AI Foundry account, model deployments, and RBAC), and `web_frontend_resources.bicep` (Key Vault + Static Web App with a linked backend). A fifth module, `event_grids.bicep`, wires blob-created events from storage to the Function App and is deployed separately by `deploy-event-grids.yml`, after the function code exists. Shared types are in `helpers/types.bicep`, shared constants (regions, role definition GUIDs) in `helpers/variables.bicep`. See `docs/infra.md`.

3. **Python Function App (`src/python/`)**: Azure Functions v2 app. Five functions:
   - `BlobCreatedEventGridFunction` — Event Grid trigger; reads FOCUS-format Parquet blobs, aggregates daily spend, detects anomalies (z-score, IQR, day-over-day, gated on both a minimum data-point floor and a minimum absolute dollar delta), merges updates per signal key with ETag-conditional retries, writes `latest.json` and daily history to the `normalized` container.
   - `GetLatestCostAnomalies` — HTTP GET; returns the current anomaly snapshot.
   - `GetCostAnomalyHistory` — HTTP GET; returns flagged signals with persistence streak counts.
   - `StorageHealthCheck` — HTTP GET; lists blobs in a container for diagnostics.
   - `ChatWithAgent` — HTTP POST, anonymous at the Functions level (the Static Web App's linked-backend auth is the real gate; this endpoint independently re-checks `x-ms-client-principal` as defense in depth); runs the actual conversation loop against the Foundry agent, dispatching tool calls directly to the same functions the GET endpoints use.
   Supporting logic in `anomaly_detection.py` (`signal_key`, `is_latest_flagged`, `compute_persistence`). See `docs/function-app.md`.

4. **Foundry agent (`agents/`)**: `cost-efficiency-advisor`, created/updated via `agents/cost-efficiency-advisor/setup_agent.py` using the current Foundry Agent Service API (`create_version` + `PromptAgentDefinition`), not the Assistants API (`azure-ai-agents`), which Microsoft is retiring. See `docs/agents.md`.

5. **Web frontend (`src/web/`)**: plain HTML/CSS/JS chat interface, no framework or build step, deployed to a Static Web App linked to the Function App as its backend. Whole app requires Entra ID login. See `docs/web-frontend.md`.

6. **CI/CD workflows (`.github/workflows/`)** — nine workflows: `validate-branch-name.yml`, `bicep-lint.yml`, `deploy-azure-resources.yml`, `deploy-event-grids.yml`, `deploy-function-app-apps.yml`, `deploy-web-frontend.yml`, `python-lint.yml`, `security-scan.yml`, `secret-scan.yml`. See `docs/workflows.md`.

## Key conventions specific to this repo

- **Branch naming is enforced in CI**: branch names must match `^(feature|bugfix|designfix|hotfix)\/[a-zA-Z0-9._-]+$`.
- **Bootstrap resource naming pattern**: `id-<repo>-prd-<location>-001` (identity), `rg-<repo>-prd-<location>-001` (resource group).
- **Infra resource naming pattern**: `<type>-<shortName>-<environment>-<regionShortName>-<instance>`, e.g. `rg-aiops-prd-weu-001`. Storage accounts use `stv2<shortName><environment><regionShortName>001` (no hyphens, max 24 chars).
- **Region references in Bicep**: always use `v.regions.<key>.location` from `helpers/variables.bicep` — never hardcode region strings.
- **Role definition IDs**: always use `v.roleDefinitionId.<key>` from `helpers/variables.bicep` — never hardcode GUIDs.
- **AVM modules**: resource modules are sourced from `br/public:avm/...` with pinned versions.
- **Optional Bicep parameters**: use the safe-access operator (`resource.?field`) when passing optional fields to AVM modules.
- **All Azure workflows use OIDC**: any workflow that calls Azure must include `id-token: write` permission and the `azure/login@v2` OIDC step.
- **Bootstrap scripts fail fast on missing dependencies** (`gh`, `az`, and `jq` for Bash).
- **Values only knowable as another module's output never belong in `.bicepparam`** — if a value (a linked backend's resource ID, an identity's `principalId`) is created in the same deployment, wire it through as a standalone module parameter fed from `main.bicep`, not a manually-pasted literal. Reserve manual placeholders in `.bicepparam` genuinely for identities external to this deployment (your own account, the CI/CD identity created by bootstrap).
- **Bicep for-expressions cannot be written directly as a value inside a function call** (e.g. `concat([...], [for x in y: {...}])`) or as a `.bicepparam` param value — compute the loop as its own `var` first, then reference that var.

## Hard-won lessons worth not re-discovering

- **Never reference an explicit agent version number in code — always by name only.** Foundry agent versions are addressable individually (`<agent_name>:<version>`), never automatically deleted, and remain independently callable by anyone holding Foundry User on the account, regardless of whether a newer version exists. `agent_reference: {name: ..., type: "agent_reference"}` (name only, no version) is what makes ChatWithAgent always resolve to the latest version automatically — keep it that way. If a version ever needs pinning for a real reason, that's a deliberate decision to make explicitly, with the security trade-off named at the time, not a default to reach for casually.
- **`Foundry User` must be assigned at the Foundry *account* scope, not the project scope.** Assigning it from the Portal's project blade can land the RBAC assignment at the narrower project scope, which fails with a generic `PermissionDenied` on agent operations that doesn't point at the scope as the cause.
- **Key Vault references cannot resolve secrets from a network-restricted vault when the calling app is a Static Web App.** Microsoft's docs describe a VNet-integration-based workaround for App Service/Functions, but it doesn't extend to Static Web Apps — confirmed by direct, repeated A/B testing (toggling the vault's network setting reproduced the failure and the fix cleanly both directions), not assumption. This is why `web_frontend_resources.bicep`'s Key Vault has open network access with RBAC as the real access control, deliberately, not by accident.
- **`az staticwebapp appsettings set` has two real, documented bugs**: it truncates any value after its first `=` character (breaks Key Vault reference strings, which have one built in), and passing multiple `key=value` pairs in one call silently applies only the last one. Use `az rest` with a `jq`-constructed JSON body against the `config/appsettings` REST endpoint instead.
- **`GITHUB_TOKEN` can never write repository Variables or Secrets, under any `permissions:` grant.** That scope doesn't exist for the auto-generated token, by design — it stops a workflow from rewriting the credentials that control its own execution. Don't try to fix this with more `permissions:`; if automating a variable write is genuinely necessary, it needs a PAT, and that PAT is itself a meaningfully sensitive credential worth thinking hard about before introducing.
- **Shell scripts need `.gitattributes` enforcing `eol=lf`.** Without it, a CRLF line ending corrupts the shebang line on checkout (`#!/usr/bin/env bash` becomes `#!/usr/bin/env bash\r`), and `env` reports it can't find a program literally named `bash\r`. Adding `.gitattributes` doesn't retroactively fix an already-checked-out working copy — `git add --renormalize .` is needed once, after the file is actually merged.
- **Foundry tool schemas with `strict: true` have three simultaneous requirements**, not one: `additionalProperties: false` on every object, every property in `required`, and optional properties expressed as nullable types rather than omitted from `required`. Missing any one produces `invalid_function_parameters`.
- **An Event Grid subscription's destination `resourceId` for an Azure Function must include `/functions/<name>`** — pointing at just the Function App's site resource ID fails with "Destination endpoint not found," and this only surfaces once the subscription is actually created, not at Bicep compile time.
- **The Python v2 programming model's entry point must be named `function_app.py`, not `main.py`.** A wrong filename produces "0 functions found" with no error anywhere — not in deployment logs, not in Application Insights, not in the Activity Log. This one cost real time to track down; check it early if functions aren't being discovered.
- **Azure CLI treats a leading `@` in some command arguments as "read from this file."** Not directly hit in this repo after switching to `az rest`, but worth remembering when constructing Key-Vault-reference-shaped strings (`@Microsoft.KeyVault(...)`) as CLI arguments elsewhere.

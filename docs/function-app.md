# Function App Guide

## Overview

The Function App code lives in `src/python/` and is deployed by `deploy-function-app-apps.yml`.

Primary file:
- `src/python/function_app.py`

Supporting logic:
- `src/python/anomaly_detection.py`

## Runtime and dependencies

- Python runtime: `3.12`
- Key dependencies (`requirements.txt`, all version-pinned with `~=`):
  - `azure-core`
  - `azure-functions`
  - `azure-identity`
  - `azure-ai-projects` — the current Foundry Agent Service SDK; not `azure-ai-agents`, which targets the Assistants API surface Microsoft is retiring
  - `azure-storage-blob`
  - `pandas`
  - `pyarrow`

`azure-monitor-opentelemetry` was removed early on — it was never imported directly, and its own transitive `opentelemetry-*` dependency tree was implicated in a documented class of "0 functions found" failures on Flex Consumption elsewhere, though it turned out not to be the actual cause here (see below).

The app uses managed identity for all storage access, and the same identity (via `DataStorage__clientId`) for authenticating to Foundry.

## Trigger and processing flow

### Event Grid trigger

`BlobCreatedEventGridFunction` runs when a new blob is created in the `focus-exports` container (scoped both by the Event Grid subscription's own filter and a code-side guard that checks the container name explicitly, as defense in depth).

Processing steps:

1. Read incoming parquet blob.
2. Validate required columns:
   - `ChargePeriodStart`
   - `SubAccountId`, `SubAccountName`, `ServiceName`
   - `EffectiveCost`, `BilledCost`
3. Aggregate daily spend per group dimensions.
4. Compute anomaly signals using:
   - z-score threshold (`z_score_threshold`, default 3.0)
   - IQR bounds (`iqr_multiplier`, default 1.5)
   - day-over-day threshold (`dod_pct_threshold`, default 0.50), gated additionally on `min_absolute_cost_delta` (default $0.01) — a large *percentage* swing on a sub-cent dollar amount doesn't get flagged, since it isn't financially meaningful regardless of how it looks statistically
   - a minimum data-point floor (`min_data_points_for_statistics`, default 10) below which a signal gets a `note` explaining insufficient history rather than a statistical verdict — small samples from freshly-provisioned landing zones produce misleadingly wide statistics otherwise
5. Merge updates per signal key (`SubAccountId`, `ServiceName`, `metric`) and write outputs to the normalized container:
   - `latest.json`
   - `history/<yyyy-mm-dd>.json`

Only blobs in the `focus-exports` container with a `.parquet` suffix are processed. The Event Grid subscription filters by container path prefix and file extension; the code-side check is a second, independent layer in case that filter is ever loosened.

Writes use ETag-conditional retries (`_upsert_merged_blob`) to avoid lost updates when multiple subscriptions' exports arrive close together — this matters because each subscription's export lands as a separate blob and triggers a separate invocation; without the merge logic, whichever invocation wrote last would silently overwrite every other subscription's data in `latest.json`.

All floating-point values are passed through `_finite_or_none()` before being included in output — `pd.isna()` alone doesn't catch `+inf`/`-inf` (which `pct_change()` produces from a zero baseline), and Python's `json.dumps()` serializes raw infinities as the bare token `Infinity`, which is not valid JSON per RFC 8259 and will fail to parse in any standards-compliant client.

## HTTP endpoints

### `GetLatestCostAnomalies`

- Route: `GET /api/GetLatestCostAnomalies`
- Auth level: `FUNCTION`
- Returns the latest anomaly snapshot (`latest.json`), merged across every subscription that has contributed data
- Returns 404 with `no_data` status if no snapshot exists yet

### `GetCostAnomalyHistory`

- Route: `GET /api/GetCostAnomalyHistory`
- Auth level: `FUNCTION`
- Optional query param: `lookback_days`
- Reads latest signals + historical snapshots and computes persistence streaks per signal key (`persistence_days` — how many consecutive snapshots a signal has stayed flagged)

### `StorageHealthCheck`

- Route: `GET /api/StorageHealthCheck`
- Auth level: `FUNCTION`
- Optional query param: `container`
- Lists blobs and returns count for health diagnostics

### `ChatWithAgent`

- Route: `POST /api/ChatWithAgent`
- Auth level: `ANONYMOUS` at the Functions runtime level — access is actually gated by the Static Web App's linked-backend authentication (Entra ID login), which auto-configures App Service Authentication on this Function App. See `docs/infra.md` for how that's wired.
- Request body: `{"message": "...", "conversation_id": "..."}` — `conversation_id` omitted on the first turn of a conversation; the client (see `src/web/`) holds and resends it for subsequent turns
- Response body: `{"conversation_id": "...", "reply": "..."}`

**Defense in depth**: before doing anything else, the handler checks for a valid `x-ms-client-principal` header (the one the Static Web App's authenticated proxy injects) and returns 401 if it's missing or malformed. This exists because `auth_level=ANONYMOUS` alone means the Function App's own runtime imposes no gate at all — the linked-backend EasyAuth configuration is what actually protects it, and this check means the application doesn't rely solely on an external platform configuration it can't independently verify at runtime.

**The agent turn loop** (`_run_agent_turn`): calls `openai_client.responses.create()` against the `cost-efficiency-advisor` agent (referenced by name via `agent_reference`, not a hardcoded version), checks the response for `function_call` items, executes each via `_execute_tool` (which dispatches directly to `_get_latest_cost_anomalies_data()` / `_get_cost_anomaly_history_data()` — the same functions the GET endpoints use, as plain Python calls with no HTTP round-trip), submits the results back, and repeats — capped at `max_tool_call_iterations` (default 5; the actual worst-case call count is 6, since the first call happens once before the loop starts).

## Storage/auth settings used by app

The function expects managed identity-based configuration:

- `DataStorage__blobServiceUri`
- `DataStorage__clientId`
- `AzureWebJobsStorage__blobServiceUri`
- `AzureWebJobsStorage__queueServiceUri`
- `AzureWebJobsStorage__tableServiceUri`
- `AzureWebJobsStorage__clientId`
- `AzureWebJobsStorage__credential=managedidentity`
- `FOUNDRY_PROJECT_ENDPOINT`

These are set through the infra module `infra/modules/function-app_resources.bicep`.

## Signal grouping and persistence

Signal groups are keyed by:

- `SubAccountId`
- `ServiceName`
- `metric`

Persistence is computed as consecutive days where the most recent day in the signal group remains flagged as anomalous.

## Why "0 functions found" happened, and what it wasn't

This app went through an extended period where the Functions runtime reported zero functions with no visible error anywhere — Application Insights, Activity Log, and the deployment logs all showed nothing wrong. Ruled out, with direct evidence rather than assumption, across that investigation:

- A NAT Gateway / outbound VNet egress issue (real, separate problem — fixed, but not the cause of this one)
- RBAC misconfiguration
- The deployed package's structure and contents (verified by extracting the actual deployed zip and importing it directly, twice, against two different builds)
- Flex Consumption itself, and even the subscription/tenant generally (ruled out via a minimal, dependency-free probe app that failed identically — twice, once in Python and once in Node.js)
- OpenTelemetry dependency version drift (a documented cause of a similar-looking symptom elsewhere; removing `azure-monitor-opentelemetry` didn't fix it here)

The actual cause: the entry-point file needed to be named `function_app.py`, not `main.py`, for the Python v2 programming model's worker to discover it at all. Once renamed, indexing worked immediately, on a build that hadn't otherwise changed.

## Local development notes

- `host.json` defines Functions host settings and extension bundle.
- `.funcignore` excludes local artifacts (`.venv`, `local.settings.json`, emulation files).

# Function App Guide

## Overview

The Function App code lives in `src/python/` and is deployed by `deploy-function-app.yml`.

Primary file:
- `src/python/function_app.py`

Supporting logic:
- `src/python/anomaly_detection.py`

## Runtime and dependencies

- Python runtime: `3.12`
- Key dependencies (`requirements.txt`):
  - `azure-functions`
  - `azure-identity`
  - `azure-storage-blob`
  - `pandas`
  - `pyarrow`
  - `azure-monitor-opentelemetry`

The app uses managed identity for all storage access.

## Trigger and processing flow

### Event Grid trigger

`BlobCreatedEventGridFunction` runs when a new blob is created in a storage container.

Processing steps:

1. Read incoming parquet blob.
2. Validate required columns:
   - `ChargePeriodStart`
   - `SubAccountId`, `SubAccountName`, `ServiceName`
   - `EffectiveCost`, `BilledCost`
3. Aggregate daily spend per group dimensions.
4. Compute anomaly signals using:
   - z-score threshold
   - IQR bounds
   - day-over-day threshold
5. Merge updates per signal key (`SubAccountId`, `ServiceName`, `metric`) and write outputs to normalized container:
   - `latest.json`
   - `history/<yyyy-mm-dd>.json`

Only blobs in the `focus-exports` container with a `.parquet` suffix are processed.

Writes use ETag-conditional retries to avoid lost updates when multiple exports arrive close together.

## HTTP endpoints

### `GetLatestCostAnomalies`

- Route: `GET /api/GetLatestCostAnomalies`
- Auth level: `FUNCTION`
- Returns latest anomaly snapshot (`latest.json`)
- Returns 404 with `no_data` status if no snapshot exists

### `GetCostAnomalyHistory`

- Route: `GET /api/GetCostAnomalyHistory`
- Auth level: `FUNCTION`
- Optional query param: `lookback_days`
- Reads latest signals + historical snapshots and computes persistence streaks per signal key

### `StorageHealthCheck`

- Route: `GET /api/StorageHealthCheck`
- Auth level: `FUNCTION`
- Optional query param: `container`
- Lists blobs and returns count for health diagnostics

## Storage/auth settings used by app

The function expects managed identity-based configuration:

- `DataStorage__blobServiceUri`
- `DataStorage__clientId`
- `AzureWebJobsStorage__blobServiceUri`
- `AzureWebJobsStorage__queueServiceUri`
- `AzureWebJobsStorage__tableServiceUri`
- `AzureWebJobsStorage__clientId`
- `AzureWebJobsStorage__credential=managedidentity`

These are set through the infra module `infra/modules/function-app_resources.bicep`.

It also receives `FOUNDRY_PROJECT_ENDPOINT` for the agent-facing functionality added in the app configuration.

## Signal grouping and persistence

Signal groups are keyed by:

- `SubAccountId`
- `ServiceName`
- `metric`

Persistence is computed as consecutive days where the most recent day in the signal group remains flagged as anomalous.

## Local development notes

- `host.json` defines Functions host settings and extension bundle.
- `.funcignore` excludes local artifacts (`.venv`, `local.settings.json`, emulation files).

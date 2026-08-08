from azure.core import MatchConditions
from azure.core.exceptions import ResourceExistsError, ResourceModifiedError, ResourceNotFoundError
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from datetime import datetime, timezone

import azure.functions as func
import pandas as pd

import io
import json
import logging
import math
import os
import time

from anomaly_detection import compute_persistence, is_latest_flagged, signal_key

group_dimensions = ["SubAccountId", "SubAccountName", "ServiceName"]
focus_exports_container = "focus-exports"
normalized_container = "normalized"
history_prefix = "history/"
history_lookback_days = int(os.environ.get("HISTORY_LOOKBACK_DAYS", "14"))
metrics = ["EffectiveCost", "BilledCost"]
dod_pct_threshold = 0.50
iqr_multiplier = 1.5
z_score_threshold = 3.0
min_data_points_for_statistics = int(os.environ.get("MIN_DATA_POINTS_FOR_STATISTICS", "10"))
min_absolute_cost_delta = float(os.environ.get("MIN_ABSOLUTE_COST_DELTA", "0.01"))

_blob_service_client: BlobServiceClient | None = None

def _get_blob_service_client() -> BlobServiceClient:
  global _blob_service_client
  if _blob_service_client is None:
    storage_account_name = os.environ["DataStorage__blobServiceUri"]
    client_id = os.environ.get("DataStorage__clientId")
    credential = DefaultAzureCredential(managed_identity_client_id=client_id) if client_id else DefaultAzureCredential()
    _blob_service_client = BlobServiceClient(account_url=storage_account_name, credential=credential)
  return _blob_service_client

def _aggregate_daily(df: pd.DataFrame) -> pd.DataFrame:
  group_cols = group_dimensions + ["ChargePeriodStart"]
  daily = df.groupby(group_cols, as_index=False)[metrics].sum()
  return daily.sort_values("ChargePeriodStart")

def _build_output(signals: list[dict], source_blob: str) -> dict:
  return {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "source_blob": source_blob,
    "signal_count": len(signals),
    "anomaly_count": sum(1 for s in signals if s.get("anomalies")),
    "signals": signals,
  }

def _finite_or_none(value: float) -> float | None:
  """pd.isna() catches NaN but not +/-inf (e.g. pct_change() from a zero baseline),
  and raw inf/-inf serialize as invalid JSON via json.dumps. math.isfinite() catches both."""
  return float(value) if math.isfinite(value) else None

def _compute_signals(daily: pd.DataFrame) -> list[dict]:
  results = []

  for dim_values, group in daily.groupby(group_dimensions):
    dim_values = dim_values if isinstance(dim_values, tuple) else (dim_values,)
    group = group.sort_values("ChargePeriodStart").reset_index(drop=True)

    for metric in metrics:
      series = group[metric]
      n = len(series)

      entry = {
        **dict(zip(group_dimensions, dim_values)),
        "metric": metric,
        "data_points": n,
        "latest_date": str(group["ChargePeriodStart"].iloc[-1]),
        "latest_value": float(series.iloc[-1]),
        "anomalies": [],
      }

      if n < min_data_points_for_statistics:
        entry["note"] = f"Insufficient data points for statistical signals (need >= {min_data_points_for_statistics} data points)."
        results.append(entry)
        continue

      mean, std = series.mean(), series.std(ddof=0)
      q1, q3 = series.quantile(0.25), series.quantile(0.75)
      iqr = q3 - q1
      lower_bound, upper_bound = q1 - iqr_multiplier * iqr, q3 + iqr_multiplier * iqr
      z_scores = (series - mean) / std if std > 0 else pd.Series([0.0] * n)
      dod_pct = series.pct_change()

      entry["mean"] = float(mean)
      entry["std_dev"] = float(std)
      entry["iqr_bounds"] = {"lower": float(lower_bound), "upper": float(upper_bound)}
      entry["latest_day_over_day_pct_change"] = _finite_or_none(dod_pct.iloc[-1])

      for i in range(n):
        value, z = float(series.iloc[i]), float(z_scores.iloc[i])
        dod = _finite_or_none(dod_pct.iloc[i])

        flags = []
        if abs(z) > z_score_threshold:
          flags.append("z_score")
        if value < lower_bound or value > upper_bound:
          flags.append("iqr")
        if dod is not None and abs(dod) >= dod_pct_threshold and abs(value - float(series.iloc[i - 1])) >= min_absolute_cost_delta:
          flags.append("day_over_day")

        if flags:
          entry["anomalies"].append({
            "date": str(group["ChargePeriodStart"].iloc[i]),
            "value": value,
            "z_score": round(z, 2),
            "day_over_day_pct_change": round(dod, 4) if dod is not None else None,
            "triggered_by": flags
          })

      results.append(entry)

  return results

def _read_focus_file(blob_name: str, container_name: str) -> pd.DataFrame:
  blob_client = _get_blob_service_client().get_blob_client(blob=blob_name, container=container_name)
  stream = blob_client.download_blob().readall()
  df = pd.read_parquet(io.BytesIO(stream))

  required = { "ChargePeriodStart", *group_dimensions, *metrics }
  missing = required - set(df.columns)
  if missing:
    raise ValueError(f"FOCUS file {blob_name} is missing the following required columns: {missing}")

  df["ChargePeriodStart"] = pd.to_datetime(df["ChargePeriodStart"]).dt.date
  for metric in metrics:
    df[metric] = df[metric].astype(float)

  return df

def _merge_signals(existing_signals: list[dict], new_signals: list[dict]) -> list[dict]:
  """Upserts new_signals into existing_signals, keyed the same way anomaly_detection
  matches signals across snapshots (SubAccountId, ServiceName, metric). This is what
  lets each subscription's export update only its own entries, leaving the other
  subscriptions' most recent data untouched."""
  merged = {signal_key(s): s for s in existing_signals}
  for s in new_signals:
    merged[signal_key(s)] = s
  return list(merged.values())

def _read_json_blob(container: str, blob_name: str) -> tuple[dict | None, str | None]:
  blob_client = _get_blob_service_client().get_blob_client(blob=blob_name, container=container)
  try:
    downloader = blob_client.download_blob()
    data = json.loads(downloader.readall())
    return data, downloader.properties.etag
  except ResourceNotFoundError:
    return None, None

def _upsert_merged_blob(container: str, blob_name: str, new_signals: list[dict], source_blob: str, max_attempts: int = 5) -> dict:
  """Reads the current blob (if any), merges in new_signals, and writes back —
  using ETag-conditional writes so two near-simultaneous exports (e.g. four
  subscriptions' daily exports landing within seconds of each other) can't
  silently overwrite one another. Retries on conflict rather than failing."""
  blob_client = _get_blob_service_client().get_blob_client(blob=blob_name, container=container)

  for attempt in range(max_attempts):
    existing, etag = _read_json_blob(container, blob_name)
    existing_signals = existing.get("signals", []) if existing else []
    merged_signals = _merge_signals(existing_signals, new_signals)
    output = _build_output(signals=merged_signals, source_blob=source_blob)
    payload = json.dumps(output, indent=2).encode("utf-8")

    try:
      if etag is None:
        blob_client.upload_blob(payload, overwrite=False)
      else:
        blob_client.upload_blob(payload, overwrite=True, etag=etag, match_condition=MatchConditions.IfNotModified)
      return output
    except (ResourceExistsError, ResourceModifiedError):
      if attempt == max_attempts - 1:
        raise
      time.sleep(0.5 * (attempt + 1))

  raise RuntimeError(f"Failed to write {blob_name} after {max_attempts} attempts due to concurrent updates.")

def _write_output(signals: list[dict], source_blob: str) -> dict:
  today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
  output = _upsert_merged_blob(normalized_container, "latest.json", signals, source_blob)
  _upsert_merged_blob(normalized_container, f"{history_prefix}{today}.json", signals, source_blob)
  return output

app = func.FunctionApp()

@app.function_name(name="BlobCreatedEventGridFunction")
@app.event_grid_trigger(arg_name="event")
def blob_created_event(event: func.EventGridEvent):
  blob_subject = event.subject
  blob_name = blob_subject.split('/blobs/')[1]
  container_name = blob_subject.split('/containers/')[1].split('/')[0]

  if container_name != focus_exports_container:
    logging.info(f"Ignoring blob event for container '{container_name}' — only '{focus_exports_container}' is processed.")
    return

  logging.info(f"Processing new FOCUS export {blob_name} in container {container_name}")

  try:
    df = _read_focus_file(blob_name=blob_name, container_name=container_name)
    daily = _aggregate_daily(df=df)
    signals = _compute_signals(daily=daily)

    source_blob = f"{container_name}/{blob_name}"
    updated_at = datetime.now(timezone.utc).isoformat()
    for s in signals:
      s["source_blob"] = source_blob
      s["updated_at"] = updated_at

    output = _write_output(signals=signals, source_blob=source_blob)
    logging.info(f"Normalization complete. {output['signal_count']} total signal groups ({len(signals)} updated by this export), {output['anomaly_count']} anomalies across all subscriptions.")
  except Exception as e:
    logging.error(f"Error processing FOCUS export {container_name}/{blob_name}: {e}")
    raise


@app.function_name(name="GetLatestCostAnomalies")
@app.route(route="GetLatestCostAnomalies", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
def get_latest_cost_anomalies(req: func.HttpRequest) -> func.HttpResponse:
  logging.info("GetLatestCostAnomalies trigger received.")

  try:
    blob_client = _get_blob_service_client().get_blob_client(blob="latest.json", container=normalized_container)

    if not blob_client.exists():
      return func.HttpResponse(
        json.dumps({
          "status": "no_data",
          "message": "No result available yet — waiting on the next scheduled export."}),
        status_code=404,
        mimetype="application/json",
      )

    raw = blob_client.download_blob().readall()
    return func.HttpResponse(raw, status_code=200, mimetype="application/json")
  except Exception as e:
    logging.error(f"The following exception occured while getting the latest results: {e}")
    return func.HttpResponse(
      json.dumps({
        "status": "error",
        "message": str(e)}),
      status_code=500,
      mimetype="application/json",
    )

@app.function_name(name="GetCostAnomalyHistory")
@app.route(route="GetCostAnomalyHistory", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
def get_cost_anomaly_history(req: func.HttpRequest) -> func.HttpResponse:
  logging.info("GetCostAnomalyHistory trigger received.")

  try:
    latest_client = _get_blob_service_client().get_blob_client(blob="latest.json", container=normalized_container)

    if not latest_client.exists():
      return func.HttpResponse(
        json.dumps({
          "status": "no_data",
          "message": "No result available yet — waiting on the next scheduled export."
        }),
        status_code=404,
        mimetype="application/json",
      )

    latest = json.loads(latest_client.download_blob().readall())
    current_signals = latest.get("signals", [])
    flagged_signals = [s for s in current_signals if is_latest_flagged(s)]

    if not flagged_signals:
      return func.HttpResponse(
        json.dumps({
          "status": "ok",
          "checked_snapshots": 0,
          "anomalies_with_persistence": [],
          "message": "No anomalies detected in the latest snapshot."
          }),
        status_code=200,
        mimetype="application/json",
      )

    try:
      lookback = int(req.params.get("lookback_days", history_lookback_days))
    except ValueError:
      lookback = history_lookback_days

    container_client = _get_blob_service_client().get_container_client(normalized_container)
    history_blobs = sorted(
      container_client.list_blobs(name_starts_with=history_prefix),
      key=lambda b: b.name,
      reverse=True,
    )[:lookback]

    history_snapshots = [
      json.loads(container_client.download_blob(b.name).readall()).get("signals", [])
      for b in history_blobs
    ]

    streaks = compute_persistence(current_signals, history_snapshots)

    anomalies_with_persistence = [
      {
        "SubAccountId": s.get("SubAccountId"),
        "SubAccountName": s.get("SubAccountName"),
        "ServiceName": s.get("ServiceName"),
        "metric": s.get("metric"),
        "latest_date": s.get("latest_date"),
        "latest_value": s.get("latest_value"),
        "persistence_days": streaks.get(signal_key(s), 1),
      }
      for s in flagged_signals
    ]

    result = {
      "status": "ok",
      "checked_snapshots": len(history_snapshots),
      "anomalies_with_persistence": anomalies_with_persistence,
    }
    return func.HttpResponse(json.dumps(result), status_code=200, mimetype="application/json")

  except Exception as e:
    logging.error(f"The following error occured while fetching the cost anomaly history: {e}")
    return func.HttpResponse(
      json.dumps({"status": "error", "message": str(e)}),
      status_code=500,
      mimetype="application/json",
    )


@app.function_name(name="StorageHealthCheck")
@app.route(route="StorageHealthCheck", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
def storage_health_check(req: func.HttpRequest) -> func.HttpResponse:
  logging.info("StorageHealthCheck trigger received.")

  container_name = req.params.get("container", normalized_container)

  try:
    container_client = _get_blob_service_client().get_container_client(container_name)
    blob_names = [b.name for b in container_client.list_blobs()]

    return func.HttpResponse(
      json.dumps({
        "status": "ok",
        "container": container_name,
        "blob_count": len(blob_names),
        "blobs": blob_names[:100],
      }),
      status_code=200,
      mimetype="application/json",
    )
  except Exception as e:
    logging.error(f"Storage health check failed for container '{container_name}': {e}")
    return func.HttpResponse(
      json.dumps({
        "status": "error",
        "container": container_name,
        "message": str(e),
      }),
      status_code=500,
      mimetype="application/json",
    )
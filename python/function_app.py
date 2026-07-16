from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from datetime import datetime, timezone

import io
import json
import logging
import os

import azure.functions as func
import pandas as pd

group_dimensions = [ "ServiceName", "SubscriptionId" ]
normalized_container = "normalized"
metrics = ["EffectiveCost", "BilledCost" ]
storage_account_name = os.environ["AzureWebJobsStorage__blobServiceUri"]

dod_pct_threshold = 0.50
iqr_multiplier = 1.5
z_score_threshold = 3.0

_credential = DefaultAzureCredential()
_blob_service_client = BlobServiceClient(account_url=storage_account_name, credential=_credential)

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

      if n < 3:
        entry["note"] = "Insufficient data points for statistical signals (need >= 3 data points)."
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
      entry["iqr_bounds"] = float(dod_pct.iloc[-1]) if not pd.isna(dod_pct.iloc[-1]) else None

      for i in range(n):
        value, z = float(series.iloc[i]), float(z_scores.iloc[i])
        dod = float(dod_pct.iloc[i]) if not pd.isna(dod_pct.iloc[i]) else None

        flags = []
        if abs(z) > z_score_threshold:
          flags.append("z_score")
        if value < lower_bound or value > upper_bound:
          flags.append("iqr")
        if dod is not None and abs(dod) >= dod_pct_threshold:
          flags.append("day_over_day")

        if flags:
          entry["anomalies"].append({
            "date": str(group["ChargePeriodStart"].iloc[i]),
            "value": value,
            "z_score": round(z, 2),
            "day_over_day_pct_change": round(dod, 4) if dod is not None else None,
            "triggered_by:": flags
          })

      results.append(entry)

  return results

def _read_focus_file(blob_name: str, container_name: str) -> pd.DataFrame:
  blob_client = _blob_service_client.get_blob_client(blob=blob_name, container=container_name)
  stream = blob_client.download_blob().readall()
  df = pd.read_parquet(io.BytesIO(stream))

  required = { "ChargePeriodStart", *group_dimensions, *metrics }
  missing = required - set(df.columns)
  if missing:
    raise ValueError(f"FOCUS file {blob_name} is missing the following required columns: {missing}")

  df["ChargePeriodStart"] = pd.to_datetime(df["ChargePeriodStart"]).dt.date
  return df

def _write_output(output: dict) -> None:
  payload = json.dumps(output, indent=2).encode("utf-8")
  timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

  _blob_service_client.get_blob_client(blob="latest.json", container=normalized_container).upload_blob(payload, overwrite=True)
  _blob_service_client.get_blob_client(blob=f"history/{timestamp}.json", container=normalized_container).upload_blob(payload, overwrite=True)

app = func.FunctionApp()

@app.function_name(name="BlobCreatedEventGridFunction")
@app.event_grid_trigger(arg_name="event")
def blob_created_event(event: func.EventGridEvent):
  blob_subject = event.subject
  blob_name = blob_subject.split('/blobs/')[1]
  container_name = blob_subject.split('/containers/')[1].split('/')[0]

  if(blob_name.endswith(".parquet") and container_name == normalized_container):
    logging.info(f"Processing new FOCUS export {blob_name} in container {container_name}")

    try:
      df = _read_focus_file(blob_name=blob_name, container_name=container_name)
      daily = _aggregate_daily(df=df)
      signals = _compute_signals(daily=daily)
      output = _build_output(signals=signals, source_blob=f"{container_name}/{blob_name}")
      _write_output(output=output)
      logging.info(f"Normalization complete. {len(output['signals'])} signal groups with {output['anomaly_count']} anomalies.")
    except Exception as e:
      logging.error(f"Error processing FOCUS export {container_name}/{blob_name}: {e}")
      raise
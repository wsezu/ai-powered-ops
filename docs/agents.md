# Agents Guide

## Overview

`agents/` contains Microsoft Foundry prompt-agent assets. The repository currently has one agent package:

- `agents/cost-efficiency-advisor/`

## Cost Efficiency Advisor

This agent is a FinOps advisor for the Azure environment represented by this repo. It is designed to:

- read current cost anomaly snapshots
- evaluate persistence across snapshots
- recommend cost actions while weighing availability, performance, and security/risk

### Files

- `instructions.md` — the agent's system instructions and response framework
- `tools.json` — tool definitions exposed to the agent
- `setup_agent.py` — creates or updates the Foundry prompt agent definition
- `requirements.txt` — Python dependencies needed to run the setup script

### Behavior

- The agent uses `get_latest_cost_anomalies` for the full current signal set.
- The agent uses `get_cost_anomaly_history` for flagged signals plus `persistence_days`.
- It does not have Azure Advisor or security-posture data.
- It must stay advisory only and never claim to have changed Azure resources.

### Setup script

`setup_agent.py` creates a new version of the same named Foundry agent each time it runs.

Required environment variable:

- `FOUNDRY_PROJECT_ENDPOINT`

Optional environment variable:

- `FOUNDRY_MODEL_DEPLOYMENT` (defaults to `gpt-5.1`)

The script authenticates with `DefaultAzureCredential`, so it can run locally after `az login` or in OIDC-backed workflows.

## Related infrastructure

The agent depends on the Foundry project and model deployments defined in `infra/main.bicepparam`.


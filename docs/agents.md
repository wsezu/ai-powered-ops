# Agents Guide

## Overview

`agents/` contains Microsoft Foundry prompt-agent assets. The repository currently has one agent package:

- `agents/cost-efficiency-advisor/`

## Cost Efficiency Advisor

This agent is a FinOps and SecOps advisor for the Azure environment represented by this repo. It is designed to:

- read current cost anomaly snapshots
- evaluate persistence across snapshots
- read currently open Microsoft Defender for Cloud security recommendations
- recommend cost actions while weighing availability, performance, and security/risk against real data, not general assumption

### Files

- `instructions.md` — the agent's system instructions and response framework
- `tools.json` — tool definitions exposed to the agent
- `setup_agent.py` — creates or updates the Foundry prompt agent definition
- `requirements.txt` — Python dependencies needed to run the setup script

### Behavior

- The agent uses `get_latest_cost_anomalies` for the full current signal set.
- The agent uses `get_cost_anomaly_history` for flagged signals plus `persistence_days`.
- The agent uses `get_security_recommendations` for currently open Microsoft Defender for Cloud recommendations across every subscription it has visibility into, and is instructed to ground the security/risk dimension of a cost trade-off in this data when relevant, rather than reasoning about security in the abstract.
- It does not have Azure Advisor data. Security-posture data, by contrast, *is* available — don't describe this agent as lacking it.
- It is explicitly scoped to FinOps/SecOps for this environment and instructed to decline and redirect anything unrelated, regardless of how the request is phrased — added after testing showed the agent would otherwise answer general-knowledge questions unrelated to its actual purpose.
- It must stay advisory only and never claim to have changed Azure resources.
- Confidence is explicitly tied to `data_points` and `persistence_days` for cost signals, or `severity` for security recommendations (which don't have a persistence concept the way cost signals do) — a signal flagged once is treated as a candidate to watch, not to act on.

### Tool schema requirements

All three tools in `tools.json` are declared `strict: true` in `setup_agent.py`, which means their JSON schemas must satisfy three requirements together (missing any one produces a real, if initially confusing, `invalid_function_parameters` error from the Foundry API):

1. `additionalProperties: false` on every object in the schema, including ones with no properties at all.
2. Every property listed in `properties` must also appear in `required`.
3. A logically optional property (like `get_cost_anomaly_history`'s `lookback_days`) is expressed as a nullable type (`["integer", "null"]`), not by omitting it from `required` — the agent will always send the key, typically as `null` when it wants the server-side default. `_execute_tool` already handles this correctly (`arguments.get("lookback_days")` on `{"lookback_days": None}` returns `None`, which the underlying function already treats as "use the default").

`get_latest_cost_anomalies` and `get_security_recommendations` both take no parameters at all — their schemas satisfy requirement 2 trivially (nothing in `properties` means nothing needs to be in `required`), but requirement 1 still applies to them regardless of having zero properties.

### Setup script

`setup_agent.py` uses the current Foundry Agent Service API (`AIProjectClient.agents.create_version()` with a `PromptAgentDefinition`) — deliberately not the Assistants API surface (`azure-ai-agents`'s `AgentsClient.create_agent()`), which Microsoft is retiring. `create_version()` creates a new version of the same named agent each time it runs rather than erroring or duplicating; callers reference the agent by name and always get whichever version is current, so there's no separate "which version is live" tracking needed anywhere.

Required environment variable:

- `FOUNDRY_PROJECT_ENDPOINT` — e.g. `https://fa-aiops-prd-weu-001.services.ai.azure.com/api/projects/proj-aiops-prd-weu-001`

Optional environment variable:

- `FOUNDRY_MODEL_DEPLOYMENT` (defaults to `gpt-5.1`)

The script authenticates with `DefaultAzureCredential`, so it can run locally after `az login` or in OIDC-backed workflows. Either identity needs the **Foundry User** role — assigned at the Foundry **account** scope, not the project scope. This is a real, easy-to-hit mistake: assigning it from the Portal's project blade can land the RBAC assignment at the narrower project scope, which is not sufficient — the error in that case is a generic `PermissionDenied`, not something that points at the scope specifically.

**This now runs in CI (`deploy-agent.yml`), not just locally.** Running it from a human's local clone has a real failure mode: the script reads `tools.json`/`instructions.md` from whatever's on disk relative to itself, with zero awareness of what's actually merged on `origin/main`. A stale, un-pulled local checkout deploys old tool definitions while reporting success, with no error anywhere pointing at the actual cause — this happened once and cost a real debugging session. A workflow checking out `main` fresh on every run is definitionally never stale. Running it locally is still fine for iterating on a change before merging; just don't treat a local run's success as confirmation of what's on `main`.

## How the agent actually gets invoked

`setup_agent.py` only creates/updates the agent's *definition* — it's a one-time or occasional setup step, not something that runs per conversation. The actual runtime invocation happens through the Function App's `ChatWithAgent` endpoint (`src/python/function_app.py`), which:

1. Creates or continues a Foundry conversation (`openai_client.conversations`)
2. Calls `responses.create()` with `agent_reference` pointing at `cost-efficiency-advisor` by name
3. Executes any requested tool calls directly against the same data functions the `GetLatestCostAnomalies`/`GetCostAnomalyHistory`/`GetSecurityRecommendations` HTTP endpoints use — no HTTP round-trip, since it's the same codebase
4. Submits tool outputs back and repeats until the agent returns a plain text reply

See `docs/function-app.md` for the endpoint's request/response contract and the auth model that protects it.

## Related infrastructure

The agent depends on the Foundry project and model deployments defined in `infra/main.bicepparam`, and on the RBAC grants described in `docs/infra.md`:

- **Foundry User**, granted to both the Function App's identity and the CI/CD identity, at the Foundry account scope — needed for the agent's own operation (both creating versions and being invoked).
- **Security Reader**, granted to the Function App's identity individually across all four subscriptions (`infra/modules/security_reader_role_assignments.bicep`) — needed specifically for `get_security_recommendations`'s Resource Graph query. Not scoped at a management group, despite that initially looking like the simpler option — a subscription-scoped deployment can't reach upward to grant a role at a parent management group; only downward, to subscriptions/resource groups at or below its own scope. Four individual subscription-scoped assignments is the correct pattern here, not a workaround for one.

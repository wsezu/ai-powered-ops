# AI powered Ops

AI powered **FinOps + SecOps architecture advisor** on Azure, combining infrastructure-as-code, a Python anomaly-detection Function App, a Microsoft Foundry agent, and a web chat interface with real Entra ID login.

The core advisory loop — detect anomalies, reason about them with an agent, chat with it through a browser — is complete and working end to end, now grounded in real data from Microsoft Defender for Cloud and Azure Advisor as well as the platform's own cost signals. A broader multi-agent setup remains a deliberate non-goal until there's genuine tool-count pressure or conflicting priorities to justify it, not a default next step.

## What this repository is

This is an **operations platform repository**, not a traditional web/API app codebase. It contains:

- Azure infrastructure definitions in Bicep
- A Python Azure Function that processes FOCUS exports, detects anomalies, and hosts both the read APIs and the agent-facing chat endpoint
- A Microsoft Foundry agent (definition, tools, and setup script)
- A plain HTML/CSS/JS chat frontend, deployed to a Static Web App with Entra ID authentication
- GitHub Actions workflows for validation, deployment, and security checks
- Bootstrap automation for first-time GitHub + Azure setup, and for the Entra ID app registration the web frontend's auth depends on

## What gets deployed

From `infra/`, the platform deploys:

- resource group(s)
- virtual network + network security group
- two storage accounts (data + function package/runtime)
- Log Analytics + Application Insights (connected to the Foundry project for agent tracing)
- user-assigned managed identity, with Security Reader and Reader roles across every subscription in scope — needed for the agent's Defender for Cloud and Azure Advisor tools respectively
- Linux Function App and App Service plan (Flex Consumption)
- Azure AI Foundry account + model deployments
- Key Vault (holding the web frontend's Entra ID client secret)
- Static Web App (Standard tier, linked to the Function App as its backend)

From `src/python/`, the Function App provides:

- Event Grid-driven normalization/anomaly analysis pipeline
- HTTP endpoints to read latest anomaly signals, anomaly persistence history, storage health, currently open Defender for Cloud recommendations, and currently active Azure Advisor recommendations
- A chat endpoint (`ChatWithAgent`) that runs the actual conversation loop against the Foundry agent

From `agents/`, a Foundry prompt agent (`cost-efficiency-advisor`) reasons about cost trade-offs against availability, performance, and security — grounding each dimension in real data (Defender for Cloud for security, Azure Advisor for availability and performance) rather than general assumption, and advisory only, never claiming to have changed anything.

From `src/web/`, a chat interface — no framework, no build step — that talks to the Function App through the Static Web App's linked backend, behind Entra ID login.

## Repository layout

| Path | Purpose |
|---|---|
| `agents/` | Foundry agent definition, tool schemas, and setup script |
| `bootstrap/` | One-time setup scripts: GitHub/Azure foundation + OIDC, and the Entra ID app registration for web frontend auth |
| `infra/` | Subscription-scoped Bicep templates and modules |
| `src/python/` | Azure Functions Python app (anomaly detection, HTTP endpoints, chat endpoint) |
| `src/web/` | Static chat frontend, deployed to the Static Web App |
| `.github/workflows/` | CI/CD, infra/function/frontend/agent deploy, lint/security/secret scans |
| `docs/` | Detailed documentation for bootstrap, infrastructure, workflows, function app, agents, and the web frontend |

## How it works

1. Bootstrap creates repository/security prerequisites, including the Entra ID app registration for web auth.
2. Infrastructure is validated on PRs and deployed from `main`.
3. Function App code is deployed from `main` when `src/python/**` changes.
4. Event Grid wiring deploys after the Function App code exists (its destination references a specific function by name).
5. The web frontend deploys from `main` when `src/web/**` changes.
6. The agent's definition (instructions and tools) deploys from `main` when `agents/cost-efficiency-advisor/**` changes.
7. Incoming FOCUS exports are processed and anomaly outputs are stored, served via HTTP functions, and reasoned about — alongside real security and Advisor data — by the Foundry agent when someone chats with it through the web interface.

## Progress

1. Bootstrap — done
2. Deploy infra — done
3. Implement agent — done
4. Implement chat interface — done
5. Ground the agent in real security and Advisor data (Defender for Cloud, Azure Advisor) — done
6. Multi-agent setup — deliberately not planned unless genuine tool-count pressure or conflicting priorities emerge to justify it

## Documentation

- [Bootstrap guide](docs/bootstrap.md)
- [Infrastructure guide](docs/infra.md)
- [Workflows guide](docs/workflows.md)
- [Function app guide](docs/function-app.md)
- [Agents guide](docs/agents.md)
- [Web frontend guide](docs/web-frontend.md)

## Quick start

1. Read [docs/infra.md](docs/infra.md) for architecture and deployment topology.
2. Read [docs/workflows.md](docs/workflows.md) for CI/CD behavior and required GitHub configuration.
3. Read [docs/function-app.md](docs/function-app.md) for runtime behavior and endpoints.
4. Read [docs/agents.md](docs/agents.md) and [docs/web-frontend.md](docs/web-frontend.md) for the agent and chat interface.
5. Use [docs/bootstrap.md](docs/bootstrap.md) if you need to set up a new repo/subscription foundation, or the Entra ID app registration for a new environment's web frontend.

# AI powered Ops

AI-driven **FinOps + SecOps architecture advisor** on Azure, combining infrastructure-as-code, a Python anomaly-detection Function App, and CI/CD guardrails.

This repo is still a **work in progress**: the core platform is in place, but the advisor experience is not complete yet.

## What this repository is

This is an **operations platform repository**, not a traditional web/API app codebase. It contains:

- Azure infrastructure definitions in Bicep
- A Python Azure Function that processes FOCUS exports and exposes anomaly APIs
- GitHub Actions workflows for validation, deployment, and security checks
- Optional bootstrap automation for first-time GitHub + Azure setup

## What gets deployed

From `infra/`, the platform deploys:

- resource group(s)
- virtual network + network security group
- two storage accounts (data + function package/runtime)
- Log Analytics + Application Insights
- user-assigned managed identity
- Linux Function App and App Service plan
- Azure AI Foundry account + model deployments

From `src/python/`, the Function App provides:

- Event Grid-driven normalization/anomaly analysis pipeline
- HTTP endpoints to read latest anomaly signals, anomaly persistence history, and storage health

## Repository layout

| Path | Purpose |
|---|---|
| `bootstrap/` | Optional one-time setup scripts for GitHub/Azure foundation and OIDC |
| `infra/` | Subscription-scoped Bicep templates and modules |
| `src/python/` | Azure Functions Python app (anomaly detection logic + HTTP endpoints) |
| `.github/workflows/` | CI/CD, infra deploy, function deploy, lint/security/secret scans |
| `docs/` | Detailed documentation for bootstrap, infrastructure, workflows, and function app |

## How it works

1. Optional bootstrap creates repository/security prerequisites.
2. Infrastructure is validated on PRs and deployed from `main`.
3. Function App code is deployed from `main` when `src/python/**` changes.
4. Incoming FOCUS exports are processed and anomaly outputs are stored + served via HTTP functions.

## Progress

1. Bootstrap — done
2. Deploy infra — done
3. Implement agents — work in progress
4. Implement chat interface — planned

## Documentation

- [Bootstrap guide](docs/bootstrap.md)
- [Infrastructure guide](docs/infra.md)
- [Workflows guide](docs/workflows.md)
- [Function app guide](docs/function-app.md)
- [Agents guide](docs/agents.md)

## Quick start

1. Read [docs/infra.md](docs/infra.md) for architecture and deployment topology.
2. Read [docs/workflows.md](docs/workflows.md) for CI/CD behavior and required GitHub configuration.
3. Read [docs/function-app.md](docs/function-app.md) for runtime behavior and endpoints.
4. Use [docs/bootstrap.md](docs/bootstrap.md) if you need to set up a new repo/subscription foundation.

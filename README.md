# AI powered Ops

AI-driven **FinOps + SecOps architecture advisor** for Azure, built with Bicep, GitHub Actions, and optional bootstrap automation.

## Overview

This repository defines the infrastructure and guardrails for an Azure-based AI operations platform. It is not an application codebase; instead, it provides:

- **Bootstrap automation** to create the GitHub + Azure foundation needed for secure deployments
- **Bicep infrastructure** for Azure resource groups, monitoring, storage, a Python Function App, and AI Foundry resources
- **GitHub Actions workflows** for validation, deployment, branch policy, Python quality checks, and secret scanning

## How it fits together

1. Bootstrap sets up the GitHub repository, Azure identity, and OIDC trust.
2. `infra/main.bicep` deploys the Azure foundation.
3. GitHub Actions validates infrastructure changes on pull requests.
4. Approved changes deploy from `main`.

## Repository structure

| Path | Purpose |
|---|---|
| `bootstrap/` | Optional one-time setup scripts for GitHub repo creation, Azure identity setup, federated credentials, and required secrets |
| `infra/` | Subscription-scoped Bicep templates for resource groups, supporting Azure services, a Python Function App stack, and AI Foundry resources |
| `.github/workflows/` | Branch validation, Bicep linting, deployment, Python linting/security scans, and secret scanning |
| `docs/` | Detailed guides for bootstrap, infrastructure, and workflows |

## Key components

### Bootstrap

Use the scripts in `bootstrap/` when you need to create the repository foundation from scratch. They create:

- the GitHub repository
- an Azure resource group
- a user-assigned managed identity
- GitHub OIDC federated credentials for `main` deployments and pull request validation
- the GitHub secrets used by the workflows

See [docs/bootstrap.md](docs/bootstrap.md).

### Infrastructure

The Bicep templates in `infra/` deploy:

- resource groups
- Log Analytics Workspace
- Application Insights
- user-assigned identity
- storage account and containers
- Linux Function App and App Service plan
- AI Foundry account and model deployments

See [docs/infra.md](docs/infra.md).

### Workflows

The workflows in `.github/workflows/` enforce:

- branch naming rules
- Bicep linting and validation
- infrastructure deployment
- Python linting
- Python security scanning
- secret scanning

See [docs/workflows.md](docs/workflows.md).

## Getting started

If you are new to the repo:

1. Read this README for the big picture.
2. Read [docs/bootstrap.md](docs/bootstrap.md) if you want to create the GitHub/Azure foundation.
3. Read [docs/infra.md](docs/infra.md) if you want to understand or change the infrastructure.
4. Read [docs/workflows.md](docs/workflows.md) if you want to understand CI/CD behavior.

## Notes

- Bootstrap is optional.
- Azure deployments use GitHub OIDC; credentials are not stored in the repo.
- Infrastructure changes are expected to go through pull requests and workflow validation.

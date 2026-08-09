"""
Creates a new version of the "cost-efficiency-advisor" agent in Microsoft
Foundry, using the current Foundry Agent Service API (prompt agents via
create_version) — NOT the Assistants API, which Microsoft is retiring on
August 26, 2026.

Safe to re-run: create_version() creates a new version (1, 2, 3, ...) of the
same named agent each time rather than erroring or duplicating ambiguously.
Callers reference the agent by name alone and automatically get whatever
version is current, so there's no separate "which version is live" tracking
needed here.

Required environment variable:
  FOUNDRY_PROJECT_ENDPOINT   e.g. https://fa-aiops-prd-weu-001.services.ai.azure.com/api/projects/proj-aiops-prd-weu-001
                             (account name + project name come from
                             infra/main.bicepparam's foundryAccount.aiFoundryConfiguration)

Optional:
  FOUNDRY_MODEL_DEPLOYMENT   defaults to "gpt-5.1" — must match a model
                             deployment name already provisioned in
                             infra/main.bicepparam's foundryAccount.aiModelDeployments

Authenticates via DefaultAzureCredential — run locally while signed in via
`az login`, or from a workflow authenticated via OIDC. Either identity needs
the Foundry User role, assigned at the Foundry *account* scope (not the
project scope — that's a real, easy-to-hit mistake; see
infra/main.bicepparam's foundryAccount.aiFoundryConfiguration.roleAssignments).
"""

import json
import os
import sys
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import FunctionTool, PromptAgentDefinition, Tool
from azure.identity import DefaultAzureCredential

AGENT_NAME = "cost-efficiency-advisor"
AGENT_DIR = Path(__file__).parent


def _load_instructions() -> str:
    return (AGENT_DIR / "instructions.md").read_text(encoding="utf-8")

def _load_tools() -> list[Tool]:
    raw_tools = json.loads((AGENT_DIR / "tools.json").read_text(encoding="utf-8"))
    tools: list[Tool] = []
    for entry in raw_tools:
        fn = entry["function"]
        tools.append(
            FunctionTool(
                name=fn["name"],
                description=fn.get("description"),
                parameters=fn.get("parameters"),
                strict=True,
            )
        )
    return tools

def main() -> None:
    endpoint = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
    if not endpoint:
        print("FOUNDRY_PROJECT_ENDPOINT environment variable is required.", file=sys.stderr)
        sys.exit(1)

    model = os.environ.get("FOUNDRY_MODEL_DEPLOYMENT", "gpt-5.1")
    instructions = _load_instructions()
    tools = _load_tools()

    project = AIProjectClient(endpoint=endpoint, credential=DefaultAzureCredential())

    agent_version = project.agents.create_version(
        agent_name=AGENT_NAME,
        definition=PromptAgentDefinition(
            model=model,
            instructions=instructions,
            tools=tools,
        ),
    )

    print(f"Created '{agent_version.name}' version {agent_version.version} (id={agent_version.id}).")


if __name__ == "__main__":
    main()
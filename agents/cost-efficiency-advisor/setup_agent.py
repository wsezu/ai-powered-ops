"""
Creates or updates the "cost-efficiency-advisor" agent in Microsoft Foundry.

Safe to re-run: if an agent with this name already exists, it's updated in
place rather than duplicated — so this can run every time instructions.md or
tools.json changes, whether from your own machine or a CI workflow.

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
the Foundry User role on the Foundry account (see
infra/main.bicepparam's foundryAccount.aiFoundryConfiguration.roleAssignments).
"""

import json
import os
import sys
from pathlib import Path

from azure.ai.agents import AgentsClient
from azure.ai.agents.models import FunctionDefinition, FunctionToolDefinition
from azure.identity import DefaultAzureCredential

AGENT_NAME = "cost-efficiency-advisor"
AGENT_DIR = Path(__file__).parent


def _load_instructions() -> str:
    return (AGENT_DIR / "instructions.md").read_text(encoding="utf-8")


def _load_tools() -> list[FunctionToolDefinition]:
    raw_tools = json.loads((AGENT_DIR / "tools.json").read_text(encoding="utf-8"))
    tools = []
    for entry in raw_tools:
        fn = entry["function"]
        tools.append(
            FunctionToolDefinition(
                function=FunctionDefinition(
                    name=fn["name"],
                    description=fn.get("description"),
                    parameters=fn.get("parameters"),
                )
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

    client = AgentsClient(endpoint=endpoint, credential=DefaultAzureCredential())

    existing = next((a for a in client.list_agents() if a.name == AGENT_NAME), None)

    if existing is not None:
        agent = client.update_agent(
            agent_id=existing.id,
            model=model,
            instructions=instructions,
            tools=tools,
        )
        print(f"Updated existing agent '{AGENT_NAME}' (id={agent.id}).")
    else:
        agent = client.create_agent(
            model=model,
            name=AGENT_NAME,
            instructions=instructions,
            tools=tools,
        )
        print(f"Created new agent '{AGENT_NAME}' (id={agent.id}).")


if __name__ == "__main__":
    main()

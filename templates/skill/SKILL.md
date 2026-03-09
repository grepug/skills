---
name: example-skill
description: One-sentence summary of what this skill helps an agent do and when it should be used.
---

# Example Skill

Short description of the job this skill performs.

## Use when

- The user asks for this exact workflow
- The task matches this skill's domain closely

## Prerequisites

- Required tools, accounts, or platform limits
- Any files or environment that must exist before running

## Confirm before acting

The agent should confirm:

- the target project or file
- any destructive or irreversible action
- required inputs such as version, environment, or destination

## Workflow

1. Discover the current state and gather the minimum required inputs.
2. Show a short dry-run summary before any risky action.
3. Run the local helper files if needed.
4. Report outputs, artifact paths, and any next step the user must take.

## Output

- What success looks like
- Where artifacts or logs are written
- What the user should verify afterwards

## Bundled files

- `scripts/example.sh` — optional helper script
- `assets/example.txt` — optional static asset
- `references/example.md` — optional background reference

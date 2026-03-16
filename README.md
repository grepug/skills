# Agent Skills Catalog

Public, installable skills for coding agents.

This repository is a companion catalog to the open skills ecosystem around [vercel-labs/skills](https://github.com/vercel-labs/skills). It follows the same simple repository shape so skills in this repo can be listed and installed from GitHub-based tooling without adding custom packaging or registry layers.

## What this repo is for

- Ship production-usable skills that I can maintain in one place
- Keep each skill self-contained with instructions plus optional helper files
- Stay easy to browse, copy, and reuse from other repos or agents

## How it differs from `vercel-labs/skills`

- `vercel-labs/skills` is the broader tooling and ecosystem entrypoint
- This repo is a standalone catalog of my own published skills
- Compatibility matters more than customization here, so the structure stays intentionally minimal

## Install or browse skills

Use the Vercel-compatible CLI against this repository or any local clone:

```bash
# List skills available in a GitHub repo
npx skills add <owner>/<repo> --list

# Install one skill from a GitHub repo
npx skills add <owner>/<repo> --skill xcode-archive-release

# Install from a local checkout while developing
npx skills add . --list
```

See the upstream project for the latest CLI capabilities and agent support: [vercel-labs/skills](https://github.com/vercel-labs/skills).

## Repository layout

```text
skills/<slug>/SKILL.md
skills/<slug>/scripts/      # optional helper scripts
skills/<slug>/assets/       # optional static files
skills/<slug>/references/   # optional supporting docs
templates/skill/            # starter template for new skills
```

Every public skill lives in `skills/<slug>/`. The only required file is `SKILL.md`, which must include YAML frontmatter with:

- `name`
- `description`

## Catalog

| Skill | Purpose | Requirements | Status |
| --- | --- | --- | --- |
| `module-boundary-governance` | Define and audit module boundary manifests so larger changes keep clear ownership, public API, and dependency direction | Existing repo structure or architecture docs, boundary-sensitive change, and a planning workflow such as `plan-driven-change` | Stable |
| `plan-driven-change` | Approval-gated, plan-first workflow for larger multi-file or architectural changes | Project docs, known build/lint/test commands, user approval before implementation | Stable |
| `xcode-archive-release` | Bump app version/build, archive an Xcode project, and upload to App Store Connect | macOS, Xcode, Apple Developer account, signed project | Stable |

## Authoring rules

- Use kebab-case folder names under `skills/`
- Keep helper files inside the same skill folder
- Prefer relative paths like `scripts/foo.sh` inside `SKILL.md`
- Document when to use the skill, what the agent must confirm first, and what output the user should expect
- Start new skills from `templates/skill/`

Detailed contribution guidance lives in `CONTRIBUTING.md`.

## Validation

For local validation:

```bash
# Validate one skill without extra Python packages
python3 scripts/quick_validate_skill.py skills/<slug>

# Validate the full catalog
python3 scripts/validate_skills.py
```

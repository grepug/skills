# Contributing

This repo is a lightweight public catalog, so contributions should keep the structure simple and predictable.

## Skill contract

Each skill must live in its own folder:

```text
skills/<slug>/
├── SKILL.md
├── scripts/      # optional
├── assets/       # optional
└── references/   # optional
```

## Required conventions

- Folder names use kebab-case and should match the skill name
- `SKILL.md` must start with YAML frontmatter
- Frontmatter must include non-empty `name` and `description`
- Any referenced `scripts/...`, `assets/...`, or `references/...` path must exist inside that skill folder
- Helper scripts should be deterministic, documented, and safe for agents to run with explicit inputs

## Writing a good `SKILL.md`

Aim for a skill that an agent can use correctly without guessing:

- Start with a clear one-line purpose
- State when the skill should be used
- List prerequisites and constraints up front
- Tell the agent what inputs it must confirm before acting
- Describe expected outputs, artifact locations, and retry guidance
- Keep instructions actionable and concrete

## Review checklist

Before opening a PR or merging locally, check:

- The skill solves one clear job
- The frontmatter is present and accurate
- All relative file references resolve
- Shell helpers pass `bash -n`
- `python3 scripts/quick_validate_skill.py skills/<slug>` passes for the edited skill
- `python3 scripts/validate_skills.py` passes for the full catalog
- The root `README.md` catalog includes the new skill
- The template is still representative of the current standard if conventions changed

## Done criteria

A new or updated skill is ready when:

- It passes the repository validation workflow
- A fresh reader can understand when to use it
- The bundled helpers and assets are discoverable from `SKILL.md`
- The skill feels publishable, not experimental notes pasted into a folder

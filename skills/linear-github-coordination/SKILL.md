---
name: linear-github-coordination
description: Use when work involves both Linear and GitHub, including deciding whether to create or update Linear issues, GitHub issues, PR links, product-scope comments, engineering execution records, or state transitions without mirroring the same issue across both tools.
---

# Linear GitHub Coordination

Use this as the boundary policy between Linear product management and GitHub engineering execution. This skill decides which artifact should own the current truth, what should be linked, and which specialized workflow skill should handle the actual work.

This is a router and policy skill. Do not duplicate the full `linear-workflow` or `github-issue-workflow` process here.

## Prerequisites

This skill coordinates:

- `linear-workflow`
- `github-issue-workflow`

Before acting, check whether the needed underlying skills are available. If one is missing, do not reimplement it here. Ask the user to install the missing skill, or continue with the available skill and clearly state what coordination behavior is limited.

For this catalog, the usual install shape is:

```bash
npx skills add <owner>/<repo> --skill linear-workflow
npx skills add <owner>/<repo> --skill github-issue-workflow
```

Use repo-local install guidance when it differs from this catalog command.

## Use When

- A task mentions both Linear and GitHub.
- A Linear issue may need GitHub implementation tracking.
- A GitHub issue or PR may change product scope, acceptance, priority, or release sequencing.
- A PR merged, but it is unclear whether Linear should move state.
- The user asks whether to mirror, link, close, split, or update work across both systems.

## Core Model

- Linear owns product truth: user outcome, product scope, acceptance criteria, priority, sequencing, blockers, PM decisions, and PRD sync.
- GitHub owns engineering truth: code anchors, technical plan, implementation checklist, schemas, migrations, validation commands, PR review, and merge proof.
- Links connect the two systems. They do not make either system a copy of the other.

If Linear and GitHub disagree, Linear owns product intent and acceptance outcomes. GitHub owns implementation feasibility and validation evidence. Product-impacting engineering discoveries must be reported back to Linear before continuing.

## Decision Workflow

1. Identify the starting artifact: Linear issue, GitHub issue, PR, branch, code, docs, chat, or product request.
2. Read `references/artifact-ownership.md` to decide which system should own the current truth.
3. If status, closure, acceptance, release, or PRD sync is involved, read `references/state-transition-rules.md`.
4. If both systems exist or should be created, read `references/linking-and-closeout.md`.
5. Delegate the actual mutation:
   - PM/product issue, comment, metadata, or decision request: use `linear-workflow`.
   - Developer execution issue, canonical plan, validation, PR closeout, or merge audit: use `github-issue-workflow`.

## Default Rules

- Do not create one GitHub issue for every Linear issue by default.
- Do not create or update Linear only to mirror GitHub implementation details.
- Do not move Linear state just because a PR merged unless the user, PM workflow, or Linear issue explicitly authorizes that transition.
- Do not resolve product-scope disagreement only in GitHub, PR review, code comments, or chat.
- Do not put test logs, stack traces, code plans, migration checklists, or validation transcripts into Linear unless a short summary is needed for PM decision-making.
- Do not put product-decision debates into GitHub except as a short blocker that links back to Linear.

## Output

Successful use should leave one of these outcomes:

- Linear-only: PM contract or decision updated; no GitHub artifact was needed.
- GitHub-only: engineering work was tracked without creating fake product management overhead.
- Linked Linear and GitHub: each artifact owns its own layer, with bidirectional links and no body mirroring.
- Blocked: the exact PM decision, engineering evidence, or missing skill/install step is named.

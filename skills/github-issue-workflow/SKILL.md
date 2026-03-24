---
name: github-issue-workflow
description: Use when work should be tracked and executed through GitHub Issues instead of repo-local todo files. Helps agents adopt a repo's existing issue templates, labels, and project conventions when present, or fall back to a portable seed plus execution workflow when they are missing.
---

# GitHub Issue Workflow

Use GitHub Issues as the source of truth for scope, acceptance criteria, live progress, and completion state.

Prefer the repo's existing GitHub workflow when it exists. Use the bundled defaults in this skill only when the repo has no established issue templates, label conventions, or execution workflow.

When work depends on third-party, platform, or provider setup outside the repo, do not guess the setup contract and do not defer that research until implementation is already underway. Research the official documentation first, then capture the concrete dependency and the verification it unlocks in the issue body before treating the issue as ready for execution.

## Use when

- The user wants work tracked through GitHub Issues
- The repo already uses issues, labels, issue templates, or GitHub Projects for execution
- The task is meaningful enough that durable issue history is better than a local scratch checklist
- The repo should stop reviving retired repo-local planning workflows for tracked work

## Prerequisites

- GitHub access for the target repo
- Issue creation or editing permission when the task requires backfilling or updating issue state
- The ability to inspect repo-local guidance such as `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, and `.github/ISSUE_TEMPLATE/`

## Discovery order

Before creating or reshaping an issue workflow, inspect the repo in this order:

1. `.github/ISSUE_TEMPLATE/` for existing issue classes and required fields
2. repo docs for label policy, project usage, and planning rules
3. existing issue labels and naming conventions if the user or tooling exposes them
4. `AGENTS.md` or equivalent repo instructions for how tracked work should be executed

If the repo already has templates, labels, or project rules, follow them.

If the repo has no established workflow, use the portable defaults bundled with this skill:

- `assets/issue-templates/seed.yml`
- `assets/issue-templates/feature.yml`
- `assets/issue-templates/bug.yml`
- `assets/issue-templates/infra.yml`
- `assets/issue-templates/research.yml`
- `assets/issue-templates/config.yml`
- `references/label-conventions.md`
- `assets/canonical-plan-comment.md`

When external dependencies are involved, extend discovery with one more required step before implementation:

5. official provider or platform documentation for the required setup, configuration, limits, and verification prerequisites

## Default model when the repo has no workflow yet

Use two issue classes:

1. Seed issue
2. Execution issue

### Seed issue

Use a seed issue for early ideas that are worth capturing but are not ready to implement.

Rules:

- use the `seed` template
- apply `type:seed`
- do not apply a priority label
- do not treat the seed as execution authorization by itself
- do not add the canonical implementation-plan comment to the seed

### Execution issue

Use an execution issue once the work is concrete enough to build, investigate, or review against explicit acceptance criteria.

Rules:

- use the matching execution template: `feature`, `bug`, `infra`, or `research`
- apply the matching `type:*` label
- apply exactly one priority label from `priority:p0` to `priority:p3`
- in the bundled default templates, execution issues start with `priority:p2`; if the issue needs a different priority, replace that label immediately after creation
- keep one canonical implementation-plan comment for meaningful work

## Seed promotion

Do not implement directly from a seed issue.

Promote a seed into a new execution issue only when all of these are true:

- the problem is concrete enough to describe clearly
- the desired outcome is specific enough to verify
- the scope has at least some non-goals or boundary
- an owning area or module can be named

Promotion workflow:

1. Create a new execution issue with the matching template
2. Distill the seed into the new issue instead of copying the whole discussion
3. Add a backlink from the execution issue to the seed
4. Comment on the seed with `Promoted to #<n>`
5. Close the seed unless it intentionally remains a broader parent idea

## Canonical GitHub surfaces

For meaningful execution work, keep these aligned:

1. Issue body
2. One canonical implementation-plan comment
3. Optional GitHub Project item when the repo uses projects

Rules:

- the issue body is the stable request contract
- the plan comment is the rich design, checklist, verification trail, and tweaks log
- avoid multiple active plan comments
- if the repo uses a GitHub Project, keep status there instead of inventing another tracker

## Issue body requirements

Execution issues should capture:

- problem or request
- why it matters
- desired outcome
- constraints or non-goals
- acceptance criteria
- external setup dependencies when live verification depends on human-owned setup
- affected repo area
- owning layer or module
- validation commands or proof of completion
- optional links or references

When external setup dependencies exist, the issue must also capture:

- the provider or platform name
- the concrete setup tasks required
- the specific values, configuration surfaces, or credentials that must exist
- the official documentation links used to confirm those requirements
- the validation or acceptance criteria that each setup item unlocks

Rules:

- do not write `TBD`, `guess`, or similar placeholders when the information can be determined from official docs
- do not defer dependency research until implementation unless the user explicitly chooses that tradeoff
- if official docs are incomplete or contradictory, say that in the issue and record the remaining unknown precisely

Use a milestone or planning-bucket field only when the repo actually uses one.

## Canonical plan comment

Use `assets/canonical-plan-comment.md` as the default structure when the repo does not already have one.

Rules:

- keep it design-first and checklist-second
- map checklist items back to design sections
- include explicit verification items
- keep external setup as checklist items when live verification depends on it
- append tweaks instead of starting a second live plan
- do not start provider-dependent implementation from assumptions that have not been verified against official docs

## Labels

Use repo-native labels when present.

If the repo has none, adopt the portable defaults in `references/label-conventions.md`:

- `type:seed`
- `type:feature`
- `type:bug`
- `type:infra`
- `type:research`
- `priority:p0`
- `priority:p1`
- `priority:p2`
- `priority:p3`

Before relying on those defaults, create or sync the labels in the target repo using `references/label-bootstrap.md`.

## Output

Successful use of this skill should leave:

- the right issue class created or updated
- a clear stable issue body
- one canonical implementation-plan comment when the work is meaningful
- labels applied according to repo policy or the portable defaults
- no competing repo-local plan or todo file acting as the live tracker

## Bundled files

- `assets/issue-templates/*.yml` - portable issue form defaults for repos that have no issue templates yet
- `assets/canonical-plan-comment.md` - default implementation-plan comment structure
- `references/label-conventions.md` - portable label policy and meanings
- `references/label-bootstrap.md` - how to create or sync the required label set in a repo that does not already have it

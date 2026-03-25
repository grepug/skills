---
name: github-issue-workflow
description: Use when work should be tracked and executed through GitHub Issues instead of repo-local todo files. Helps agents adopt a repo's existing issue templates, labels, and project conventions when present, or fall back to a portable seed plus execution workflow when they are missing.
---

# GitHub Issue Workflow

Use GitHub Issues as the source of truth for scope, acceptance criteria, live progress, and completion state.

Prefer the repo's existing GitHub workflow when it exists. Use the bundled defaults in this skill only when the repo has no established issue templates, label conventions, or execution workflow.

When work depends on third-party, platform, or provider setup outside the repo, do not guess the setup contract and do not defer that research until implementation is already underway. Research the official documentation first, then capture the concrete dependency, how a human retrieves or configures it in the real world, and the verification it unlocks in the issue body before treating the issue as ready for execution.

Execution issues should read like completed implementation plans, not placeholders for future discovery. If the work changes dependencies, data models, schemas, architecture, module boundaries, rollout shape, or other reviewer-sensitive surfaces, research and record those details before marking the issue ready. If that detail is still unknown, keep the work as a seed or research issue instead of presenting it as ready-to-build execution work.

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
5. the currently affected code, manifests, schemas, migrations, and module boundaries so the issue describes the real starting point instead of guesses

If the repo already has templates, labels, or project rules, follow them.

If the repo has no established workflow, use the portable defaults bundled with this skill:

- `assets/issue-templates/seed.yml`
- `assets/issue-templates/feature.yml`
- `assets/issue-templates/bug.yml`
- `assets/issue-templates/infra.yml`
- `assets/issue-templates/research.yml`
- `assets/issue-templates/config.yml`
- `references/label-conventions.md`
- `references/label-bootstrap.md`
- `references/external-dependency-research.md`
- `references/implementation-readiness.md`
- `assets/canonical-plan-comment.md`

When external dependencies are involved, extend discovery with one more required step before implementation:

6. official provider or platform documentation for the required setup, configuration, limits, and verification prerequisites

When that sixth step applies, use `references/external-dependency-research.md` to shape what must be researched and how the issue should record it.
When the work changes dependencies, schemas, data models, architecture, or boundaries, also use `references/implementation-readiness.md` to shape the level of detail required before the issue is treated as ready.

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
- treat `type:research` as a bounded investigation issue, not as implementation authorization for follow-on code or config changes

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

- reviewer-attention summary near the top of the body
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

The reviewer-attention summary should stay concise and highlight only the change surfaces that deserve extra scrutiny from humans or agents, for example:

- added or removed dependencies
- database, schema, or migration changes
- architecture or module-boundary changes
- rollout, backfill, or compatibility risks
- config, secrets, or external setup

Use `None` only when there is genuinely no material review hotspot. Do not hide important review surfaces inside long prose elsewhere in the body.

When external setup dependencies exist, the issue must also capture:

- the provider or platform name
- the concrete setup tasks required
- the specific configuration surfaces plus credential identifiers or field names, owning systems, storage locations, and retrieval paths that must exist, never the secret values themselves
- how a human developer retrieves, creates, verifies, or configures each dependency in the real system
- the admin console, dashboard, API surface, or settings page where that work happens
- who needs access or permissions to do it
- the official documentation links used to confirm those requirements
- the validation or acceptance criteria that each setup item unlocks

Prefer a concrete structure such as:

- provider or platform
- what must exist
- how to get or configure it
- where to do that
- who needs access
- official docs
- unlocks

Rules:

- never paste the contents of secrets into the issue body; record the secret name, source, format, owner, storage location, and retrieval path instead
- do not write `TBD`, `guess`, or similar placeholders when the information can be determined from official docs
- do not defer dependency research until implementation unless the user explicitly chooses that tradeoff
- do not leave dependency additions, schema changes, architecture changes, migrations, or rollout shape as assumptions in a ready-for-implementation issue
- if official docs are incomplete or contradictory, say that in the issue and record the remaining unknown precisely

Use a milestone or planning-bucket field only when the repo actually uses one.

## Implementation readiness gate

Do not treat a `feature`, `bug`, or `infra` issue as implementation-ready until both of these are true:

1. the issue body gives a short, prominent summary of the reviewer-attention hotspots
2. the canonical plan comment elaborates the concrete implementation details for every hotspot

When relevant, the canonical plan comment should make the following explicit:

- current and planned dependency changes, including why each dependency is needed and why existing dependencies are insufficient
- current and planned data model or schema changes, including migrations, backfills, compatibility concerns, and rollback or recovery notes when applicable
- current and planned architecture or module-boundary changes, including the contracts being introduced or reshaped
- external setup dependencies and the human steps required to satisfy them
- rollout, operational, or verification constraints

If those details are not yet known, the work is still in research. Do not disguise incomplete discovery as an execution-ready issue.

`type:research` issues are different. They are execution-tracked investigations with explicit outputs and acceptance criteria, but they are not themselves implementation-ready contracts for code or configuration changes. Promote the result into a `feature`, `bug`, or `infra` issue when the work becomes concrete enough to build.

## Canonical plan comment

Use `assets/canonical-plan-comment.md` as the default structure when the repo does not already have one.

Rules:

- keep it design-first and checklist-second
- treat it as the completed implementation plan, not as a scratchpad for later discovery
- map checklist items back to design sections
- include explicit verification items
- keep external setup as checklist items when live verification depends on it
- append tweaks instead of starting a second live plan
- do not start provider-dependent implementation from assumptions that have not been verified against official docs
- do not omit dependency, schema, architecture, migration, or rollout detail when those surfaces are part of the change

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
- `references/external-dependency-research.md` - how to research and record real-world external setup requirements for issue bodies
- `references/implementation-readiness.md` - how to research and record dependency, schema, architecture, and rollout detail before an execution issue is treated as ready

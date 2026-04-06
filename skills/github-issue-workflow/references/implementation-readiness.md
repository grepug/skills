# Implementation Readiness

Use this when an execution issue is supposed to be ready for implementation rather than just worth discussing.

The goal is to make the issue and its canonical plan comment concrete enough that a human reviewer or an execution agent can understand the real change surface without discovering core facts mid-implementation.

## Readiness rule

Do not call an execution issue implementation-ready if the work would materially change any of these surfaces and the issue still treats them as guesses:

- package or service dependencies
- data models, schemas, migrations, or backfills
- architecture, layering, or module boundaries
- rollout, compatibility, recovery, or operational behavior
- configuration, secrets, or human-owned setup outside the repo

If those details are still unknown, keep the work as a seed or a bounded research issue instead of an implementation-bearing execution issue.

## What to research before writing the issue

For each material change surface, gather the current state and the planned change.

### Dependency changes

For every dependency being added, removed, upgraded materially, or newly relied on:

1. `What changes`
   - Package, service, SDK, tool, or provider name
2. `Why it is needed`
   - The capability it unlocks and why current repo choices are insufficient
3. `Where it integrates`
   - Touched manifests, lockfiles, modules, commands, build steps, or runtime paths
4. `Operational impact`
   - Config, credentials, bundle size, platform support, licensing, or maintenance implications
5. `Review hotspot`
   - What a reviewer should pay attention to

### Data model or schema changes

For every database, persistence, schema, model, or API contract change:

1. `Current state`
   - The model, table, field, enum, payload, or contract that exists today
2. `Planned change`
   - Exactly what fields, relations, constraints, indexes, or payload shapes will change
3. `Migration path`
   - Migration, backfill, data repair, or transitional compatibility steps
4. `Risk or recovery`
   - Breaking behavior, rollback limits, reversibility, or monitoring concerns
5. `Review hotspot`
   - What a reviewer should pay attention to

### Architecture or boundary changes

For every layering, ownership, or contract change:

1. `Current boundary`
   - What module, layer, or component owns the responsibility today
2. `Planned boundary`
   - What will own it after the change
3. `Contracts`
   - Interfaces, commands, events, schemas, or file boundaries being introduced or changed
4. `Decision basis`
   - The concrete repo constraint, requirement, or compatibility fact that makes this chosen design necessary
5. `Review hotspot`
   - What a reviewer should pay attention to

### Rollout and verification

For every change with operational or staged risk:

1. `Rollout shape`
   - Flag day, staged, guarded, migration-first, or no-op-compatible rollout
2. `Compatibility constraints`
   - Version skew, ordering constraints, or environment prerequisites
3. `Verification`
   - Commands, tests, manual checks, or evidence that prove the change is safe

## Where to put the detail

Use two layers:

1. `Issue body`
   - Keep it short and readable
   - Add a required `Reviewer attention` summary near the top
   - Summarize only the hotspots, not all backing detail
   - Record the selected scope only; do not add `Options considered`, alternatives, pros / cons, or recommendation sections
2. `Canonical plan comment`
   - Record the researched implementation detail for each hotspot
   - Treat this as the authoritative implementation plan
   - Record the chosen design and supporting facts, not a comparison between options

## Review rule

Before treating the issue as ready, ask:

- Could a reviewer see the risky surfaces within a few seconds from the issue body?
- Could an implementation agent execute without first rediscovering dependency, schema, or architecture facts?
- Does the plan comment describe the current state as well as the target state?
- Does it explain why the chosen dependency or design is being used?
- Does it distinguish between reversible and irreversible changes?
- Does it make rollout and verification explicit where relevant?

## Completion rule

Implementation is not complete when code lands on a branch. It is complete when the execution surfaces still agree after implementation.

Before opening or updating the PR, verify all of the following:

- the issue body still matches the shipped scope
- the canonical plan comment checklist has been reconciled against the shipped code
- no implementation checklist item remains unchecked in the issue body or the canonical plan comment
- the PR body closes the linked issue and summarizes closeout instead of inventing a different checklist

Before merging the PR on user request, verify all of the following:

- no PR checklist item remains unchecked
- every additional issue the PR closes has reconciled issue and canonical-plan checklist state
- any merge blocker is reported and worked through instead of being bypassed

If those conditions are not true yet, the work is still in execution even if the code is already written.

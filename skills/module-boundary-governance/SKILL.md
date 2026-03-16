---
name: module-boundary-governance
description: Define, audit, and migrate module boundary manifests for codebases that need explicit ownership and dependency rules. Use when Codex is creating a new module, adding a new nested layer, moving code across layers, changing a module's public entrypoints, checking an existing repo's boundary health, or replacing weaker boundary docs and conventions with a canonical manifest-based system.
---

# Module Boundary Governance

Use this skill to keep module boundaries explicit before code changes make them fuzzy. Treat the boundary manifest as a small control surface: it should describe module ownership, public surface, internal layers, dependency direction, and review questions without becoming a second architecture codebase.

This skill works best alongside a planning workflow such as `plan-driven-change`. Use it to decide the owning module, choose whether a new nested layer is warranted, update or create the manifest, and run a boundary audit after implementation.

## Default Recommendation

Prefer one manifest per major module root with nested layers inside the same file.

Use a separate manifest file only when a submodule is independently owned or reused and has meaningfully different boundary rules.

Keep automation strict for dependency direction and public entrypoints. Keep semantic placement review human-readable via purpose, allowed contents, forbidden contents, and audit questions.

Adopt manifests incrementally. Prefer small structural corrections over broad redesign.

## Trigger Checklist

Load this skill when any of these are true:

- a new module root is being created
- a new nested layer is being introduced inside an existing module
- code is moving across declared layers
- a module's public entrypoints are changing
- a change touches multiple layers inside one module
- the user wants a repo-wide boundary audit
- the repo already has weak boundary management and needs migration to manifests
- the user is asking how to keep UI, feature, infrastructure, data, or utility code from drifting into each other

Skip this skill for one-line changes, isolated bug fixes that clearly stay within one layer, or edits that do not affect module ownership or public surface.

## Workflow

### 1. Find the owning module

Inspect the repo's existing package, workspace, and feature seams before inventing new ones.

Answer these questions in order:

- Which major module root owns this change?
- Does an existing manifest already govern that root?
- Does the change fit an existing declared layer?
- If not, is the problem a missing nested layer or a wrongly shaped module?

Prefer the existing major root over creating a new manifest. Only split out a new manifest when the submodule has distinct ownership and long-term independence.

### 2. Decide the right granularity

Add a nested layer only if at least one of these is true:

- it has a different dependency policy
- it has a different ownership or responsibility
- it exposes a different public API surface
- it needs different audit questions than its parent layer

Do not create a layer just because a folder exists.

If multiple new exceptions would be needed to make the current structure work, prefer redesigning the layer or module boundary instead of piling on exceptions.

### 3. Create or update the manifest

Place the manifest at the major module root with a predictable name such as `boundary.manifest.yml`.

Use this schema shape:

```yaml
version: 1

module:
  name: app
  root: clients/apple/Packages/App
  owners:
    - apple
  purpose: >
    App-owned product shell, canonical models, and feature workflow logic.
  public:
    - Sources/App/**
    - Sources/Shared/Models/**
  forbidden:
    - reusable cache infrastructure
    - generic UI-only component library code

layers:
  - id: shared-models
    paths:
      - Sources/Shared/Models/**
    purpose: Canonical app-owned model shapes.
    may_depend_on: []
    may_be_depended_on_by:
      - feature-stores
      - app-shell
    contains:
      - canonical entities
      - stable read shapes
    must_not_contain:
      - transport orchestration
      - feature-specific workflow policy

  - id: feature-stores
    paths:
      - Sources/Shared/Features/*/Stores/**
    purpose: Feature-owned business workflow and optimistic mutation logic.
    may_depend_on:
      - shared-models
      - graphql-models
    may_be_depended_on_by:
      - feature-ui
      - app-shell
    contains:
      - stores
      - workflow coordinators
    must_not_contain:
      - reusable cache primitives
      - general-purpose visual components

review:
  checklist:
    - Does every changed file map to a declared layer?
    - Did any internal file become a de facto public API?
    - Did business logic leak into an adapter or generic layer?
  exceptions:
    policy: explicit
    require:
      - reason
      - owner
      - expiry_or_followup
```

Keep the schema small. The most important machine-checkable fields are:

- `module.root`
- `module.public`
- `layers[].paths`
- `layers[].may_depend_on`
- optional `layers[].may_be_depended_on_by`

Keep the semantics human-readable:

- `purpose`
- `contains`
- `must_not_contain`
- `review.checklist`

### 4. Audit an existing repo before adopting manifests

When the repo does not yet use manifests consistently, perform an adoption audit before introducing new files.

Inspect all existing boundary signals:

- package and workspace structure
- feature folder layout
- architecture docs, rules docs, ADRs, or module readmes
- lint or import-boundary rules
- actual dependency direction in code

Produce these outputs:

- proposed manifest roots
- proposed nested layers inside each root
- gaps between the repo's claimed boundaries and actual code structure
- duplicated or contradictory boundary rules
- a phased migration plan

Use this audit structure:

```md
## Existing Boundary Audit

Current boundary artifacts:
- `AGENTS.md`
- `docs/rules/feature-placement.md`
- package-level folder conventions

Observed module seams:
- `servers/main`
- `shared/graphql-schema`
- `clients/apple/Packages/App`

Weaknesses:
- ownership rules live in prose only
- public entrypoints are not explicit
- some rules are duplicated across docs

Proposed canonical manifests:
- `servers/main/boundary.manifest.yml`
- `clients/apple/Packages/App/boundary.manifest.yml`

Migration risks:
- contributors may keep editing the old rules docs unless they are marked as superseded
```

Focus on the biggest seams first. Do not try to model every subfolder in the first pass.

### 5. Assess boundary readiness before proposing manifests

Classify the repo before recommending manifest adoption:

- `ready`
  - the repo already has recognizable module seams
  - boundaries are mostly stable but weakly enforced
  - proceed with manifests for the relevant major roots
- `partially-ready`
  - some module seams are stable, but others are still entangled
  - adopt manifests only for the stable roots and defer the rest
- `not-ready`
  - responsibilities are deeply mixed, imports are highly tangled, or the user is not willing to make structural changes now
  - do not propose broad manifest adoption yet

Use this readiness structure:

```md
## Boundary Readiness

Status: `partially-ready`

Signals:
- backend feature seams are mostly stable
- shared utilities and app-specific workflow code still mix in several folders
- current docs describe ownership, but code does not follow it consistently

Recommendation:
- adopt manifests for `servers/main` and `clients/apple/Packages/UIComponents`
- defer `clients/apple/Packages/App` broad layering until one small cleanup lands

Immediate next step:
- extract one mixed feature-policy helper out of the shared utility layer
```

If the repo is `not-ready`, say so directly. Do not pretend the manifest system will fix architectural chaos by itself.

### 6. Migrate from weak boundary management

Treat existing docs and conventions as source material, not as untouchable truth.

For each existing boundary artifact, classify it as one of:

- `keep as supporting guidance`
- `fold into manifest`
- `supersede and remove`

Use this migration table shape:

```md
## Boundary Migration

| Existing artifact | Decision | Replacement | Reason |
| --- | --- | --- | --- |
| `docs/rules/feature-placement.md` | keep as supporting guidance | `servers/main/boundary.manifest.yml`, `clients/apple/Packages/App/boundary.manifest.yml` | Good teaching document, but ownership rules should move to manifests |
| `docs/architecture/old-layers.md` | supersede and remove | `servers/main/boundary.manifest.yml` | Duplicates layer rules and will drift |
```

Migration rules:

- Keep narrative docs that teach contributors how to think.
- Move ownership, public API, and dependency-direction rules into manifests.
- Mark duplicated docs as superseded before removing them.
- Do not leave two canonical sources for the same boundary rule.
- If removal is risky, shrink the old doc to a pointer that references the manifest.

Make the migration actionable. Do not stop at "this area should be cleaner." Spell out the concrete reorganization steps.

For any migration that changes structure, produce a file move map in this form:

```md
## Boundary Migration Execution

Canonical target:
- `servers/main/boundary.manifest.yml`

File moves:
- move `servers/main/src/graphql/files/file-policy.ts` -> `servers/main/src/features/files/file-policy.ts`
- move `clients/apple/Packages/Utils/Sources/Utils/AgentSessionStore.swift` -> `clients/apple/Packages/App/Sources/Shared/Features/Agent/Stores/AgentSessionStore.swift`
- keep `clients/apple/Packages/UIComponents/Sources/UIComponents/ChatBubble.swift` in place

Folder reorganization:
- create `servers/main/src/features/files/storage/` for storage-driver implementations
- create `servers/main/src/features/files/persistence/` for repository implementations
- collapse `docs/rules/old-boundaries.md` into a short pointer to `servers/main/boundary.manifest.yml`

Follow-up cleanup:
- update imports after moving `file-policy.ts`
- update tests to point at the new package path
- remove the old empty folder once references are gone
```

Use imperative wording such as `move`, `keep`, `create`, `rename`, `collapse`, and `remove`.

When deciding whether to move a file, answer:

- what layer owns this file now
- what layer should own it after the migration
- whether the move improves the boundary immediately
- whether the move is safe in the current task scope

If the correct destination is clear, name the exact target path. Prefer `move A -> B` over vague advice like "put this in the feature layer."

If the correct destination is not safe to change now, say so explicitly:

- `defer moving \`A\` to \`B\` until <reason>`

Use deferral sparingly. A deferred move must include a reason and the smallest follow-up step that would unblock it.

For messy repos, prefer a small migration slice with high value:

- move a few obviously misplaced files into the correct layer
- create only the minimum new folders required
- update imports and tests in the same change
- leave broader redesign for later

Do not propose broad folder churn without naming the concrete files or folders that move.

### 7. Keep restructuring small

Default to the smallest structural change that makes the next boundary decision clearer.

Prefer:

- one module root at a time
- one stable seam at a time
- one small boundary cleanup before manifest adoption if the code is still mixed
- narrow pilot adoption for a high-value module instead of repo-wide rollout

Avoid:

- repo-wide redesign in the name of boundary purity
- speculative layer creation
- moving large amounts of code without a current product reason
- introducing manifests for modules whose boundaries are not stable enough to govern

When the repo is messy, this skill should usually propose a small restructuring slice, not a significant redesign.

### 8. Add boundary context to the plan

If a planning document exists, require a dedicated `## Boundary` section.

Use this shape:

```md
## Boundary

Owning manifest: `servers/main/boundary.manifest.yml`
Affected layers:
- `graphql`
- `features`
- `files-storage`

Manifest changes:
- [ ] none
- [x] add nested `files-storage` layer
- [ ] public surface changed

Boundary risk:
- resolver logic may absorb storage policy unless the service seam stays explicit
```

Require the plan to answer:

- which manifest owns the change
- which layers are affected
- whether the manifest changes
- whether public entrypoints change
- what the main boundary risk is

If the task is an adoption or migration task, also include:

- readiness status
- which existing artifacts will remain as guidance
- which artifacts will be superseded or removed
- the exact file moves, folder creates, renames, or removals
- whether the rollout is immediate or phased

### 9. Audit after implementation

Run a boundary audit after the implementation checklist is done.

Use this audit shape:

```md
## Boundary Audit

Owning manifest: `servers/main/boundary.manifest.yml`

Touched layers:
- `graphql`
- `features`

Results:
- [x] Every changed file maps to a declared layer
- [x] No new undeclared public entrypoints
- [x] Dependency direction remains valid
- [ ] Manifest unchanged

Risks:
- resolver mappers are still adjacent to service logic; watch for drift in follow-up changes
```

Check all of the following:

- every changed file belongs to a declared layer
- dependency direction still matches the manifest
- no internal helper became a public API accidentally
- no changed file violates a `must_not_contain` rule
- the manifest still matches reality after the change
- any superseded boundary doc now points to the manifest or has been removed from the canonical path

Any audit gap becomes a new work item before the task is considered done.

## Guardrails

- Prefer one manifest per major root module, not per folder.
- Prefer nested layers inside the manifest over additional manifest files.
- Keep new layers rare and justified.
- Keep the manifest strict on dependency direction and public surface.
- Keep the manifest concise; if a layer needs a long essay, the boundary is probably wrong.
- If the repo is not ready, say so and propose a small cleanup or a narrow pilot instead of broad adoption.
- Prefer shrinking old boundary docs into teaching guides rather than leaving duplicated rules in place.
- Allow exceptions only when they are explicit, named, justified, and time-bounded.

## Integration With Plan-Driven Change

When this skill is paired with `plan-driven-change`, require it before finalizing the plan if the change:

- creates a module or major sublayer
- crosses module or layer boundaries
- changes public entrypoints
- touches multiple layers where responsibilities could blur

The expected handoff back to `plan-driven-change` is:

- the owning manifest path
- affected layers
- required manifest changes, if any
- any existing boundary artifacts to keep, fold in, or supersede
- plan-ready `## Boundary` content
- post-implementation audit questions

---
name: plan-driven-change
description: "Approval-gated, plan-first workflow for larger code changes. Use when the user asks to build a new capability or make a non-trivial change that touches multiple files, crosses module boundaries, or involves architectural decisions. Do NOT use for bug fixes, one-line tweaks, dependency bumps, or small config changes. The workflow is: clarify intent -> user approves -> write a rich plan with interface stubs + checklist -> user approves -> implement with progress logging -> run a gap audit -> record tweaks."
---

# Plan-Driven Change

Plan-first development cycle for larger changes. Combines brainstorming-style intent review with a tracked plan document and explicit implementation traceability.

## When to Use

- New capabilities, features, or modules
- Changes touching 3+ files or involving architectural decisions
- Anything where scope is unclear or risks exist

Skip for: bug fixes, one-liners, dependency bumps, config tweaks, and small maintenance edits. Act directly for those.

## Phase 0: Discover Project Conventions

Before starting, quickly orient to the project:

- Where does the project store plans or design docs? Check for `docs/`, `docs/plans/`, `docs/rfcs/`, `docs/decisions/`, `.github/`, `planning/`, or similar. If none found, default to `docs/plans/`.
- What are the build, lint, and test commands? Check `package.json`, `Makefile`, `README`, `justfile`, `pyproject.toml`, or CI config.
- What language(s) and conventions does the project use for interfaces and types?

Use these findings throughout the workflow — don't hardcode assumptions.

## Phase 1: Intent Brainstorm (no code, no files yet)

Load the `brainstorming` skill. Then conduct a focused scoping conversation:

1. Ask **one question at a time** to clarify:
   - What exactly is being built and why?
   - What is explicitly out of scope?
   - What is the biggest risk or unknown?
   - Are there simpler alternatives worth considering?

2. Challenge assumptions: if a simpler approach exists, surface it before planning the complex one.

3. Once aligned, produce the **intent block** in chat (not a file yet):

```
What: <one sentence>
Why: <one sentence>
Out of scope: <one sentence>
Key risk: <one sentence>
```

4. **Wait for user approval** of the intent block before moving to Phase 2. Do not proceed without an explicit "go" or equivalent.

The approved intent block becomes the seed for the **Context** section of the Phase 2 plan document.

## Phase 2: Plan Document

Create a plan file at the project's established location (discovered in Phase 0), using a consistent naming scheme. Default if no convention exists:

```
docs/plans/YYYY-MM-DD-NN-<kebab-topic>.md
```

`NN` is a zero-padded two-digit sequence number for that calendar day, starting at `01`. List existing files for that date and increment from the highest `NN` found (or use `01` if none exist).

The plan is a **design document first, checklist second.** It should be rich enough that any engineer can implement without asking follow-up questions.

### Required sections (always present)

```markdown
# <Topic>

**Date:** YYYY-MM-DD
**Status:** Draft | Ready for implementation
**Target path:** `path/to/affected/module/`

<!-- Optional: Supersedes: [prior-plan.md](link), Based on: [review.md](link) -->

---

## Context

<2–4 sentences: what problem this solves, why now, and — if this replaces a prior design —
what the old approach got wrong. Be specific. Name the actual file or abstraction being fixed.>

---

## Design

<!-- One ## sub-section per major component. Each section contains:
     - the interface / signature stub (always — even a brief stub in the project's language)
     - rationale: why this shape / approach
     - key design decisions with > **Why X not Y:** callouts for non-obvious choices
     - execution flow in numbered pseudocode if the component has a complex happy-path -->

### <Component Name> (`path/to/file`)

<interface or signature stub — use the project's language conventions, not full implementation>

<rationale paragraph>

> **Why X not Y:** <one-sentence justification for a non-obvious choice>

<!-- Execution flow — include only when the component orchestrates multiple steps -->

**Flow:**
```

method(input):

1. <step>
2. <step>
   ...

```

---

## Folder Structure  <!-- include only when new directories or files are being created -->

```

path/to/module/
├── file-a — <one-line purpose>
└── file-b — <one-line purpose>

```

<!-- Include a "Why This Layout" comparison table if the structure replaces an existing one -->

---

## Checklist

<!-- Each item names the file(s) it touches and references the design section above.
     Steps are ordered by dependency. Verification steps are explicit, not assumed. -->

- [ ] <step> — `path/to/file` (see §<ComponentName>)
- [ ] <step> — `path/to/other`
- [ ] Verify: build + lint + tests pass

## Tweaks

<!-- appended after implementation -->
```

### Rules for each design section

- **Always include an interface/signature stub** for every new component — even a 3-line stub is enough; use the project's own language and conventions
- Use `> **Why X not Y:**` callouts for any decision another engineer might question
- Include execution flow pseudocode when a method coordinates 4+ distinct steps
- Keep rationale paragraphs to 3–5 sentences; link to external docs rather than quoting them

### Rules for the checklist

- Each item names the file(s) it touches and cross-references the relevant design section (`see §ComponentName`)
- Verification steps (build, lint, tests) are explicit items — use the actual commands for the project
- Steps are ordered by dependency — no step assumes earlier unfinished work

### Review pass before sharing

Do a **brainstorm-style review pass** on the full document before showing it to the user:

- Is every component in the checklist also covered in the Design section?
- Is there a signature stub for every new file?
- Flag any step that is underspecified or too coarse — propose splits
- Ask: "is there a simpler sequence?"
- Ask: "what's the test strategy for the riskiest step?"

**Wait for user approval** of the plan. The user may reorder, add, or remove items. Do not begin implementation until they say "go" or equivalent.

## Phase 3: Implementation

Work through the checklist top-to-bottom:

- Check off items as completed using the manage_todo_list tool or by updating the plan file
- Run verification steps (build, lint, tests) at the milestones specified in the checklist
- If a step reveals unexpected complexity, stop and surface it before continuing — do not silently expand scope

## Communication and Logging

While implementing, leave a compact trail that makes the work easy to review:

- Before editing, post a short summary of what part of the plan you are starting
- During implementation, send brief phase updates when you complete a meaningful checklist item or discover a risk
- Record verification commands and outcomes explicitly in chat or in the plan file's checklist; do not collapse them into "verified"
- At handoff, summarize:
  - what changed
  - what was intentionally deferred
  - what risks or follow-ups remain

If the project already has a decision log, changelog, ADR folder, or implementation-notes convention, append to that instead of inventing a new logging location.

## Commenting Standard

Use comments sparingly and for future readers, not for narration:

- Add comments only where the code contains a non-obvious constraint, invariant, workaround, or trade-off
- Do not add comments that restate what the code already says clearly
- Put broader rationale in the plan document; put local rationale in code only when a future editor would miss it at the point of change
- Prefer short boundary comments near subtle logic, protocol edges, migrations, or compatibility shims
- If a new component needs explanation longer than 2-3 lines, the design is probably underspecified or the component should be split

## Phase 4: Gap Audit

After all checklist items are checked:

1. Re-read the **Context** section of the plan — does the implementation match what was promised?
2. Scan for missed test coverage, unhandled edge cases, or broken contracts
3. Verify that build, lint, and all tests pass cleanly
4. Confirm the final implementation notes cover verification results, deferred items, and remaining risks
5. Any gaps found become new checklist items and are fixed before done

## Phase 5: Tweaks

Post-implementation polish or orphan changes that emerge from conversation:

- Append to the **same plan file** under `## Tweaks` as one-liner checked items:
  ```
  - [x] Fixed edge case in parser — added null guard
  ```
- If no parent plan file exists for the tweak, create a new sequenced plan file for that day with just a `## Tweaks` section.

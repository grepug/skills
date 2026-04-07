# <Topic>

**Status:** Draft | Ready for implementation
**Target paths:** `path/to/area`
**Use this comment for:** live checklist updates, plan edits, boundary notes, validation results, and post-implementation tweaks
**Do not use this comment for:** option comparisons, alternatives sections, pros / cons lists, tradeoff matrices, or recommendation sections
**Any rationale in this comment must be:** concrete, fact-based, and tied to repo constraints, requirements, or compatibility needs

## Context

<2-4 focused sentences>

## Reviewer Attention

- <material review hotspot and why it needs attention>

## Current Evidence / Anchors

- <specific file, function, command, issue, PR, log line, or short excerpt that shows the current state>

## Change Surface

### Dependency changes

- Current state: <what the repo uses today or `None`>
- Planned change: <added, removed, or upgraded dependency, or `None`>
- Where it integrates: <manifests, lockfiles, modules, commands, build steps, or `None`>
- Operational impact: <config, credentials, platform, licensing, maintenance, or `None`>
- Decision basis: <the concrete repo constraint or requirement that makes this dependency or approach necessary>
- Review focus: <what reviewers should scrutinize>

### Data model / schema changes

- Current state: <current model, schema, contract, or `None`>
- Planned change: <what changes, or `None`>
- Migration / compatibility: <migration, backfill, rollout, or `None`>
- Risk / recovery: <breakage risk, rollback limits, monitoring, or `None`>
- Review focus: <what reviewers should scrutinize>

### Architecture / boundary changes

- Current state: <current ownership or boundary, or `None`>
- Planned change: <new ownership, contract, or boundary, or `None`>
- Contracts: <interfaces, commands, events, schemas, or `None`>
- Decision basis: <the concrete repo constraint or requirement that makes this design necessary>
- Review focus: <what reviewers should scrutinize>

## Design

### <Component or step>

- Files: `path/to/file`
- Interface or contract: `<signature or artifact shape>`
- Decision basis: <the concrete repo constraint or requirement that makes this component shape necessary>

## Boundary

<Include only when boundary-sensitive>

## Folder Structure

<Include only when creating or reshaping directories materially>

## External Setup Dependencies

- [ ] <provider or platform setup task> - unlocks `<verification or acceptance check>`

## Rollout / Operational Notes

- <compatibility, sequencing, backfill, recovery, or `None`>

## Closeout Contract

- Re-read the issue body and acceptance criteria before opening or updating a PR.
- Reconcile this checklist against the shipped code; do not leave implementation items unchecked because the work moved to PR review.
- Open or update a PR that closes the linked issue and carries a short closeout checklist derived from this issue.
- Treat unchecked implementation items in the issue body or this comment as blockers for PR readiness.

## Checklist

### Phase 1 - <name>

- [ ] <step> - `path/to/file` (see Design)

### Verification

- [ ] Verify: `<command or proof>`

## Tweaks

- [ ] None yet

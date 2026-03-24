# Portable Label Conventions

Use repo-native labels when the target repository already has them.

If the repo has no issue-tracking label policy, these labels are the portable default:

## Type labels

- `type:seed` - early idea or intake item; not committed execution work yet
- `type:feature` - product or platform capability work
- `type:bug` - defect investigation and correction
- `type:infra` - infrastructure, tooling, workflow, CI, or repo operations work
- `type:research` - investigation, spike, or decision-support work

## Priority labels

Execution issues should have exactly one of:

- `priority:p0` - emergency, security-critical, production-incident, or release-blocking work only
- `priority:p1` - highest normal execution priority
- `priority:p2` - standard planned work
- `priority:p3` - intentionally deferred or low-urgency work

Seed issues do not get priority labels.

## Operational rules

- Create or sync the portable label set before using the bundled default templates. See `references/label-bootstrap.md`.
- Every execution issue gets exactly one `type:*` label and exactly one `priority:*` label.
- Seed issues get `type:seed` and no priority label.
- The bundled execution templates default new issues to `priority:p2`; replace that label immediately when the issue should be `priority:p0`, `priority:p1`, or `priority:p3`.
- When reprioritizing, replace the old priority label instead of stacking multiple priorities.
- If the repo uses GitHub Projects, keep project status there rather than inventing another parallel tracker.

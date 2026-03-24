# GitHub Labels

This repo now ships the label conventions used by the bundled `github-issue-workflow` skill.

GitHub labels are not created by files in the repository by default, so create or sync these labels in the GitHub UI or with your preferred label automation.

The bundled execution templates default new execution issues to `priority:p2`. Replace that label immediately when the selected initial priority should be `priority:p0`, `priority:p1`, or `priority:p3`.

## Type labels

- `type:seed` - early idea or intake item; not committed execution work yet
- `type:feature` - product, workflow, or catalog capability work
- `type:bug` - defect investigation and correction
- `type:infra` - infrastructure, tooling, workflow, CI, and repository operations work
- `type:research` - investigation, spike, or decision-support work

## Priority labels

Execution issues should have exactly one:

- `priority:p0` - emergency, security-critical, production-incident, or release-blocking work only
- `priority:p1` - highest normal execution priority
- `priority:p2` - standard planned work
- `priority:p3` - intentionally deferred or low-urgency work

Seed issues do not get a priority label.

## Working rules

- Every execution issue should have one `type:*` label and one `priority:*` label.
- Seed issues should use `type:seed` only.
- When reprioritizing, replace the old priority label instead of stacking multiple priorities.
- When third-party or platform setup is required, research the official docs first and capture the concrete dependency plus doc links in the issue instead of guessing or punting the research into implementation.

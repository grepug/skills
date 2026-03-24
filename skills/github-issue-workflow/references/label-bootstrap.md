# Label Bootstrap

If the target repo does not already have a compatible label set, create or sync the portable defaults before using the bundled issue templates.

Required labels:

- `type:seed`
- `type:feature`
- `type:bug`
- `type:infra`
- `type:research`
- `priority:p0`
- `priority:p1`
- `priority:p2`
- `priority:p3`

## Minimum rule

The bundled execution issue templates assume those labels exist. If they do not, create them first or the workflow will not apply labels correctly.

## Manual bootstrap

Create the labels in the GitHub UI or with your usual repo automation.

Suggested descriptions:

- `type:seed` - Early idea or intake item
- `type:feature` - Product or platform capability work
- `type:bug` - Defect investigation and correction
- `type:infra` - Tooling, workflow, CI, or repo operations work
- `type:research` - Investigation or decision-support work
- `priority:p0` - Emergency or release-blocking work
- `priority:p1` - Highest normal execution priority
- `priority:p2` - Standard planned work
- `priority:p3` - Deferred or low-urgency work

## GitHub CLI bootstrap example

If `gh` is available and authenticated for the target repo, these commands create or update the label set:

```bash
gh label create 'type:seed' --color BFD4F2 --description 'Early idea or intake item' --force
gh label create 'type:feature' --color 0E8A16 --description 'Product or platform capability work' --force
gh label create 'type:bug' --color D73A4A --description 'Defect investigation and correction' --force
gh label create 'type:infra' --color 5319E7 --description 'Tooling, workflow, CI, or repo operations work' --force
gh label create 'type:research' --color 1D76DB --description 'Investigation or decision-support work' --force
gh label create 'priority:p0' --color B60205 --description 'Emergency or release-blocking work' --force
gh label create 'priority:p1' --color D93F0B --description 'Highest normal execution priority' --force
gh label create 'priority:p2' --color FBCA04 --description 'Standard planned work' --force
gh label create 'priority:p3' --color C2E0C6 --description 'Deferred or low-urgency work' --force
```

These commands intentionally standardize colors and descriptions as well as names. If the repo already has established label presentation you want to preserve, either omit `--force` for labels that already exist or use `gh label edit` selectively so only the semantics stay aligned.

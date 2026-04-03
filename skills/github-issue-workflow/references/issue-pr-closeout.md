# Issue To PR Closeout

Use this reference when implementation is finishing and the work needs to move from issue execution into PR review without dropping checklist state.

## Goal

Keep the issue body, canonical plan comment, and PR body aligned so the issue remains the source of truth and the PR becomes the auditable closeout record.

## Closeout rules

1. Re-read the issue body after implementation, not before it.
2. Re-read the canonical plan comment and reconcile every implementation checkbox against shipped code.
3. Treat unresolved implementation checkboxes as blockers for PR readiness.
4. Generate the PR body from the linked issue instead of writing it from memory.
5. Open the PR automatically once the issue is fully implemented and the closeout audit passes.

## Local workflow

Use the bundled helper locally. It does not depend on CI.

Audit the issue state:

```bash
python3 skills/github-issue-workflow/scripts/issue_pr_closeout.py audit --issue 123
```

Render the PR body without creating the PR:

```bash
python3 skills/github-issue-workflow/scripts/issue_pr_closeout.py pr-body \
  --issue 123 \
  --summary "Implement issue-to-PR closeout gate in the skill" \
  --summary "Add a local helper script for audit and PR creation"
```

Create or update the PR after the audit passes:

```bash
python3 skills/github-issue-workflow/scripts/issue_pr_closeout.py open-pr \
  --issue 123 \
  --base main \
  --summary "Implement issue-to-PR closeout gate in the skill" \
  --summary "Add a local helper script for audit and PR creation" \
  --validation "python3 scripts/quick_validate_skill.py skills/github-issue-workflow"
```

## Expected behavior

- If the canonical plan comment is missing, the helper exits non-zero.
- If unchecked implementation checklist items remain in the issue body or plan comment, the helper exits non-zero.
- Open items under `External Setup Dependencies` remain visible in the audit output but do not block PR creation by themselves.
- If the current branch already has a PR, the helper updates that PR instead of creating a duplicate.
- If the current branch is not pushed yet, the helper exits non-zero and tells you to push the branch first.
- The helper carries the issue milestone into the PR when one exists.

## Notes

- The helper is strict on implementation checklists because the failure mode here is agents moving on too early.
- The helper is local-first. CI can layer on top later, but this workflow should stand on its own without CI.

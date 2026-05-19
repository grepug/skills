# Issue To PR Closeout

Use this reference when implementation is finishing and the work needs to move from issue execution into PR review without dropping checklist state.

## Goal

Keep the issue body, canonical plan comment, and PR body aligned so the issue remains the source of truth and the PR becomes the auditable closeout record.

When the user asks to merge, re-audit the live PR and all issues that the PR will close so merge cannot happen on stale checklist state.

## Closeout rules

1. Keep exactly one canonical execution issue for the work. If a duplicate or superseded issue exists, close it with a backlink and keep the plan and PR closeout on the surviving issue.
2. If the original concern only existed on an unmerged draft PR, keep it in PR review until merged-state evidence proves it should become a standalone execution issue.
3. Keep conversational planning in the user chat. Do not post issue comments that enumerate options, recommendations, or chat-style `next runs`.
4. If a separate execution-status comment is necessary before PR closeout, keep it deterministic: current state, selected next slice, blockers, validation, and concrete human follow-up only.
5. Re-read the issue body after implementation, not before it.
6. Re-read the canonical plan comment and reconcile every implementation checkbox against shipped code.
7. Treat unresolved implementation checkboxes as blockers for PR readiness.
8. For source-changing PRs, use `inline-doc-governance` to audit changed repo-owned source files before opening or updating the PR.
9. Generate the PR body from the linked issue instead of writing it from memory.
10. Open the PR automatically once the issue is fully implemented and the closeout audit passes.
11. Before merge, re-read the current PR body and treat unchecked PR checklist items as merge blockers.
12. Before merge, re-run or verify `inline-doc-governance` if new commits changed repo-owned source files.
13. Before merge, re-audit every additional issue the PR will close and treat their unresolved checklist state as merge blockers.
14. If the merge audit fails, report the blockers and continue the work instead of merging.

## Inline documentation audit

For PRs that change repo-owned source files, load the `inline-doc-governance` skill as part of PR closeout. Run its deterministic audit against the changed source paths, using the target repo's local policy when one exists and the `public` policy otherwise. Then do the semantic pass for comments the script cannot prove: file headers, public or cross-boundary type docs, side effects, fallback behavior, provider quirks, and comments near changed code.

Keep comments synchronized with behavior in the same PR. Update comments whose contract, side effect, ownership, fallback, or edge case changed; delete comments that no longer match the code; and avoid adding comments that only narrate syntax.

Do not edit generated, vendored, test, or build-output files while satisfying the audit. If the audit reports generated code, update the exclusion rules or narrow the audited path set instead of patching generated output.

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
  --inline-doc-audit ran \
  --inline-doc-audit-note "inline-doc-governance audit passed for changed source paths" \
  --summary "Implement issue-to-PR closeout gate in the skill" \
  --summary "Add a local helper script for audit and PR creation"
```

Create or update the PR after the audit passes:

```bash
python3 skills/github-issue-workflow/scripts/issue_pr_closeout.py open-pr \
  --issue 123 \
  --base main \
  --inline-doc-audit ran \
  --inline-doc-audit-note "inline-doc-governance audit passed for changed source paths" \
  --summary "Implement issue-to-PR closeout gate in the skill" \
  --summary "Add a local helper script for audit and PR creation" \
  --validation "python3 scripts/quick_validate_skill.py skills/github-issue-workflow"
```

Merge the PR only after the merge audit passes:

```bash
python3 skills/github-issue-workflow/scripts/issue_pr_closeout.py merge-pr \
  --issue 123 \
  --method merge
```

## Expected behavior

- If the supplied issue is already closed, labeled `duplicate`, or explicitly marked as duplicate/superseded by another issue in its comments, the helper exits non-zero instead of treating it as the canonical closeout thread.
- If the canonical plan comment is missing, the helper exits non-zero.
- If unchecked implementation checklist items remain in the issue body or plan comment, the helper exits non-zero.
- If issue comments outside the canonical plan comment contain `Execution is not started yet`, `Next runs`, `Run options`, `Option A/B/C`, or similar planning markers, the helper exits non-zero.
- If unchecked checklist items remain in the PR body, the merge audit exits non-zero.
- If the PR is still a draft, the merge audit exits non-zero.
- If related issues that the PR closes still have unchecked issue or blocking plan items, the merge audit exits non-zero.
- Open items under `External Setup Dependencies` remain visible in the audit output but do not block PR creation by themselves.
- The helper requires `--inline-doc-audit ran|skipped` and `--inline-doc-audit-note` when rendering or opening a PR.
- The merge audit exits non-zero when the PR body does not include an explicit checked inline-doc audit status.
- If the current branch already has a PR, the helper updates that PR instead of creating a duplicate.
- If the current branch is not pushed yet, the helper exits non-zero and tells you to push the branch first.
- The helper carries the issue milestone into the PR when one exists.
- The merge audit prints blockers grouped by source so the agent can continue work on those items instead of guessing.
- The inline-doc audit remains skill-driven; the helper does not infer repository source ownership or semantic comment quality.
- If an execution-status comment is posted before PR closeout, it stays deterministic and does not contain option menus or recommendation prose.

## Notes

- The helper is strict on implementation checklists because the failure mode here is agents moving on too early.
- The merge audit is intentionally separate from `open-pr` because PR opening and PR merging happen at different points in the workflow.
- The helper is local-first. CI can layer on top later, but this workflow should stand on its own without CI.
- Execution-status comments are optional. When the canonical plan and PR body already carry the durable truth, do not add a separate issue comment.

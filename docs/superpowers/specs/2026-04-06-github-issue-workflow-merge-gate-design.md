# GitHub Issue Workflow Merge Gate Design

Date: 2026-04-06
Topic: Harden the `github-issue-workflow` merge path so merge checks PR, linked issue, canonical plan comment, and related issues before merging

## Goal

Extend the bundled GitHub issue workflow so a user-requested merge is blocked unless every relevant checklist item is reconciled across the PR and the issues that the PR is closing.

The merge path must:

- inspect the PR body checklist state
- inspect the primary linked issue body and canonical plan comment
- inspect related issues that the PR closes
- print actionable blocker output when anything is still open
- merge only after the audit passes

## Why

The current helper stops at PR creation and update. That is strict enough to open a good PR, but it does not protect the final merge request.

That leaves two gaps:

- reviewers or agents can add unchecked PR checklist items after the PR is opened
- a PR can close multiple issues, but the helper only audits one issue today

The result is that merge readiness can drift after the PR body was first generated.

## Scope

In scope:

- add an explicit merge command to the local helper
- audit PR checklist items before merge
- audit the primary linked issue and related issues before merge
- report blockers grouped by source so the agent can continue work instead of merging early
- update the skill guidance and closeout reference to make merge a separate audited step

Out of scope:

- changing the repo's GitHub-side branch protection or CI rules
- auto-editing issue or PR checklist state to mark items complete
- guessing unrelated issue references outside the PR closeout contract

## Recommended Approach

Add a new `merge-pr` command to `skills/github-issue-workflow/scripts/issue_pr_closeout.py`.

This is the preferred approach because it keeps responsibilities clear:

- `audit` remains the issue-centric closeout check
- `open-pr` remains the PR creation/update step after issue closeout passes
- `merge-pr` becomes the final gate that re-audits current PR and issue state immediately before merge

Rejected alternatives:

1. Expand `open-pr` so it also merges.
This conflates two different lifecycle stages. Opening a PR and merging a reviewed PR happen at different times and need different inputs.

2. Strengthen only the existing issue audit and leave merge implicit.
This still leaves a gap where PR or related issue checklist state can change after the PR is opened.

## User-Facing Behavior

When an agent is asked to merge a PR for tracked work, the workflow should run:

`python3 skills/github-issue-workflow/scripts/issue_pr_closeout.py merge-pr --issue <n>`

The command should:

1. resolve the current branch's PR, or use an explicitly supplied PR reference
2. verify that the PR closes the primary linked issue
3. parse PR checklist items and block on any unchecked item
4. audit the primary linked issue body and canonical plan comment
5. audit every additional related issue that the PR closes
6. print grouped blocker output and exit non-zero if any required item is still open
7. merge the PR only when all blocking items are resolved

If the audit fails, the command must not merge. The output must make it obvious that the work is still in execution and list what needs to be finished or rewritten first.

## Related Issue Rule

Treat related issues as the additional issues that GitHub says the PR will close on merge.

Use the PR's `closingIssuesReferences` metadata as the canonical source, excluding the primary issue supplied through `--issue`.

This keeps the merge gate strict without turning every loose `#123` mention into a blocker.

## Merge Safety Rules

Rules:

- do not merge when the PR body has unchecked checklist items
- do not merge when the primary issue body has unchecked checklist items
- do not merge when the primary canonical plan comment is missing
- do not merge when the primary canonical plan comment has unchecked blocking implementation items
- do not merge when any related closing issue has unchecked checklist items
- do not merge when any related closing issue is missing its canonical plan comment
- do not merge when any related closing issue has unchecked blocking plan items
- keep `External Setup Dependencies` non-blocking for issue-plan audits, as the current workflow already does
- do not guess merge readiness from stale PR-body counts; always re-audit live PR and issue state

## Failure Handling

Failure output must be source-aware and action-oriented.

The merge audit should print:

- PR metadata and primary issue metadata
- open PR checklist items
- open linked-issue checklist items
- open linked-issue blocking plan items
- open related-issue checklist items grouped per issue
- open related-issue blocking plan items grouped per issue
- a final blocker summary that clearly says merge is blocked and work must continue

## Script Changes

File:

`skills/github-issue-workflow/scripts/issue_pr_closeout.py`

Planned changes:

- add PR fetch logic with checklist parsing
- add merge-audit datatypes for PR plus multiple issue audits
- add related-issue discovery from PR `closingIssuesReferences`
- add a `merge-pr` subcommand
- add strict merge blockers for open PR checklist items and unresolved related issue state
- add merge execution through `gh pr merge` only after the merge audit passes
- add clear dry-run output for the merge command

## Skill Documentation Changes

Files:

- `skills/github-issue-workflow/SKILL.md`
- `skills/github-issue-workflow/references/issue-pr-closeout.md`
- `skills/github-issue-workflow/references/implementation-readiness.md`

Planned changes:

- document merge as a separate audited step
- state that PR checklist items and related closing issues are merge blockers
- state that unresolved blockers mean the agent must continue the work instead of merging
- document the new local helper usage for merge

## Verification Plan

Verification should cover:

- `python3 -m py_compile skills/github-issue-workflow/scripts/issue_pr_closeout.py`
- `python3 scripts/quick_validate_skill.py skills/github-issue-workflow`
- `python3 scripts/validate_skills.py`
- dry-run merge command formatting and blocker output on synthetic or known refs when practical
- doc text remains aligned with helper behavior

# State Transition Rules

Use this reference before closing, moving, or treating work as done across Linear and GitHub.

## GitHub State

GitHub issue state follows engineering execution:

- Open while implementation, validation, or PR closeout remains.
- Closed when the linked implementation checklist and validation proof are complete.
- Reopened or followed up when shipped code does not satisfy the engineering contract.

PR merge means engineering code landed. It does not prove product acceptance unless the product workflow says merge is the acceptance point.

## Linear State

Linear state follows PM or project-management ownership:

- Keep Linear open while product acceptance, QA, release, PM review, customer validation, or PRD sync remains.
- Move Linear only when the user, PM workflow, Linear issue, or explicit metadata convention authorizes it.
- Do not move Linear solely because a related GitHub issue closed or a PR merged.

If the implementation is complete but product acceptance remains, add or update implementation links in Linear and leave the PM-managed state alone.

## Product Drift

When engineering changes product meaning, acceptance, scope, sequencing, or rollout:

1. Record the engineering evidence in GitHub.
2. Comment or update Linear in PM language.
3. Reconcile the Linear issue body after a product decision is accepted.
4. Continue implementation only from the reconciled contract.

Do not hide product drift in PR review, code comments, GitHub-only checklists, or chat.

## Closeout Checks

Before closing or moving artifacts, ask:

- Is this an engineering completion, product acceptance, release milestone, or documentation milestone?
- Which system owns that milestone?
- Are unresolved product decisions still listed in Linear?
- Are unresolved implementation checklist items still listed in GitHub?
- Does a PRD or durable doc need sync after the Linear decision settles?

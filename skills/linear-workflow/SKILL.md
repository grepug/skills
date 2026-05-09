---
name: linear-workflow
description: Use when creating or updating Linear issues as PM/product contracts, turning docs or discussion into Linear work, applying Linear labels/cycles/priorities/assignees/projects, discussing contract flaws, or linking Linear product issues to GitHub engineering issues and PRs.
---

# Linear Workflow

Use Linear as the product-management contract layer. A Linear issue should say what outcome is needed, why it matters, what is in or out of scope, how success will be accepted, which source material informed it, and what still needs product decision.

Default to Linear first. Create or update a Linear issue before implementation when a task is meaningful product, design, or implementation work. Use GitHub Issues only when engineering execution needs developer-language decomposition, code anchors, validation detail, repository automation, project tracking, cross-reference, or closeout.

When work involves both Linear and GitHub, use `linear-github-coordination` first to decide artifact ownership, linking, state-transition boundaries, and whether a GitHub engineering issue is actually needed. If `linear-github-coordination` already selected Linear as the mutation surface, continue here without re-entering coordination.

Write Linear issues and comments in the target repo's Linear language. Determine it in this order: explicit user instruction, repo guidance such as `AGENTS.md`, contributor docs, or workflow docs, existing issue body language when updating an issue and no Linear-specific language is defined, then English for new issues with no guidance. Linear language may differ from GitHub issue, PR, code, or general repo working language.

## Use When

- The user asks to create, update, inspect, or discuss Linear issues.
- Product docs, PRDs, chat notes, oral decisions, branches, PRs, or pasted context need to become PM-language Linear work.
- A developer needs to push back on a Linear issue because scope, acceptance criteria, feasibility, sequencing, or interpretation is unclear.
- Linear metadata such as labels, priorities, cycles, projects, milestones, assignees, estimates, blockers, or related issues should be applied.
- A Linear product issue needs a linked GitHub engineering issue or PR.
- A workspace needs a portable starting taxonomy for Linear metadata.

## Core Model

- Linear issue: PM/product contract, product decisions, acceptance outcomes, scope, source links, blockers, and PRD sync state.
- Linear comment: product-scope discussion, pushback, decision request, decision summary, blocker, or handoff note.
- GitHub issue: optional developer execution record with code anchors, implementation plan, validation commands, technical risks, and PR closeout.
- GitHub PR: implementation diff, review trail, validation proof, and merge record.
- Durable docs or PRDs: stable product memory after Linear decisions settle.

If Linear and GitHub differ, Linear owns product intent and acceptance outcomes. GitHub owns engineering execution details and validation proof. Sync material product changes back to Linear before continuing.

## Mode Selection

Use PM mode when the input is product intent, source material, PRD content, discussion notes, a roadmap item, or a request to shape PM-facing work. Read `references/pm-mode.md` for detailed issue-body shape and examples.

Use developer mode when the input starts from implementation, code, a branch, a PR, an engineering concern, or a Linear issue that needs developer execution tracking. Read `references/developer-mode.md`.

For any work that creates or updates a Linear issue, first discover the workspace metadata and apply existing conventions. Read `references/linear-metadata.md`.

When the workspace has no useful metadata conventions, propose the portable preset before creating new labels, projects, or status conventions. Read `references/preset-taxonomy.md`.

When a detail is unclear, a body edit is made, or a developer finds a flaw in the product contract, comment in Linear instead of resolving it only in chat or GitHub. Read `references/discussion.md`.

## Required Workflow

1. Identify the mode: PM or developer.
2. Inspect the source of truth available for the task: docs, issue, discussion, branch, PR, repo guidance, or pasted context.
3. Determine the Linear language hierarchy: explicit user instruction, repo guidance, existing issue body language for updates with no designation, then English for new issues with no guidance.
4. Search for an existing Linear issue with matching source links, title, project, branch, PR, GitHub issue, or product scope. Reuse or update the existing contract when one matches; create a new issue only when no matching contract exists.
5. Extract requirements that still need PM discussion before acceptance or closeout. Include them explicitly in the Linear issue or comment.
6. Discover Linear team metadata before assigning fields.
7. Reuse existing labels, statuses, cycles, projects, milestones, and assignees where they fit.
8. Create or update the Linear issue in PM language, using the determined Linear language.
9. Link source material and implementation artifacts.
10. If developer execution needs a GitHub issue, create or update it with developer-language scope and link it back to Linear.
11. Use Linear comments for product-contract discussion, decision requests, scope changes, and final product decisions.
12. After a Linear comment records or resolves a product decision, reconcile the issue body before continuing implementation or closeout: the body should show only the current contract, while comments preserve the decision history.
13. Each time you edit the issue body, leave a Linear comment in the determined Linear language, summarizing what changed and why, with links to the decision or source material when available.

## Linear Write Policy

- Read-only inspect, audit, summarize, or discuss requests should not mutate Linear unless the user explicitly asks for an update.
- Before creating a new issue, confirm the target team when more than one team fits or no repo/workspace default is explicit.
- Before major body rewrites, status changes, duplicate closure, or metadata changes that route ownership or priority, draft the intended update and apply it only when the user request or Linear discussion clearly authorizes that mutation.
- When the target issue and requested edit are explicit, apply the update directly, then report what changed.
- Never silently overwrite an issue body from stale or conflicting source material. If sources disagree, comment with the decision needed or ask before rewriting the contract.

## Output

Successful use of this skill should leave:

- a Linear issue or comment that reads in PM/product language
- Linear content written in the determined Linear language
- an explicit list of product requirements or acceptance details that still need discussion, or `None` when the contract is complete
- an existing matching Linear issue reused when one exists, instead of creating duplicate product contracts
- existing Linear metadata applied where available
- a proposed metadata preset only when existing conventions are absent or weak
- GitHub engineering issues created only when needed
- bidirectional links between Linear and GitHub artifacts when both exist
- product decisions recorded in Linear before implementation proceeds
- issue body reconciled to the latest accepted product contract, with obsolete wording removed rather than kept as strikethrough
- a Linear comment in the determined language for every issue-body edit, so the body stays current while the comment thread preserves edit history
- PRD or durable-doc sync called out when the Linear decision becomes stable product direction

## Bundled References

- `references/pm-mode.md` - create PM-language Linear issues from any source.
- `references/developer-mode.md` - connect Linear product contracts to GitHub engineering work.
- `references/linear-metadata.md` - discover and apply Linear metadata.
- `references/preset-taxonomy.md` - portable fallback metadata shape.
- `references/discussion.md` - comment, push back, split scope, and record decisions.

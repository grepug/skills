---
name: linear-workflow
description: Product-agnostic Linear workflow for creating, updating, inspecting, and discussing product issues, metadata, status, scope, confirmation needs, and durable product-doc sync.
---

# Linear Workflow

This skill is product agnostic. Keep the default guidance portable across products, teams, and repositories. Do not hard-code a product name, a team's private status model, a fixed label set, or product-specific document paths into this skill. Product-specific rules may appear only as clearly marked examples or as conventions discovered from the active repo, Linear workspace, or explicit user instruction.

Linear is the product execution contract and progress-management layer. A Linear issue should clearly state what problem is being solved, why it matters, what is in scope, what is out of scope, how the work will be accepted, and which product questions still need a decision.

Durable product documents, PRDs, design docs, or repo-owned planning files are long-term product memory when a team uses them. Linear should be complete enough for a developer or AI agent to execute the work, but it does not automatically replace durable docs unless the team explicitly says so.

If a Linear discussion creates a stable decision that changes product behavior, scope, acceptance criteria, data rules, status rules, language rules, or agent behavior, ask whether the decision should be synced back to the relevant durable docs. Do not silently edit product docs from a Linear decision unless the user or team workflow explicitly authorizes it.

## Use When

Use this skill when:

- The user asks to create, update, inspect, summarize, or discuss Linear issues.
- Product docs, design docs, chat notes, oral decisions, screenshots, PRDs, branches, PRs, or pasted context need to become Linear work.
- A developer or AI agent needs to push back on issue scope, acceptance criteria, feasibility, sequencing, or interpretation.
- Linear metadata such as labels, statuses, priorities, assignees, teams, projects, cycles, milestones, parent-child links, blockers, or related issues should be applied.
- A Linear decision may need to be reconciled with durable product documentation.
- A large requirement needs to be split into executable issues.
- A Linear product issue needs a linked GitHub engineering issue or PR.

## Core Model

- Durable product docs: long-term product memory for stable product rules, interaction rules, data rules, and decisions when the repo or team uses them.
- Linear project: a larger product or delivery goal.
- Linear milestone or cycle: a stage, release slice, or planning interval inside a project.
- Linear issue: the current execution contract for one coherent product or engineering task.
- Linear comment: discussion, pushback, decision request, decision record, blocker, or handoff note.
- GitHub issue: optional developer execution record with code anchors, implementation detail, validation commands, and technical risks.
- GitHub PR: implementation diff, review trail, validation proof, and merge record.

If Linear and durable docs disagree, confirm which source contains the latest accepted decision. Do not silently overwrite either side with stale or conflicting information.

## Product-Agnostic Rules

- The default workflow must work for any product.
- Treat explicit user instruction, repo guidance, existing Linear workspace conventions, and existing issue metadata as the source for product-specific behavior.
- Product-specific label names, status names, milestone names, project names, document paths, and examples must be marked as examples unless they were discovered in the active workspace.
- Do not convert this skill into a product-specific playbook. If a product needs fixed rules, put them in that product's repo guidance, a dedicated profile, or a clearly labeled example section.
- When editing this skill, prefer neutral terms such as "the product", "the team", "durable docs", "confirmation label", and "review status" over a specific product name.

## Language Selection

Write Linear issues and comments in the target repo or workspace language. Determine it in this order:

1. Explicit user instruction.
2. Repo guidance such as `AGENTS.md`, contributor docs, workflow docs, or product docs.
3. Existing Linear issue body language when updating an issue and no workspace-specific language is defined.
4. English for new issues with no guidance.

Linear language may differ from GitHub issue, PR, code, or general repo working language.

## Metadata Discovery

Before creating or updating Linear metadata:

1. Search for an existing issue with matching source links, title, project, branch, PR, GitHub issue, or product scope.
2. Inspect existing team labels, statuses, priorities, projects, cycles, milestones, and assignees.
3. Reuse existing metadata where it fits.
4. Ask before creating new labels, statuses, projects, or milestones unless the user explicitly asked for that mutation.
5. If the workspace has no useful conventions, propose a portable preset as a recommendation, then apply it only after the user accepts or the task clearly authorizes it.

## Label Rules

Labels should describe issue type, ownership, decision state, or workflow routing. Prefer existing workspace labels.

Common portable label categories:

- Feature: new user-facing or product capability.
- Improvement: enhancement to existing behavior.
- Bug: incorrect behavior or regression.
- Agent or Automation: AI, agent, or automation behavior.
- Product Decision Required: scope, acceptance, priority, sequencing, or product behavior is blocked on a decision.

These names are examples, not fixed defaults. If the workspace uses different names such as `Needs PM`, `Question`, `Design`, or localized labels, use the workspace convention.

Do not use ad hoc labels for release scope, product area, milestone, or doc-sync state when the workspace already has projects, milestones, cycles, or comments that represent those concepts better.

## Status Rules

Use the workspace's existing status flow. If there is no clear convention, recommend a minimal portable flow:

- Backlog: need is identified, but scope, acceptance criteria, priority, or timing is not ready.
- Todo: issue is ready for development or execution.
- In Progress: work has started.
- In Review: implementation is ready for engineering, design, or product review.
- Testing: work is ready for product, QA, or full-flow validation when the workspace separates testing from review.
- Done: accepted and no known blocking follow-up remains.
- Canceled: no longer needed.

These status names are examples. Do not assume every workspace has `Testing`, `Duplicate`, or the exact labels above. When duplicate issues are found, ask which issue should remain canonical unless the workspace has an explicit duplicate policy.

## Initial Status For New Issues

When creating a new issue:

- Use the workspace's default ready state if goals, scope, boundaries, and acceptance criteria are clear.
- Use the workspace's backlog or discovery state if the need is valid but scope, acceptance criteria, priority, or timing is unclear.
- Add the workspace's confirmation label or blocker note when product decisions are required before reasonable execution can continue.
- Ask when status, label, priority, project, milestone, assignee, or issue boundary is unclear.
- Do not create an issue as in progress unless the user says the work has started or you are backfilling existing work.
- Do not create an issue as review, testing, or done unless you are backfilling work that is already in that state.

## Issue Body Standard

Every issue should let a developer or AI agent complete the work primarily from the issue content. Fine UI, motion, visual design, or implementation details may still require linked source material, but the Linear body should contain the current execution contract.

Each issue should include:

- Problem: the user or product problem being solved.
- Desired outcome: what should be true after delivery.
- Scope: what this issue includes.
- Boundaries: what this issue explicitly excludes.
- Acceptance criteria: how completion will be judged.
- Open questions: unresolved product decisions, or "None" when the contract is complete.

Source links and doc-sync notes are useful when relevant, but they should not replace the execution contract. Keep the issue body current; preserve decision history in comments.

## Issue Boundary Rules

Each issue should describe one coherent product capability, workflow step, technical task, or decision path. Avoid mixing unrelated modules or acceptance paths into one issue.

Examples:

- A localization issue can cover target languages, interface language, fallback behavior, and display scope.
- A localization issue should not also define unrelated scoring, generation, or feedback rules unless those are part of the same acceptance path.
- A workflow issue can cover inputs, outputs, state transitions, retries, and completion state for that workflow.
- An onboarding issue can cover first-run entry, user choices, guidance path, and the condition for reaching the main experience.
- An agent issue can cover agent goal, inputs, outputs, follow-up questions, stop conditions, and handoff behavior without specifying unrelated page layout.

If one issue starts to contain two independent acceptance paths, recommend splitting it or linking related issues.

## Split-Size Rules

Issues should be neither too broad nor too small.

A good issue:

- Represents one complete product capability, delivery unit, technical task, or decision path.
- Can be completed in one focused implementation or decision cycle.
- Has one clear acceptance path.
- Can be tested or verified relatively independently.

An issue is too broad when it:

- Contains multiple unrelated user goals.
- Mixes product exploration, UI design, backend work, rollout, and testing without clear boundaries.
- Cannot be judged complete with one coherent set of acceptance criteria.

An issue is too small when it:

- Is only one button, one copy tweak, one field, or one tiny UI adjustment without independent product value.
- Is only an implementation step rather than a product or engineering outcome.
- Creates more task-management overhead than delivery clarity.

If a concept is really phase management, such as "first experience", "content creation", "billing readiness", "launch basics", or "market adaptation", recommend using a project, milestone, cycle, or parent issue according to workspace convention.

## Project And Milestone Rules

Use existing projects, milestones, cycles, and parent issues when the user or workspace convention makes the target clear.

Ask before creating or materially changing projects, milestones, or cycles. These usually affect planning structure across multiple issues.

If the correct project or milestone is unclear, ask the product owner or user instead of guessing.

## Product Confirmation Rules

Use the workspace's confirmation label, blocker status, or explicit comment when an issue has unresolved product decisions. Examples include:

- Acceptance criteria are unclear.
- Scope boundaries are unclear.
- Priority, release inclusion, or sequencing is unclear.
- It is unclear whether the issue should be split.
- Requirements conflict with existing docs, existing issues, or actual implementation.
- Execution cannot continue without a product decision.

After the decision is made, update the issue body so it reflects the latest execution contract. Remove the confirmation label or blocker state only when no blocking product question remains.

## Durable Doc Sync Rules

Do not assume Linear decisions automatically update durable product docs. Ask when a stable Linear decision changes product memory.

Ask whether to sync durable docs when:

- A Linear comment records a final decision that changes product behavior.
- Acceptance criteria change.
- Scope is added, removed, or deferred.
- Data rules, status rules, language rules, or agent behavior change.
- Testing reveals that durable docs and accepted behavior disagree.

Recommended wording:

"This decision affects durable product documentation. Should I update the relevant docs as well?"

Only update durable docs after explicit authorization or when repo guidance says this sync is automatic.

## Workflow

1. Identify whether the user is discussing, creating, updating, inspecting, summarizing, or splitting Linear work.
2. If the request is read-only, do not mutate Linear unless the user explicitly asks for an update.
3. Inspect available source material: docs, issue, discussion, branch, PR, repo guidance, or pasted context.
4. Determine the language for Linear content.
5. Search for an existing matching issue. Reuse or update an existing contract when one matches; create a new issue only when no matching contract exists.
6. Discover workspace metadata before assigning labels, statuses, priorities, projects, milestones, cycles, or assignees.
7. Judge whether issue boundaries are clear. Ask or recommend a split when they are not.
8. Apply existing metadata conventions, or recommend a portable fallback when conventions are absent.
9. Create or update the issue body so it is the current execution contract.
10. Use Linear comments for product-contract discussion, decision requests, blockers, and summaries of body changes.
11. If product decisions are required, mark them with the workspace's confirmation mechanism.
12. After a decision, reconcile the issue body with the latest accepted contract and keep historical context in comments.
13. If a decision affects durable product docs, ask whether to sync the docs before editing them.
14. If developer execution needs a GitHub issue or PR link, create or update that artifact and link it back to Linear.

## Write Policy

- Read-only inspect, audit, summarize, or discuss requests should not mutate Linear unless the user explicitly asks for an update.
- Before creating a new issue, confirm the target team when more than one team fits or no repo/workspace default is explicit.
- Before creating new labels, statuses, projects, milestones, or cycles, recommend the change and ask unless the user explicitly requested it.
- Before major body rewrites, status changes, duplicate closure, or metadata changes that route ownership or priority, draft the intended update and apply it only when authorized by the user request or Linear discussion.
- When the target issue and requested edit are explicit, apply the update directly, then report what changed.
- Never silently overwrite an issue body from stale or conflicting source material. If sources disagree, comment with the decision needed or ask before rewriting the contract.
- Each time you edit the issue body, leave a Linear comment in the determined language summarizing what changed and why, with links to the decision or source material when available.
- Do not sync durable product docs without explicit authorization unless repo guidance says the sync is automatic.

## Output

Successful use of this skill should leave:

- Linear issue or comment content written in product language rather than only implementation steps.
- Content written in the determined Linear language.
- A current issue body that states the execution contract.
- Clear problem, desired outcome, scope, boundaries, acceptance criteria, and open questions.
- Existing workspace labels, statuses, priorities, assignees, projects, milestones, and cycles reused where they fit.
- Product blockers marked with the workspace's confirmation mechanism.
- Duplicate issues avoided or resolved through the workspace's canonicalization process.
- Related product, GitHub, design, or documentation artifacts linked when relevant.
- Durable-doc sync called out when a stable Linear decision changes long-term product memory.
- No hard-coded product-specific rule introduced into the product-agnostic skill unless it is clearly marked as an example.

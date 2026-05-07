# Linear Metadata

Always discover existing Linear metadata before assigning fields or proposing new conventions. Prefer workspace-native values over the portable preset.

## Discovery Order

1. Teams: find the target team by user request, workspace default, related issues, or project context.
2. Existing issues: search by source links, title, project, branch, PR, GitHub issue, and product scope before creating a new contract.
3. Statuses: list statuses for the team and choose the one matching the work state.
4. Labels: list team or workspace labels and reuse exact matches or closest established labels.
5. Priorities: map urgency to Linear's native priority scale.
6. Projects and milestones: attach work to a larger initiative only when it belongs to one.
7. Cycles: use the current or next cycle only when the team uses timeboxed delivery.
8. Assignees: assign only when the user requests it, the source names an owner, or workspace convention makes ownership obvious.
9. Relations: add blockers, blocked-by, related, duplicate, or parent links when they reflect real product or execution relationships.

## Field Guidance

Team is required for creating issues. If multiple teams fit and the source does not identify one, ask briefly or choose the repo/workspace default only when it is explicit in local guidance.

Existing matching issues should be reused instead of duplicated. If several candidates fit, ask or recommend which issue should remain canonical before changing relations, status, or body content.

Status should reflect workflow state. Use backlog or todo for new product contracts unless the user or current work state indicates active execution.

Priority should describe product urgency, not implementation difficulty:

- Urgent: immediate blocker, launch-critical, severe user impact.
- High: important committed work or high-impact problem.
- Medium: default planned work.
- Low: useful but not currently time-sensitive.
- None: no assigned priority for ideas, parking lot items, or unprioritized research.

Labels should classify the work. Prefer a small set that helps filtering and routing. Do not overload labels with status, priority, or assignee meaning when Linear already has those fields.

Projects are for larger initiatives. Do not create one project per issue.

Cycles are delivery scheduling tools. Do not force cycles when the team does not use them.

Estimates are optional. Use them only when the team already estimates or the user asks.

Assignees are ownership signals. Leave unassigned when ownership is not clear.

## Creating Metadata

Do not create new labels, projects, milestones, statuses, or cycles silently. If conventions are absent or weak:

1. summarize the discovered gap
2. propose the preset from `references/preset-taxonomy.md`
3. apply it only when the user or workspace workflow asks for bootstrap behavior

When a Linear connector is unavailable, draft the desired issue body and metadata mapping, then ask the user to connect Linear or create it manually.

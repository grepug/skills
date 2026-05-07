# Preset Taxonomy

Use this only when a Linear workspace has no mature conventions or the user asks to bootstrap a consistent shape. Discover existing metadata first.

## Labels

Recommended starter labels:

- `Feature`: new user-visible capability or product workflow
- `Bug`: user-facing behavior is wrong or broken
- `Improvement`: existing behavior should become better without changing the core promise
- `Research`: bounded discovery needed before a product or implementation decision
- `Design`: product design, interaction, content, or UX shaping
- `Docs`: PRD, product docs, contributor docs, or durable written guidance
- `Needs decision`: product contract has an open PM decision
- `Blocked`: progress depends on another issue, person, vendor, or environment
- `Engineering follow-up`: product issue needs or has a linked developer execution task

Keep labels about classification and routing. Use Linear fields for status, priority, cycle, assignee, and project.

## Priorities

Map to Linear's native scale:

- Urgent: must interrupt current work; launch, outage, severe customer impact, or critical blocker
- High: committed and important; should be pulled into the near-term plan
- Medium: default planned work
- Low: useful but not time-sensitive
- None: no assigned priority for ideas, parking lot items, or unprioritized research

Do not map engineering effort to priority. Effort belongs in estimate or implementation planning.

## Statuses

Recommended workflow shape:

- Backlog: captured but not selected for immediate work
- Todo: ready and selected
- In Progress: actively being shaped or implemented
- In Review: awaiting PM review, design review, implementation review, or acceptance
- Done: accepted and no required follow-up remains
- Canceled: intentionally not pursuing

If Linear uses status types, map these names to the closest existing status type instead of creating duplicates.

## Cycles

Use cycles only for timeboxed delivery. A simple preset is:

- current cycle for selected active work
- next cycle for committed near-term work
- no cycle for backlog, ideas, or unscheduled research

Do not add cycles to every issue just to fill the field.

## Projects And Milestones

Use projects or milestones for product initiatives that contain multiple issues. A project should have:

- a named product outcome
- a target audience or workflow
- multiple related Linear issues
- a rough target date or planning horizon when known

Do not create a project for a single small issue unless the workspace uses projects as roadmap containers.

## Bootstrap Policy

When applying this preset:

1. present the labels, statuses, and priority mapping that will be created or adopted
2. reuse existing matching names where possible
3. create only the missing pieces the user approved
4. record the chosen taxonomy in a durable workspace note or issue comment when the workspace needs future agents to follow it

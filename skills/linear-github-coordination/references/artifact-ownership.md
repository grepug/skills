# Artifact Ownership

Use this reference to decide which system should own the current truth.

## Linear Owns

- User problem or product opportunity
- Desired outcome and acceptance criteria
- Product constraints, non-goals, and launch sequencing
- Priority, project, cycle, estimates, assignee, and PM-managed status
- Open product decisions and final decision summaries
- PRD or durable-doc sync expectations
- Customer, stakeholder, roadmap, or release-management language

Keep Linear readable by PMs. Avoid file paths, function names, schema fields, test commands, and implementation checklists unless they are necessary to explain a product boundary.

## GitHub Owns

- Developer-language execution scope
- Code anchors, current behavior evidence, and affected modules
- API, schema, migration, rollout, and compatibility details
- Validation commands, test proof, logs, and technical risk
- Canonical implementation plan comments
- PR body, review trail, merge proof, and engineering closeout

Keep GitHub deterministic. Do not use GitHub issue bodies or comments for product option menus, PM debates, or state changes that belong in Linear.

## When To Use Both

Use both systems when a product contract needs developer execution tracking that would be too technical or too volatile for Linear.

Common cases:

- One Linear issue needs multiple GitHub engineering issues or PRs.
- A GitHub implementation has product-visible scope, release, or acceptance impact.
- Multiple agents or PRs need a shared developer checklist.
- Engineering discovers a product ambiguity that needs PM decision before implementation continues.

Do not use both systems merely because both tools exist.

## Conflict Rule

When the two artifacts conflict:

- Linear wins on product intent and acceptance.
- GitHub wins on technical feasibility and validation evidence.
- The conflict is not resolved until Linear records the product decision and GitHub records the implementation consequence.

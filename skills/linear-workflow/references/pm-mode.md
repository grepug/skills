# PM Mode

Use PM mode when the user gives product intent, PRDs, docs, chat notes, oral decisions, branch summaries, screenshots, customer requests, or any other source that should become Linear product work.

## Source Scan

Accept any source that the environment can read:

- local files or folders
- GitHub, PR, issue, or doc URLs
- pasted text
- screenshots or images when visible context matters
- branch or PR summaries
- existing Linear issues or comments

Do not assume the source is perfectly current. Treat it as evidence to distill into a Linear contract. If sources disagree, record the disagreement as a decision point in Linear.

## Issue Shape

Write the Linear issue in PM language and in the target repo's designated Linear language. If the repo has no Linear-specific language rule, use English.

- Problem: what user, product, workflow, or business problem is being solved.
- Desired outcome: what should be true when this ships.
- Acceptance criteria: observable behavior or product outcomes, not implementation steps.
- Constraints and non-goals: what should remain out of scope.
- Source links: docs, PRDs, discussion, branches, screenshots, or related issues.
- Requirements needing discussion: concrete product requirements, acceptance details, scope boundaries, or launch criteria that are not settled yet.
- Decision points: the specific decisions needed to settle those requirements.
- Implementation links: GitHub issue or PR URLs when they exist.
- PRD sync: whether durable docs need to be updated after the decision settles.

Avoid developer-only language such as file paths, function names, schema fields, test commands, or refactor steps unless they are necessary for a PM to understand the scope boundary.

Always include a `Requirements needing discussion` section when source material is incomplete, branch-first, implementation-first, contradictory, or still under review. Use short bullets phrased as product requirements, not engineering tasks. Use `None` only when the Linear issue is already a complete product contract with no unresolved product requirement, acceptance, scope, or sequencing questions.

Keep the issue body focused on the current contract. If discussion comments remove or change scope, update the body to the latest accepted wording and preserve the old reasoning in comments instead of leaving strikethrough text in the body.

Keep source links, issue identifiers, branch names, PR titles, and quoted product terms in their original form when translating the surrounding issue body.

## Metadata

Before creating a new issue, search for an existing Linear contract that matches the source links, title, project, branch, PR, GitHub issue, or product scope. Update or comment on the matching issue instead of creating a duplicate. If multiple candidates match, recommend the best surviving issue and ask before closing or marking duplicates.

Before creating or updating the issue, discover team metadata using `references/linear-metadata.md`.

Apply existing metadata when it fits:

- team
- status
- priority
- labels
- project or milestone
- cycle
- assignee
- estimate
- blocker or related issue links

If the workspace has no useful conventions, use `references/preset-taxonomy.md` to propose a portable preset. Do not create new labels, projects, or statuses silently.

Draft the proposed issue body or major body edit before writing when the target team, target issue, or source intent is ambiguous. When the user explicitly names the target and requested update, apply it directly and report the change.

## Ready Contract

A PM-mode Linear issue is ready for development when:

- the outcome and acceptance criteria are clear enough to verify
- non-goals or scope boundaries are stated
- any known product decision points are explicit
- requirements needing discussion are listed explicitly, or marked `None`
- the owning area or initiative is identifiable
- implementation links can be added later without changing product intent

If those are not true, create or keep the issue as discovery, discussion, or a lightweight product idea instead of pretending it is ready for implementation.

# Developer Mode

Use developer mode when work starts from code, a branch, a PR, a failing implementation path, or an existing Linear issue that needs engineering execution.

## Start From Linear

Search for a Linear issue first by source links, branch, PR, GitHub issue, title, project, or product scope.

If a matching Linear issue exists, read it and treat it as the product contract:

- product problem
- desired outcome
- acceptance criteria
- constraints and non-goals
- priority and project context
- open decisions
- PRD sync expectation
- recent body-edit comments that explain why the current contract changed

If no matching Linear issue exists for branch-first, PR-first, or code-first work, create or update the PM contract using `references/pm-mode.md` and metadata discovery before continuing implementation. When the source is ambiguous, draft the proposed Linear issue first instead of writing silently.

If the Linear issue is unclear, too broad, infeasible, or inconsistent, comment in Linear using `references/discussion.md` before changing the product contract in GitHub or code.

When implementing, derive engineering tasks from the current issue body. Use comments to understand why the body changed, not as a replacement for the body. If a comment contains an accepted decision that is not reflected in the body, reconcile the body and leave a body-edit comment before continuing.

## When To Create GitHub Issues

Create or update a GitHub engineering issue only when it adds real execution value:

- implementation needs developer-language decomposition
- code anchors, module boundaries, schemas, migrations, or validation commands need durable tracking
- repo automation, GitHub Projects, PR closeout, or issue templates are part of the workflow
- multiple PRs or agents need a shared engineering checklist
- the repo explicitly requires GitHub issues for implementation tracking

Do not create GitHub issues only to mirror every Linear issue. Linear remains the PM/product contract.

## GitHub Issue Shape

When a GitHub issue is needed, write it in developer language:

- link to the Linear issue at the top
- current evidence or code anchors
- implementation plan or checklist
- technical constraints, risks, and module boundaries
- validation commands and proof expectations
- related PRs or follow-up engineering tasks

Load and follow the repo's GitHub issue workflow skill when one exists. Keep GitHub issue comments focused on implementation facts, not product-scope debates.

## Linking Rules

When both Linear and GitHub artifacts exist:

- add the GitHub issue or PR URL as a Linear link
- add the Linear issue URL or identifier to the GitHub issue and PR body
- keep product-scope decisions in Linear
- keep implementation validation and closeout in GitHub
- sync any material product change back to Linear before continuing implementation

If a PR resolves the engineering issue but the product decision requires PRD sync, keep the Linear issue open or add a Linear follow-up until the durable docs are updated.

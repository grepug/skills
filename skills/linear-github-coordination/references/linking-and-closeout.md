# Linking And Closeout

Use this reference when both Linear and GitHub artifacts exist or should exist.

## Linking

Prefer links over duplicated bodies.

Linear should include:

- GitHub issue or PR URLs under implementation links
- A short PM-language reason the link matters
- Remaining product decisions or acceptance work, if any

GitHub should include:

- Linear issue URL or identifier near the top
- Developer-language scope and current evidence
- Implementation plan, validation, and PR closeout details

Do not copy full Linear issue bodies into GitHub. Do not copy full GitHub plans, logs, or checklists into Linear.

## Creating Artifacts

Create or update Linear when:

- Product intent, acceptance, priority, sequencing, or decision history needs a durable PM contract.
- A code-first or PR-first task has product impact and no matching Linear issue exists.
- Engineering discovered a product ambiguity or flaw.

Create or update GitHub when:

- Engineering execution needs technical decomposition, code anchors, or validation proof.
- Multiple PRs, agents, migrations, or rollout steps need a shared developer checklist.
- Repo automation or PR closeout depends on GitHub issue state.

Do not create GitHub issues just to mirror Linear. Do not create Linear issues just to mirror GitHub.

## Closeout

At PR open or update:

- Make sure GitHub explains implementation status and validation.
- Link the PR to GitHub issues and Linear issues when relevant.
- If product scope changed, update or comment in Linear before claiming completion.

At PR merge:

- Close or update GitHub according to engineering closeout rules.
- Do not automatically move Linear unless authorized by the Linear workflow or user.
- If Linear remains open, leave a short implementation link or comment only when it helps PM acceptance or follow-up.

At Linear closeout:

- Confirm acceptance criteria, product decisions, and PRD sync expectations are satisfied.
- Link final GitHub PRs or issues as implementation proof.
- Avoid reopening or changing GitHub unless engineering follow-up is actually needed.

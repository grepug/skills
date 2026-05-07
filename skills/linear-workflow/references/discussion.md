# Discussion

Use Linear discussion when the product contract needs clarification, pushback, or a recorded decision. Do not hide these decisions in chat, GitHub comments, or code review if they change product meaning.

## When To Comment

Comment in Linear when:

- the Linear issue lists requirements needing discussion
- acceptance criteria are ambiguous or unverifiable
- scope is too broad for one delivery slice
- implementation reveals a product flaw or missing edge case
- priority, sequencing, or ownership needs a PM decision
- docs, discussion, implementation, or existing issues disagree
- a GitHub engineering issue or PR changes what the Linear issue promises
- PRD sync is needed after a decision settles

Implementation/docs drift is one case of this broader discussion workflow, not the default path.

## Comment Shape

Write comments in product-contract language and in the target repo's designated Linear language. If the repo has no Linear-specific language rule, use English.

- Observation: what is unclear, conflicting, blocked, or newly discovered.
- Impact: why this affects user outcome, acceptance, priority, sequencing, or scope.
- Proposed decision: the smallest clear decision that would unblock work.
- Links: source docs, GitHub issue, PR, branch, screenshot, or related Linear issue.

Avoid long technical traces. Put test logs, code plans, stack traces, and validation proof in GitHub or PRs, then link them from Linear if needed.

When updating an issue body, keep a dedicated `Requirements needing discussion` section. Move resolved items out of that section by updating the contract or adding a short decision comment.

## Body Maintenance

Treat the issue body as the current product contract, not a changelog.

- When a comment records a final decision, update the body so future agents can read the current truth without replaying the comment thread.
- Remove obsolete body wording entirely instead of keeping it with strikethrough.
- Keep the decision history in comments, for example: "Decision: removed X because Y; issue body updated."
- Use strikethrough only as a temporary review markup while actively discussing an edit, not as the steady-state issue body.
- Before implementation, PR update, PR merge, or Linear closeout, re-read recent comments and reconcile any accepted decision back into the body.

## Pushback

Developer pushback should be specific and decision-oriented:

- "This acceptance criterion conflicts with the source doc."
- "This scope includes two user outcomes; recommend splitting into separate issues."
- "The current implementation path cannot verify this outcome without a product decision on X."
- "This appears to be implementation detail; recommend keeping Linear focused on outcome Y and tracking the code work in GitHub."

Do not rewrite the PM contract silently. Ask for or record the decision in Linear.

## Splitting Scope

Split a Linear issue when:

- it contains unrelated user outcomes
- one part is ready and another needs product discovery
- delivery requires independent acceptance paths
- different owners or projects should manage different parts

Keep the original issue as the parent or product umbrella when useful. Link children with parent, related, blocked-by, or blocks relationships.

## Decision Closeout

When a discussion resolves:

- update the issue body if the contract changed
- add a short decision comment if the thread needs a clear final state
- update labels, priority, status, cycle, project, or assignee if the decision changes routing
- create or update a GitHub engineering issue only when developer execution needs it
- mark PRD sync as done or create an explicit follow-up when the decision should become durable product docs

# Guided Adoption

Use this reference when the skill first enters a repository or when existing state-testing setup may be incomplete. Discover facts first, guide user-owned decisions one at a time, and install only the permanent setup required by the selected user outcome.

## Contents

- [Classify adoption state](#classify-adoption-state)
- [Discover repository facts](#discover-repository-facts)
- [Build the feature shortlist](#build-the-feature-shortlist)
- [Run the guided interview](#run-the-guided-interview)
- [Install authorized setup](#install-authorized-setup)
- [Conclude with one recommendation](#conclude-with-one-recommendation)

## Classify Adoption State

Classify the repository from evidence rather than a marker file.

### Unadopted

Treat a repository as unadopted when it lacks most of these:

- governing guidance that routes meaningful SwiftUI work through State Seams;
- a canonical local-only runner and explicit gate;
- an ignored Scratch test convention;
- a known headless test target or harness; and
- recognizable Feature or Application State Seam boundaries.

Run the complete discovery, shortlist, and guided interview.

### Partially Adopted

Treat a repository as partially adopted when some infrastructure or guidance exists but required pieces are missing, contradictory, or unused. Report the concrete gaps and ask only decisions affected by them. Do not repeat a full onboarding interview.

### Adopted

Treat a repository as adopted when the governing guidance, local runner/gate, ignored Scratch convention, test harness, and State Seam vocabulary are usable. Route directly to Develop, Verify, or Review. Re-run adoption only when the user asks or a material architecture change invalidates the setup.

## Discover Repository Facts

Inspect these before asking the user:

- governing `AGENTS.md` files and included rules;
- app, scene, tab, split-view, and composition roots;
- `@Environment(Model.self)`, `@EnvironmentObject`, and separately declared observable models;
- source roots, modules, packages, schemes, test targets, and canonical commands;
- CI configuration and local-only gates;
- `.gitignore` and existing Scratch conventions;
- production clients, repositories, databases, files, authentication, and authoritative systems visible in code or configuration;
- complete user outcomes and existing test coverage; and
- generated-file headers on every candidate setup file.

Do not ask the user for a test command, source root, or model location before searching the repository. Do not edit a file with a generated header; locate its source or report the setup gap.

## Build the Feature Shortlist

Rank 3-7 complete user outcomes, not Views or filenames. Prefer candidates with expensive or error-prone behavior:

- external or async operations;
- meaningful phases, failure, retry, cancellation, or recovery;
- backend, database, file, cache, authentication, or synchronization boundaries;
- cross-feature or Application State Seam coordination;
- restoration or platform reconciliation with product consequences;
- non-obvious invariants; or
- known regressions.

For each candidate include:

| Field | Content |
| --- | --- |
| Outcome | The complete user result |
| State Seam | Feature, Application, or composed |
| Risk-bearing behavior | The expensive or error-prone path |
| Failure hypothesis | The plausible defect verification would catch |
| Verification | State Test, focused composition State Test, Product E2E, or none |
| Required setup | Existing harness or exact missing infrastructure |
| Residual UI scope | Rendered/platform behavior not covered headlessly |
| Priority | Start here, next, later, or omit, with a reason |

Include a compact `Not recommended for testing` section for presentation-only surfaces and direct assignments. Do not turn omissions into coverage findings.

Example:

| Outcome | Seam | Risk | Verification | Priority |
| --- | --- | --- | --- | --- |
| Complete checkout and open receipt | Composed | Payment API, retry, persistence, returned-ID routing | State Tests plus Product E2E when production wiring remains unproved | Start here |
| Restore a signed-in session | Application | Token refresh, local credential state, root gating | State Tests; Product E2E only for unresolved production composition | Next |
| Open settings | Application | Direct route assignment only | None | Omit |
| Render profile header | Presentation | Visual only | External UI handoff when needed | Exempt |

End the shortlist with one recommended first vertical slice and explain what permanent setup it validates.

## Run the Guided Interview

Ask decision questions one at a time and wait for each answer. Give a recommended answer and explain the consequences of alternatives. Inspect facts instead of asking for them. Do not mutate the repository until the user confirms shared understanding and authorizes the selected setup.

When the user explicitly invokes `grill-me` or asks to be grilled, use that skill for the interview if available. Keep this adoption flow self-contained when it is not installed; do not add it as a dependency.

Resolve only decisions that apply:

1. Which ranked user outcome should be the first slice?
2. What is the whole-product acceptance claim and authoritative result?
3. Which production systems and non-production credentials may the local workflow use?
4. Does the outcome require a Feature, Application, or composed State Seam?
5. Should an existing boundary be minimally adapted or intentionally redesigned?
6. Which State Tests have concrete failure hypotheses?
7. Does critical impact plus uncovered production-composition risk justify Product E2E?
8. What residual SwiftUI or runtime behavior remains outside the headless claim?
9. Is the user authorizing the selected permanent setup and implementation?

The user owns these decisions. The agent owns discovery of repository facts and must recommend an answer for each decision.

Keep the shortlist and interview conversational. Do not create a repository report or issues for every candidate. When durable tracking is appropriate, record only the selected execution contract in the repository's existing issue workflow.

## Install Authorized Setup

After authorization, adapt the smallest missing permanent setup:

1. Update the narrowest governing `AGENTS.md` for the Swift app or module.
2. Amend an existing state-testing rule instead of duplicating it.
3. Create a root `AGENTS.md` only when it correctly governs the whole repository; otherwise use the relevant module boundary.
4. Adapt `../assets/project-agent-rule.md.template` to name the project's exact runner, gate, Scratch location, seams, and residual UI handoff.
5. Add or reuse one headless test target and the smallest harness support.
6. Add or verify a narrow ignored Scratch directory.
7. Adapt `../assets/run-state-e2e.sh.template`; remove unused hooks.
8. Prove produced tests cannot run in CI.
9. Exercise the setup on the selected vertical slice instead of declaring infrastructure success in isolation.

Never edit generated guidance. Change its generator or report the blocker. Do not install every optional hook before the selected outcome requires it.

## Conclude with One Recommendation

Finish onboarding with one concrete next action, then compact alternatives:

```text
Recommended next: adopt checkout as the first slice because it validates
payment failure/retry, backend persistence, and application-level receipt
routing. I will add only the guidance and harness pieces this outcome needs.

Available actions:
- Start the recommended feature.
- Choose another ranked feature.
- Install shared infrastructure only.
- Stop after the audit.
```

Explain that infrastructure-only setup provides no behavioral evidence until a real outcome exercises it. Do not finish with an unranked option list or an open-ended question without a recommendation.

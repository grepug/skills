---
name: develop-swiftui-with-state-testing
description: Integrate state-driven verification into SwiftUI development by auditing feature and app-wide observable models, establishing SwiftUI-free Feature and Application State Seams, guiding first-use adoption and minimal refactors, generating valuable local-only State Tests and retained Git-ignored whole-product E2E scenarios, and reviewing semantic behavior without mounting Views. Use for meaningful SwiftUI feature work, global navigation or presentation models, architecture audits, refactors, bug fixes, test planning, local end-to-end verification, onboarding, and code review. Exempt purely visual Presentation Components and trivial state assignments.
---

# Develop SwiftUI with State Testing

Replace screenshot-heavy verification of product behavior with semantic state assertions. Keep SwiftUI responsible for rendering and platform translation; drive the same production state interfaces from local tests without mounting the app.

## Preserve the Core Contract

Use **State Seam** as the shared contract with two scopes:

- a **Feature State Seam** owns one feature's state, effects, recovery, and internal destinations;
- an **Application State Seam** owns cross-feature navigation, global presentation, root/session gating, deep links, restoration, and other app-wide product coordination.

Require each non-visual product scope to expose a State Seam that:

- can be instantiated outside SwiftUI;
- exposes observable semantic state;
- accepts public user intents;
- receives production dependencies outside `View.body`;
- owns product branching, effects, failure, recovery, and destinations; and
- is shared by the SwiftUI runtime and tests; and
- exposes no SwiftUI types in its public testing interface.

Prefer `@MainActor @Observable` plus initializer injection for new examples. Production SwiftUI may obtain an Application State Seam with `@Environment(Model.self)`; tests instantiate that model directly. Accept an existing observable model or reducer/store when it satisfies the same contract. Do not impose a framework.

Keep feature models independent of the application model. Let features emit semantic outcomes; let the Application State Seam decide cross-feature routes and presentation. It may own child feature models when it owns their lifetime. Let SwiftUI bindings forward platform-driven changes through semantic reconciliation intents when those changes affect product behavior.

Exempt **Presentation Components** that render plain values or bindings, emit callbacks, and own only visual interaction state. Require a seam when a View owns product behavior or effects, even when no backend exists.

Read [pattern-and-refactoring.md](references/pattern-and-refactoring.md) before judging compliance or changing feature structure.

## Select Valuable Verification

Do not generate a test merely because a model is observable or an intent changes state. Before writing a State Test, state a concrete failure hypothesis: `This test would fail if ...`. Omit the test when it would only restate a direct assignment or obvious route mutation.

Require at least one risk-bearing surface such as async or external work, meaningful multi-phase behavior, failure or recovery, cancellation, stale results, persistence, reconciliation, cross-seam coordination, a non-obvious invariant, or a known regression.

Use a Scratch Product E2E only when both are true:

- failure would materially damage a critical user outcome; and
- an uncovered production-composition risk cannot be proved faithfully with controlled State Tests.

Treat Product E2E as whole-product verification entered through the narrowest production State Seam. It may expose defects in client composition, serialization, authentication, backend behavior, local databases, files, caches, or synchronization. Do not label ownership until evidence identifies the failing boundary.

## Route the Task

### Adopt

Use this route when introducing the workflow to a repository.

1. Read repository guidance, build/test commands, package boundaries, and CI configuration.
2. Read [adoption-guide.md](references/adoption-guide.md) and classify the repository as unadopted, partially adopted, or adopted.
3. Run `scripts/find-state-seam-candidates.sh <swift-source-roots...>` to produce a review inventory.
4. Classify each candidate as Presentation Component, Feature Container, Feature Model, Application Container, Application Model, or platform adapter. Never treat scanner output as a verdict.
5. Inventory complete user outcomes and rank 3-7 valuable starting candidates; explicitly omit trivial and presentation-only cases.
6. Ask user-owned decisions one at a time with a recommendation. Inspect repository facts instead of asking for them. When the user explicitly invokes `grill-me`, use it for this interview; do not require it to be installed.
7. Do not mutate the repository until the user confirms the selected outcome and setup.
8. When mutation is authorized, adapt the narrowest governing non-generated `AGENTS.md`, then add only the missing permanent harness, ignored Scratch directory, local gate, and project-owned runner.
9. Keep all produced tests behind an explicit local gate. They may compile in CI but must never execute there.

### Develop

Use this route during meaningful feature implementation or refactoring.

1. State the user outcome and minimum stable semantic assertions before editing code.
2. Classify touched Views. Do not force the pattern onto pure Presentation Components.
3. Inspect whether product state, effects, errors, recovery, and destinations cross the appropriate Feature or Application State Seam.
4. For an audit-only request, report findings without editing.
5. For an authorized change, perform the smallest refactor that lets SwiftUI and tests drive the same public intents without adding SwiftUI to the test interface.
6. Keep the Container translation-only: forward SwiftUI lifecycle/events to intents and map semantic state to presentation.
7. State the failure hypothesis, apply the value gate, and choose the required verification layer from [testing-workflow.md](references/testing-workflow.md).

### Verify

Use this route to prove a current workflow without mounting SwiftUI.

1. Select one complete user outcome and one exact test filter.
2. Use a fast local State Test only for qualifying risk-bearing behavior; support feature, application, and focused composition scopes.
3. When a critical workflow has uncovered production-composition risk, create one Scratch Product E2E using production adapters and the real authoritative system.
4. Put generated scenario source under the repository's ignored scratch directory in a real test target.
5. Run only through the canonical local runner described in [runner-contract.md](references/runner-contract.md).
6. Apply an operation deadline to every async acceptance step and a hard scenario watchdog in the runner.
7. Perform the whole-product fidelity audit in [testing-workflow.md](references/testing-workflow.md). Never label controlled-adapter success as Product E2E.
8. Record semantic state, durable evidence, fidelity path, command, Run Identity, timeout result, and cleanup result.
9. Verify every Scratch source path is ignored, untracked, and unstaged. Treat any violation as blocking; retain the source while fixing ignore or staging state.
10. Keep Scratch source in the current worktree. Report its path, file count, last validated commit, and how the user can remove it later.
11. Apply the promotion gate; uncommitted Scratch source remains the default.

### Review

Use this route for code review or delivery review.

1. Look for product logic in `body`, lifecycle modifiers, button closures, bindings, private `@State`, and convenience components.
2. Inspect separately declared `@MainActor @Observable` environment models for Application State Seam responsibilities and god-model coupling.
3. Reject helpers that swallow product errors, own semantic loading state, navigate directly, or hide outcomes in private View state.
4. Reject tautological tests without a credible failure hypothesis.
5. Check that assertions cover stable product meaning rather than complete model snapshots or incidental implementation state.
6. Check that every Product E2E claim uses production adapters, reaches its declared authoritative system, and proves a composition risk not covered below.
7. Check that produced test source imports no SwiftUI and cannot execute in CI.
8. Require explicit residual UI handoff instead of treating screenshots as semantic evidence.

## Select Verification Deliberately

Use these defaults:

| Change | State Test | Product E2E | External UI handoff |
| --- | --- | --- | --- |
| Pure style, layout, copy, animation | No | No | When visual/runtime confidence is needed |
| Risk-bearing feature state, failure, recovery | Yes | When critical composition risk remains | Residual wiring only |
| App navigation, presentation, restoration | When branching, reconciliation, or cross-seam risk exists | When critical composition risk remains | Minimal runtime wiring |
| Direct state or route assignment | No | No | Usually none |
| Persistence, files, cache, remote system | Deterministic risk-bearing branches | When critical composition risk remains | Usually none |
| Async, streaming, cancellation | Yes | When composition risk matters | Runtime-only remainder |
| Bug fix | Lowest faithful regression | Scratch reproduction when composition-dependent | Only for UI-only defects |

Do not run a real system merely because one exists. Reach the product's real authoritative implementation when it is part of the acceptance claim. A client-only product can complete Product E2E through production in-client logic, files, or persistence.

## Keep the Workflow Local and Uncommitted

- Never add produced tests to CI execution.
- Require an explicit local gate such as `STATE_TEST_WORKFLOW_ENABLED=1`.
- Keep generated State Tests and Product E2E scenarios Git-ignored, untracked, and unstaged. Do not delete them automatically after verification.
- Let the user remove Scratch source manually, commonly by deleting the worktree. Delete it as an agent only after explicit authorization in the current request.
- Keep committed only the project harness, runner, local gate, scratch convention, and selectively promoted regressions.
- Promote a scenario only when it protects a stable harmful recurrence, is deterministic and affordable, is the lowest faithful layer, and has clear ownership and diagnostics.
- Promote only with explicit user approval by rewriting or moving the scenario into the maintained test suite. Never force-add a file from the ignored Scratch directory.
- If a Scratch Product E2E finds a defect, prefer the smallest permanent local regression at the lowest faithful layer.

The rationale is recorded in [ADR 0001](docs/adr/0001-retained-scratch-verification.md).

## Report the Result

For an audit, report:

1. critical user workflows;
2. Presentation Component exemptions;
3. Feature and Application State Seam findings by blocking, important, or advisory priority;
4. the smallest ordered refactor sequence;
5. permanent harness gaps;
6. State Test candidates with failure hypotheses;
7. Scratch Product E2E candidates with uncovered composition risks; and
8. residual UI/runtime behavior outside scope.

For verification, post evidence to the existing issue or PR when available; otherwise include it in the final response. Do not create a permanent repository result document. Use the evidence template in [testing-workflow.md](references/testing-workflow.md).

Never import, mount, or automate SwiftUI in produced test source; never launch the product app or capture screenshots under this skill. A headless test process may use a simulator when the platform test runtime requires one. Statically audit Container wiring, then hand off the small residual rendered/runtime checks explicitly.

## Use the Bundled Resources

- Read [pattern-and-refactoring.md](references/pattern-and-refactoring.md) for classification, audit output, modern examples, convenience components, and refactoring steps.
- Read [testing-workflow.md](references/testing-workflow.md) for assertions, deadlines, local-only gating, fidelity, authentication bootstrap, evidence, and promotion.
- Read [adoption-guide.md](references/adoption-guide.md) for first-use detection, the guided interview, feature shortlists, and scoped project setup.
- Read [runner-contract.md](references/runner-contract.md) before creating or reviewing a project runner.
- Run `scripts/find-state-seam-candidates.sh` only as a candidate finder.
- Adapt `assets/run-state-e2e.sh.template` into a repository-owned runner; remove unused hooks.
- Adapt `assets/state-e2e-scenario.swift.template` into the ignored scratch test target, then retain it locally until the user authorizes deletion.
- Adapt `assets/project-agent-rule.md.template` into the repository's agent guidance so future feature work enters this workflow automatically.

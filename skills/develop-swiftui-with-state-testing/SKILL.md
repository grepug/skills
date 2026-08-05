---
name: develop-swiftui-with-state-testing
description: Integrate state-driven verification into SwiftUI development by auditing Views for product behavior, establishing observable Feature State Seams and public user intents, guiding or performing minimal refactors, generating local-only State Tests and disposable headless Product E2E scenarios, and reviewing changes that use screenshots for semantic behavior. Use for meaningful SwiftUI feature work, architecture audits, refactors, bug fixes, test planning, local end-to-end verification against client-side or external authoritative systems, and code review. Exempt purely visual Presentation Components.
---

# Develop SwiftUI with State Testing

Replace screenshot-heavy verification of product behavior with semantic state assertions. Keep SwiftUI responsible for rendering and platform translation; drive the same production feature interface from local tests without mounting the app.

## Preserve the Core Contract

Require every non-visual feature to expose a **Feature State Seam** that:

- can be instantiated outside SwiftUI;
- exposes observable semantic state;
- accepts public user intents;
- receives production dependencies outside `View.body`;
- owns product branching, effects, failure, recovery, and destinations; and
- is shared by the SwiftUI runtime and tests.

Prefer `@MainActor @Observable` plus initializer injection for new examples. Accept an existing observable model or reducer/store when it satisfies the same contract. Do not impose a framework.

Exempt **Presentation Components** that render plain values or bindings, emit callbacks, and own only visual interaction state. Require a seam when a View owns product behavior or effects, even when no backend exists.

Read [pattern-and-refactoring.md](references/pattern-and-refactoring.md) before judging compliance or changing feature structure.

## Route the Task

### Adopt

Use this route when introducing the workflow to a repository.

1. Read repository guidance, build/test commands, package boundaries, and CI configuration.
2. Run `scripts/find-state-seam-candidates.sh <swift-source-roots...>` to produce a review inventory.
3. Classify each candidate as Presentation Component, Feature Container, Feature Model, or platform adapter. Never treat scanner output as a verdict.
4. Inventory critical user workflows by complete user outcome, not screen or source file.
5. Report blocking, important, and advisory findings using the audit format in [pattern-and-refactoring.md](references/pattern-and-refactoring.md).
6. When mutation is authorized, add the smallest permanent harness, ignored scratch directory, project-owned runner, and project agent-routing rule.
7. Keep all produced tests behind an explicit local gate. They may compile in CI but must never execute there.

### Develop

Use this route during meaningful feature implementation or refactoring.

1. State the user outcome and minimum stable semantic assertions before editing code.
2. Classify touched Views. Do not force the pattern onto pure Presentation Components.
3. Inspect whether product state, effects, errors, recovery, and destinations cross the Feature State Seam.
4. For an audit-only request, report findings without editing.
5. For an authorized change, perform the smallest refactor that lets SwiftUI and tests drive the same public intents.
6. Keep the Container translation-only: forward SwiftUI lifecycle/events to intents and map semantic state to presentation.
7. Choose the required verification layer from [testing-workflow.md](references/testing-workflow.md).

### Verify

Use this route to prove a current workflow without mounting SwiftUI.

1. Select one complete user outcome and one exact test filter.
2. Use a fast local State Test for deterministic transitions and edge states.
3. For a critical workflow, create one disposable Product E2E happy path using production adapters and the real authoritative system.
4. Put generated scenario source under the repository's ignored scratch directory in a real test target.
5. Run only through the canonical local runner described in [runner-contract.md](references/runner-contract.md).
6. Apply an operation deadline to every async acceptance step and a hard scenario watchdog in the runner.
7. Perform the Product E2E fidelity audit in [testing-workflow.md](references/testing-workflow.md). Never label controlled-adapter success as Product E2E.
8. Record semantic state, durable evidence, fidelity path, command, Run Identity, timeout result, and cleanup result.
9. Delete the scratch scenario and verify that no scratch source is tracked or staged.
10. Apply the promotion gate; disposable remains the default.

### Review

Use this route for code review or delivery review.

1. Look for product logic in `body`, lifecycle modifiers, button closures, bindings, private `@State`, and convenience components.
2. Reject helpers that swallow product errors, own semantic loading state, navigate directly, or hide outcomes in private View state.
3. Check that assertions cover stable product meaning rather than complete model snapshots or incidental implementation state.
4. Check that every Product E2E claim uses production adapters and reaches its declared authoritative system.
5. Check that produced tests cannot execute in CI.
6. Require explicit residual UI handoff instead of treating screenshots as semantic evidence.

## Select Verification Deliberately

Use these defaults:

| Change | State Test | Product E2E | External UI handoff |
| --- | --- | --- | --- |
| Pure style, layout, copy, animation | No | No | When visual/runtime confidence is needed |
| Feature state, intent, failure, recovery | Yes | For an affected critical workflow | Residual wiring only |
| Navigation, sheet, alert decision | Yes | When part of a critical outcome | Minimal runtime wiring |
| Persistence, files, cache, remote system | Deterministic branches | Critical happy path | Usually none |
| Async, streaming, cancellation | Yes | When composition risk matters | Runtime-only remainder |
| Bug fix | Lowest faithful regression | Temporary reproduction when composition-dependent | Only for UI-only defects |

Do not run a real system merely because one exists. Reach the product's real authoritative implementation when it is part of the acceptance claim. A client-only product can complete Product E2E through production in-client logic, files, or persistence.

## Keep the Workflow Local and Disposable

- Never add produced tests to CI execution.
- Require an explicit local gate such as `STATE_TEST_WORKFLOW_ENABLED=1`.
- Keep generated State Tests and Product E2E scenarios Git-ignored and delete them after evidence is recorded.
- Keep permanent only the project harness, runner, local gate, scratch convention, and selectively promoted regressions.
- Promote a scenario only when it protects a stable harmful recurrence, is deterministic and affordable, is the lowest faithful layer, and has clear ownership and diagnostics.
- If a temporary Product E2E finds a defect, prefer the smallest permanent local regression at the lowest faithful layer.

The rationale is recorded in [ADR 0001](docs/adr/0001-local-disposable-state-verification.md).

## Report the Result

For an audit, report:

1. critical user workflows;
2. Presentation Component exemptions;
3. Feature Container findings by blocking, important, or advisory priority;
4. the smallest ordered refactor sequence;
5. permanent harness gaps;
6. disposable scenario candidates; and
7. residual UI/runtime behavior outside scope.

For verification, post evidence to the existing issue or PR when available; otherwise include it in the final response. Do not create a permanent repository result document. Use the evidence template in [testing-workflow.md](references/testing-workflow.md).

Never mount or automate SwiftUI, launch the product app, or capture screenshots under this skill. A headless test process may use a simulator when the platform test runtime requires one. Statically audit Container wiring, then hand off the small residual rendered/runtime checks explicitly.

## Use the Bundled Resources

- Read [pattern-and-refactoring.md](references/pattern-and-refactoring.md) for classification, audit output, modern examples, convenience components, and refactoring steps.
- Read [testing-workflow.md](references/testing-workflow.md) for assertions, deadlines, local-only gating, fidelity, authentication bootstrap, evidence, and promotion.
- Read [runner-contract.md](references/runner-contract.md) before creating or reviewing a project runner.
- Run `scripts/find-state-seam-candidates.sh` only as a candidate finder.
- Adapt `assets/run-state-e2e.sh.template` into a repository-owned runner; remove unused hooks.
- Adapt `assets/state-e2e-scenario.swift.template` into the ignored scratch test target, then delete it after the run.
- Adapt `assets/project-agent-rule.md.template` into the repository's agent guidance so future feature work enters this workflow automatically.

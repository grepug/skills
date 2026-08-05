# Testing Workflow

Use this reference to choose the local verification layer, write stable assertions, enforce deadlines, prove Product E2E fidelity, and record current evidence.

## Contents

- [Use two local layers](#use-two-local-layers)
- [Require a failure hypothesis](#require-a-failure-hypothesis)
- [Keep produced tests out of CI](#keep-produced-tests-out-of-ci)
- [Assert semantic outcomes](#assert-semantic-outcomes)
- [Bound every async operation](#bound-every-async-operation)
- [Audit Product E2E fidelity](#audit-product-e2e-fidelity)
- [Bootstrap authentication safely](#bootstrap-authentication-safely)
- [Retain Scratch scenarios without committing them](#retain-scratch-scenarios-without-committing-them)
- [Record verification evidence](#record-verification-evidence)
- [Hand off residual UI scope](#hand-off-residual-ui-scope)

## Use Two Local Layers

### State Test

Use a State Test for deterministic semantic behavior with controlled adapters when the behavior has a credible failure surface:

- async loading, failure, retry, cancellation, and recovery;
- branching on returned data, authentication, permissions, or persisted state;
- ordering, stale-result protection, and reconciliation logic;
- duplicate-action protection; and
- time-dependent behavior when a clock is deliberately controlled;
- persistence or other durable side effects;
- cross-feature/application composition; and
- non-obvious invariants or known regressions.

Use one State Test category with the narrowest useful scope:

- **Feature scope** drives one Feature State Seam.
- **Application scope** drives one Application State Seam.
- **Composition scope** passes real semantic outcomes between production feature and application models without mounting SwiftUI.

Do not label controlled-adapter success as proof that the product composition works.

### Product E2E

Use a Scratch Product E2E only when a workflow is critical and a plausible production-composition failure remains uncovered by controlled State Tests. Drive a complete user outcome through production adapters to its real authoritative system.

A critical workflow prevents or materially damages a user outcome when broken, such as:

- entering the usable product state;
- creating or changing primary user-owned data;
- completing the product's core value;
- reconciling purchase or entitlement state;
- performing destructive work; or
- recovering from interruption where integrity matters.

Organize Product E2E by user outcome, not screen. One workflow may cross several Models, persistence layers, or services.

Do not create Product E2E merely because a workflow is critical or calls an external API. State the composition failure hypothesis, such as a wrong production adapter, incompatible payload, authentication mismatch, persistence discrepancy, or premature completion. If a lower layer proves the risk faithfully, use that lower layer.

## Require a Failure Hypothesis

Before writing any State Test or Product E2E, complete this sentence:

```text
This test would fail if the product incorrectly ...
```

Reject hypotheses that only say a direct assignment used the wrong literal. Do not test an intent like `settingsTapped()` when its entire behavior is an obvious `routes.append(.settings)` with no branching, effect, reconciliation, invariant, or regression history.

For qualifying tests, select only evidence that proves the hypothesis:

- a controlled dependency receives the correct semantic input;
- an observable in-progress phase remains active while controlled work is suspended;
- success data determines the correct completion or route;
- failure preserves a no-navigation or no-persistence invariant;
- retry starts new work and can recover;
- cancellation or a stale completion cannot overwrite newer state;
- durable state agrees with semantic completion; or
- an Application State Seam routes from the actual feature outcome, session, deep link, or restored state.

Do not require a fixed assertion checklist. Record deliberately untested seams as headlessly driveable but not recommended for testing because they lack meaningful risk.

An Application State Test follows the same rule and contains no SwiftUI:

```swift
import Foundation
import Testing
@testable import MyApp

@Test @MainActor
func expiredSessionBlocksOrderDeepLink() async {
    let deepLinks = RecordingDeepLinkClient()
    let app = AppModel(
        deepLinks: deepLinks.client,
        session: .expired
    )
    let orderURL = URL(string: "myapp://orders/123")!

    await app.deepLinkReceived(orderURL)

    #expect(app.presentation == .signInRequired)
    #expect(app.routes.isEmpty)
    #expect(deepLinks.requestedURLs.isEmpty)
}
```

Its failure hypothesis is that an expired session might still query protected order data or navigate behind the authentication gate. By contrast, a test that only calls `settingsTapped()` and expects `.settings` has no comparable defect surface and should be omitted.

## Keep Produced Tests out of CI

Every test produced by this skill is local-only and headless.

- Require `STATE_TEST_WORKFLOW_ENABLED=1` or a project-equivalent explicit gate.
- Put generated State Tests and Product E2E source under the repository's ignored scratch directory by default.
- Require Scratch source to remain ignored, untracked, and unstaged. Treat a violation as blocking.
- Keep promoted local regressions behind the same gate.
- Never edit CI to execute these tests, the runner, or the candidate scanner.
- Audit CI commands to ensure the gate is absent.
- Allow committed harness/support code to compile in CI so it does not silently rot.
- Never import `SwiftUI` in produced test source or instantiate a View, `App`, `Scene`, environment container, `NavigationPath`, or another SwiftUI runtime type.

For Swift Testing:

```swift
import Foundation
import Testing

enum LocalStateWorkflow {
    static let isEnabled = ProcessInfo.processInfo.environment[
        "STATE_TEST_WORKFLOW_ENABLED"
    ] == "1"
}

@Suite(
    "Local state workflow",
    .enabled(if: LocalStateWorkflow.isEnabled)
)
struct LocalStateWorkflowTests {
    // Local-only tests.
}
```

For an existing XCTest target, skip in setup when the gate is absent. Do not create a second test framework migration merely for this workflow.

## Assert Semantic Outcomes

Assert the minimum stable product meaning required by the acceptance claim.

Prefer:

```swift
await model.saveTapped()

let noteID = try #require(model.phase.completedNoteID)
#expect(model.destination == .note(noteID))
#expect(try await runtime.notes.exists(id: noteID))
```

Avoid:

```swift
assertSnapshot(of: model)
#expect(model == expectedModelContainingEveryInternalField)
```

Classify observations:

- **Contract state**: user-visible phase, failure, recovery, completion, or destination. Assert it.
- **Evidence state**: a durable record, file, or authoritative read. Assert it when the workflow promises durability.
- **Incidental state**: task handles, cache representation, counters, timestamps, or implementation details. Do not assert it.

Assert a transient phase only when a user can observe or act on it. Do not assert exact generated copy, timestamps, identifiers, or provider output unless they are the contract.

Observation is synchronization machinery, not evidence by itself. A notification that a property changed does not justify a test and does not prove the intended effect, branch, durable result, or negative invariant.

## Bound Every Async Operation

Use an operation deadline for every awaited acceptance step and semantic state wait. Use a runner watchdog as the hard guarantee when code ignores cancellation or deadlocks.

Recommended profiles:

| Profile | Default | Use |
| --- | ---: | --- |
| `local` | 5 seconds | In-client logic, files, local persistence |
| `system` | 30 seconds | Local service, authentication, ordinary network work |
| `provider` | 180 seconds | Explicit real external provider work |
| Scenario watchdog | 5 minutes | One selected Product E2E scenario |

Allow project-level overrides beside runner configuration. Require a reason for a scenario-specific increase. Do not treat a larger timeout as the first fix for repeated failures.

Adapt and test this cooperative Swift helper in the project harness:

```swift
import Foundation

enum OperationDeadline {
    case local
    case system
    case provider

    var duration: Duration {
        switch self {
        case .local: .seconds(5)
        case .system: .seconds(30)
        case .provider: .seconds(180)
        }
    }
}

struct OperationTimedOut: Error, CustomStringConvertible {
    let operation: String
    let deadline: Duration
    let lastState: String

    var description: String {
        "Operation '\(operation)' exceeded \(deadline); last state: \(lastState)"
    }
}

func withOperationDeadline<Result: Sendable>(
    _ profile: OperationDeadline,
    operation name: String,
    lastState: @escaping @Sendable () async -> String = { "unavailable" },
    body: @escaping @Sendable () async throws -> Result
) async throws -> Result {
    try await withThrowingTaskGroup(of: Result.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: profile.duration)
            throw OperationTimedOut(
                operation: name,
                deadline: profile.duration,
                lastState: await lastState()
            )
        }

        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw CancellationError()
        }
        return result
    }
}
```

Structured concurrency waits for child tasks to unwind. This helper does not hard-stop a non-cooperative deadlock; the runner watchdog owns that guarantee.

For projects whose test deployment supports iOS 26, macOS 26, watchOS 26, tvOS 26, or visionOS 26, prefer [`Observation.Observations`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md) for bounded semantic waits on `@Observable` models. It emits an initial value and then transactional snapshots of properties read by its closure. Create it in the model's actor context; for a `@MainActor` model, create and iterate it from `@MainActor` test code.

```swift
import Observation
import Testing

@Test @MainActor
func paymentFailureDoesNotNavigate() async throws {
    let payment = SuspendedPaymentClient()
    let model = CheckoutModel(payment: payment)
    let phases = Observations { model.phase }

    let submitting = Task { @MainActor in
        for await phase in phases where phase == .submitting {
            return phase
        }
        return nil
    }

    let operation = Task { await model.submitTapped() }
    await payment.waitUntilRequested()

    #expect(
        try await withOperationDeadline(.local, operation: "observe submitting") {
            await submitting.value
        } == .submitting
    )

    payment.resume(throwing: PaymentError.declined)
    await operation.value

    #expect(model.phase == .failed(.paymentDeclined))
    #expect(model.destination == nil)
}
```

Use a controlled dependency to hold an important transient phase open; do not rely on task scheduling to catch it. `Observations` coalesces synchronous mutations into a consistent value at the next suspension and may omit intermediate values when production outpaces iteration. Do not use it to count setter calls or prove every incidental transition.

For earlier deployment targets, or long-lived streams that are not backed by the modern API, adapt a bounded semantic polling wait:

```swift
@MainActor
func awaitState(
    _ profile: OperationDeadline,
    operation name: String,
    describe: @escaping @MainActor @Sendable () -> String,
    condition: @escaping @MainActor @Sendable () -> Bool
) async throws {
    try await withOperationDeadline(
        profile,
        operation: name,
        lastState: { await MainActor.run { describe() } }
    ) {
        while !(await MainActor.run { condition() }) {
            try Task.checkCancellation()
            await Task.yield()
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
```

Prefer one-shot intents that return at meaningful completion:

```swift
await model.saveTapped()
```

Use either wait only when an intent cannot return at the semantic point being asserted. Never use a fixed sleep as completion evidence, recursively wrap the one-shot `withObservationTracking` callback as an ad hoc async stream, or expose internal `Task` values solely for tests.

## Audit Product E2E Fidelity

Before labeling a scenario Product E2E, prove all of these:

- It states the critical impact and uncovered production-composition failure hypothesis.
- It instantiates the narrowest production Feature or Application State Seam that contains the complete claim.
- It drives the same public intents used by SwiftUI.
- It selects production adapters rather than mocks, stubs, or in-memory substitutes, except for run-isolated identity and storage location.
- It uses the production serialization/client path when one exists.
- It reaches the declared authoritative system.
- It asserts a semantic State Seam outcome.
- It verifies a durable result when the user outcome promises one.
- It contains no test-only product behavior branch.
- It fails if the authoritative system is unavailable or violates its contract.

Record the path explicitly:

```text
NoteEditorModel.saveTapped()
→ LiveNotesRepository
→ production client
→ authoritative system
→ NoteEditorPhase.completed(noteID)
→ authoritative read confirms noteID
```

If any link uses a controlled adapter, call it a State Test and state the narrower claim.

Treat the State Seam as the entry point, not the ownership boundary of the result. A Product E2E may expose faults in the model, dependency selection, serialization, networking, authentication, backend behavior, local database, filesystem, cache, synchronization, or route composition. Record the last trustworthy state and the boundary where observed behavior diverged; assign a subsystem owner only when evidence supports it.

## Bootstrap Authentication Safely

Treat authentication as setup unless login itself is the acceptance claim. Permit a **Test Authentication Bootstrap** that supplies a temporary valid session without mounting interactive provider UI.

Accept:

- a short-lived token minted by a local development command;
- a non-production endpoint that creates a run-owned principal;
- an emulator identity;
- a temporary session fixture accepted only by local/test configuration; or
- a project-provided test account with per-run data isolation.

Require:

- production-environment rejection;
- short-lived credentials and no committed token values;
- no test branch in the shipped State Seam;
- Run Identity ownership and exact cleanup where possible; and
- evidence that interactive authentication was not covered.

If no bootstrap exists, recommend the smallest project-owned non-production adapter. Do not force provider UI automation into this workflow.

## Retain Scratch Scenarios Without Committing Them

Use this lifecycle for generated State Tests and Product E2E scenarios:

```text
derive current acceptance claim
→ inspect retained Scratch material without trusting it as current evidence
→ generate or update one ignored Scratch scenario
→ run one exact filter
→ record current evidence
→ clean run-owned product and client state
→ retain Scratch source in the worktree
→ report its path, count, last validated commit, and manual cleanup method
```

Do not create a worktree merely for this workflow. Use the current worktree's ignored Scratch directory. The user owns source deletion, commonly by deleting that worktree. An agent may delete Scratch source only when the user explicitly authorizes that deletion in the current request.

Before reporting success, verify every Scratch source path:

```bash
tracked_scratch="$(git ls-files -- "${scenario_path}")"
staged_scratch="$(git diff --cached --name-only -- "${scenario_path}")"

git check-ignore --quiet -- "${scenario_path}"
[[ -z "${tracked_scratch}" ]]
[[ -z "${staged_scratch}" ]]
```

Run the checks for each Scratch file or directory path; Git pathspec matching makes the tracked and staged checks include files below a directory. If any check fails, keep the source, remove it from staging if necessary, add or repair the narrow ignore rule when mutation is authorized, and report verification as blocked until all three conditions hold. Never use `git add -f` for Scratch source.

Treat retained Scratch scenarios as debugging material, not evergreen proof. Before reuse, compare the current acceptance claim, public intents, production adapters, authoritative system, and semantic assertions; update the scenario as needed and rerun it against the current commit.

Promote a scenario only when all are true:

- it protects a stable user-visible contract;
- recurrence is plausible and materially harmful;
- it is deterministic and affordable for local reuse;
- no lower layer detects the failure faithfully; and
- ownership and diagnostics are clear.

Promotion also requires explicit user approval. Rewrite or move the behavior into the maintained test suite and review it as committed test code; do not force-add the ignored Scratch file.

When a Scratch scenario finds a defect, first add the smallest local regression at the lowest faithful layer. Keep full Product E2E only for composition-dependent failures.

## Record Verification Evidence

Post evidence to the existing issue or PR when available. Otherwise return it in the final response. Do not create a permanent result document.

```markdown
### State-driven verification

Commit: `<sha>`
Workflow: `<complete user outcome>`
Scenario: `<exact suite/test>`
Run identity: `<run-id>`

State seam:
`<Feature or Application Model.publicIntent()>`

Production path:
`<State Seam → production adapters → backend/database/files/authentication → authoritative result>`

Failure hypothesis:
`<plausible defect this scenario detects>`

Assertions:
- `<semantic outcome>`
- `<durable evidence>`
- `<deadline/no-hang result>`

Command:
`<exact local runner command>`

Result: `PASS | FAIL | BLOCKED`
Runtime cleanup: `PASS | FAIL`

Not covered:
- `<residual rendered/platform behavior>`

Scratch sources: `<paths and file count>`
Scratch git state: `ignored, untracked, unstaged | BLOCKED`
Last validated commit: `<sha>`
Source cleanup: `retained; remove with worktree | retained; explicit paths for manual removal`
Promotion decision: `<decision and reason>`
```

Never include credentials, raw tokens, private responses, or full nondeterministic provider content.

## Hand off Residual UI Scope

Do not import, mount, or automate SwiftUI in produced test source or launch the product app under this skill. A headless test process may use a simulator when its platform runtime requires one. Statically inspect that Containers map controls, lifecycle, bindings, and destinations to the expected seam, then report residual risks:

```text
Headless verification passed.

Not covered by this skill:
- Save control is present and tappable.
- Destination renders the intended View.
- Keyboard focus advances correctly.

Recommended external verification:
- One manual rendered smoke through Save → Detail.
```

Do not use screenshots as substitute evidence for semantic state. Keep layout, styling, gestures, focus, accessibility runtime, scene lifecycle, entitlement hosting, and rendered wiring outside this skill.

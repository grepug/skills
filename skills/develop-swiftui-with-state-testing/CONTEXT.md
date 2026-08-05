# SwiftUI State-Driven Development

This context describes product verification through observable Swift state without mounting SwiftUI. It separates product behavior from rendered presentation so development can use fast semantic evidence while preserving a small explicit UI-runtime handoff.

## Language

**Presentation Component**:
A SwiftUI View that renders supplied values or bindings, emits callbacks, and owns only visual interaction state.
_Avoid_: Dumb view, pure screen

**Feature Container**:
A SwiftUI View that translates platform lifecycle and interaction into feature intents and maps semantic state into rendered presentation.
_Avoid_: Smart view, screen controller

**Application Container**:
A root or cross-feature SwiftUI View that translates environment, navigation, presentation, deep-link, restoration, and lifecycle mechanics into Application State Seam intents.
_Avoid_: Global View, app controller

**State Seam**:
The SwiftUI-free production interface through which runtime containers and tests drive semantic intents and observe product state at feature or application scope.
_Avoid_: View test hook, test model

**Feature State Seam**:
The State Seam for one feature's behavior, effects, recovery, and internal destinations.
_Avoid_: Screen ViewModel, local test hook

**Application State Seam**:
The State Seam for cross-feature navigation, global presentation, root/session gating, deep links, restoration, and app-wide product coordination. Production SwiftUI may obtain it through `@Environment(Model.self)`; tests construct it directly.
_Avoid_: Global singleton, navigation test hook

**User Intent**:
A product-level action named for what the user or system is trying to accomplish at the Feature State Seam.
_Avoid_: Event handler, state setter

**Semantic State**:
Observable product meaning such as loading, failure, recovery, completion, or destination, independent of visual rendering details.
_Avoid_: UI snapshot, internal state dump

**State Test**:
A local test with a concrete failure hypothesis that drives a Feature or Application State Seam with controlled dependencies to verify risk-bearing deterministic semantic behavior.
_Avoid_: Unit test, mock E2E

**Product E2E**:
A local headless whole-product scenario that enters through the narrowest production State Seam, traverses production adapters to the real authoritative system, and asserts semantic plus durable results for an uncovered composition risk.
_Avoid_: UI E2E, screenshot test, integration smoke

**Failure Hypothesis**:
The plausible product defect a test is designed to expose. Direct assignments without branching, effects, reconciliation, invariants, or regression risk do not qualify.
_Avoid_: Coverage goal, expected-value restatement

**Authoritative System**:
The production implementation that owns the workflow result, whether it is in-client state, persistence, files, a local service, or an external backend.
_Avoid_: Backend when no server is required

**Scratch Scenario**:
Git-ignored, untracked Product E2E source retained in the current worktree after verification until the user authorizes deletion.
_Avoid_: Temporary hack, disposable test, permanent smoke test

**Test Authentication Bootstrap**:
A non-production setup mechanism that supplies a temporary authenticated principal or session without claiming to verify interactive sign-in.
_Avoid_: Auth bypass, fake login test

**Verification Evidence**:
A commit-bound record of the acceptance claim, fidelity path, command, semantic outcome, durable result, deadlines, cleanup, and residual UI scope.
_Avoid_: Test report document, screenshot proof

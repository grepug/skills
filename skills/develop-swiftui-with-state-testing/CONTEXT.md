# SwiftUI State-Driven Development

This context describes product verification through observable Swift state without mounting SwiftUI. It separates product behavior from rendered presentation so development can use fast semantic evidence while preserving a small explicit UI-runtime handoff.

## Language

**Presentation Component**:
A SwiftUI View that renders supplied values or bindings, emits callbacks, and owns only visual interaction state.
_Avoid_: Dumb view, pure screen

**Feature Container**:
A SwiftUI View that translates platform lifecycle and interaction into feature intents and maps semantic state into rendered presentation.
_Avoid_: Smart view, screen controller

**Feature State Seam**:
The production interface through which SwiftUI and tests both drive user intents and observe semantic product state.
_Avoid_: View test hook, test model

**User Intent**:
A product-level action named for what the user or system is trying to accomplish at the Feature State Seam.
_Avoid_: Event handler, state setter

**Semantic State**:
Observable product meaning such as loading, failure, recovery, completion, or destination, independent of visual rendering details.
_Avoid_: UI snapshot, internal state dump

**State Test**:
A local test that drives the Feature State Seam with controlled dependencies to verify deterministic semantic behavior.
_Avoid_: Unit test, mock E2E

**Product E2E**:
A local headless scenario that drives a complete user outcome through production adapters to the real authoritative system and asserts semantic plus durable results.
_Avoid_: UI E2E, screenshot test, integration smoke

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

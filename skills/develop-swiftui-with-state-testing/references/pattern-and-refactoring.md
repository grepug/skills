# Pattern and Refactoring

Use this reference to classify SwiftUI code, audit the Feature State Seam, and design the smallest compliant refactor.

## Contents

- [Classify the surface](#classify-the-surface)
- [Audit the seam](#audit-the-seam)
- [Report findings](#report-findings)
- [Recognize a coupled View](#recognize-a-coupled-view)
- [Use the default Feature Model pattern](#use-the-default-feature-model-pattern)
- [Keep the Container translation-only](#keep-the-container-translation-only)
- [Make convenience components safe](#make-convenience-components-safe)
- [Refactor incrementally](#refactor-incrementally)

## Classify the Surface

Classify before recommending a Model. Do not infer responsibility from a filename alone.

### Presentation Component

Treat a View as a Presentation Component when it:

- renders supplied values or bindings;
- emits callbacks such as `onSelect`, `onSubmit`, or `onDismiss`;
- owns only animation, focus, hover, press, geometry, scroll, or other visual interaction state; and
- performs no product branching or effects.

Presentation Components are exempt from the Feature State Seam. Do not create a Model merely to move visual state out of a View.

### Feature Container

Treat a View as a Feature Container when it coordinates any of these:

- loading, saving, deletion, retry, cancellation, or recovery;
- authentication, persistence, files, device capabilities, or remote calls;
- validation that changes product behavior;
- semantic navigation, sheets, alerts, windows, or destinations;
- async workflow sequencing, streaming, or reconciliation; or
- conversion of framework lifecycle into product work.

A Feature Container must translate between SwiftUI and a Feature State Seam. It must not make product decisions itself.

### Feature Model

Treat an existing observable model or reducer/store as a compliant Feature Model when it:

- is production code and can be created without mounting SwiftUI;
- owns semantic state and product decisions;
- exposes user/system intents rather than state setters;
- accepts or resolves dependencies outside `View.body`;
- guards duplicate or invalid operations independently of controls; and
- is driven through the same interface by SwiftUI and tests.

### Platform Adapter

Treat code as a platform adapter when its behavior only exists in SwiftUI, UIKit, AppKit, or an entitlement/runtime host. Keep the adapter narrow. Move the product meaning on either side of it into the Feature State Seam and hand off the runtime verification explicitly.

## Audit the Seam

Run the candidate scanner first:

```bash
scripts/find-state-seam-candidates.sh Sources Packages/MyFeature/Sources
```

Then inspect every reported line semantically. The scanner intentionally reports valid visual state alongside possible violations.

For each Feature Container, answer:

1. What complete user outcome does this surface participate in?
2. Which state can the user observe or act on?
3. Which public intent corresponds to each meaningful interaction?
4. Where are product effects created and awaited?
5. Where are failures categorized and recovery made available?
6. Where are navigation and presentation destinations decided?
7. Can a normal test process instantiate the production interface?
8. Can it use production adapters and the real authoritative system?
9. What behavior still requires rendered/platform verification?

Flag common violations:

- clients, repositories, databases, or files used directly in a View;
- business branching inside `body`, `.task`, `.onChange`, or button closures;
- private View state named for loading, failure, completion, or product destinations;
- errors caught only to show a toast;
- multiple booleans that can express impossible workflow phases;
- async work that cannot be awaited or observed semantically;
- test-only product branches;
- tests that invoke a different interface than SwiftUI; and
- convenience components that swallow product outcomes.

## Report Findings

Do not issue a project-wide numeric score. Report a migration map:

| Surface | Classification | State seam | Product logic in View | E2E readiness | Recommendation |
| --- | --- | --- | --- | --- | --- |
| `ProfileHeader` | Presentation Component | Exempt | None | N/A | Keep |
| `CheckoutView` | Feature Container | Missing | Submit and destination | Blocked | Extract `CheckoutModel` |
| `OrdersView` | Feature Container | Partial | Error toast | Ready after fix | Move failure state |

Use these priorities:

- **Blocking**: a critical workflow cannot be driven without mounting SwiftUI.
- **Important**: the seam exists but hides failure, destination, persistence, or async completion.
- **Advisory**: a clarity or convenience improvement that does not block state verification.

Finish with the smallest ordered refactor sequence. Do not prescribe a repository-wide migration when one workflow can be made testable locally.

## Recognize a Coupled View

This View owns product state, production work, error presentation, and navigation:

```swift
struct NoteEditorView: View {
    @Environment(NotesClient.self) private var notes
    @State private var title = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var openedNoteID: Note.ID?

    var body: some View {
        Form {
            TextField("Title", text: $title)
            Button("Save") {
                Task {
                    isSaving = true
                    defer { isSaving = false }

                    do {
                        let note = try await notes.create(title)
                        openedNoteID = note.id
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .disabled(isSaving)
        }
    }
}
```

A headless test cannot prove this workflow without reproducing the View's implementation.

## Use the Default Feature Model Pattern

Use modern Observation and initializer injection as the canonical example. Adapt to an existing compliant architecture instead of replacing it.

```swift
import Foundation
import Observation

struct NoteDraft: Equatable, Sendable {
    var title = ""
}

struct Note: Equatable, Sendable {
    typealias ID = UUID
    let id: ID
    let title: String
}

struct NotesClient: Sendable {
    var create: @Sendable (NoteDraft) async throws -> Note
}

enum NoteEditorFailure: Equatable {
    case validation
    case authenticationRequired
    case temporarilyUnavailable
}

enum NoteEditorPhase: Equatable {
    case editing
    case saving
    case failed(NoteEditorFailure)
    case completed(Note.ID)
}

enum NoteEditorDestination: Equatable, Identifiable {
    case note(Note.ID)
    case discardConfirmation

    var id: String {
        switch self {
        case .note(let id): "note-\(id)"
        case .discardConfirmation: "discard-confirmation"
        }
    }
}

@MainActor
@Observable
final class NoteEditorModel {
    var draft = NoteDraft()
    private(set) var phase: NoteEditorPhase = .editing
    private(set) var destination: NoteEditorDestination?

    private let notes: NotesClient

    init(notes: NotesClient) {
        self.notes = notes
    }

    func saveTapped() async {
        guard phase != .saving else { return }
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .failed(.validation)
            return
        }

        phase = .saving
        do {
            let note = try await notes.create(draft)
            phase = .completed(note.id)
            destination = .note(note.id)
        } catch {
            phase = .failed(mapFailure(error))
        }
    }

    func retryTapped() async {
        guard case .failed = phase else { return }
        await saveTapped()
    }

    func destinationDismissed() {
        destination = nil
    }

    private func mapFailure(_ error: Error) -> NoteEditorFailure {
        // Map implementation errors to stable product meaning and log the raw cause.
        .temporarilyUnavailable
    }
}
```

Use an enum for mutually exclusive phases and a typed optional destination. Keep independent form inputs and selections as separate properties. Do not require one monolithic State value.

Expose stable semantic failures and recovery. Keep raw errors for diagnostics; do not require tests to compare arbitrary `Error` values or exact localized copy.

## Keep the Container Translation-Only

Split composition from pure rendering:

```swift
struct NoteEditorContainer: View {
    @State private var model: NoteEditorModel

    init(notes: NotesClient) {
        _model = State(initialValue: NoteEditorModel(notes: notes))
    }

    var body: some View {
        NoteEditorView(
            title: $model.draft.title,
            phase: model.phase,
            save: model.saveTapped,
            retry: model.retryTapped
        )
        .sheet(
            item: Binding(
                get: { model.destination },
                set: { destination in
                    if destination == nil {
                        model.destinationDismissed()
                    }
                }
            )
        ) { destination in
            destinationView(destination)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: NoteEditorDestination) -> some View {
        switch destination {
        case .note(let id): NoteDetailView(id: id)
        case .discardConfirmation: DiscardConfirmationView()
        }
    }
}

struct NoteEditorView: View {
    @Binding var title: String
    let phase: NoteEditorPhase
    let save: @MainActor () async -> Void
    let retry: @MainActor () async -> Void

    var body: some View {
        Form {
            TextField("Title", text: $title)
            AsyncIntentButton(
                isBusy: phase == .saving,
                action: save
            ) { isBusy in
                if isBusy { ProgressView() } else { Text("Save") }
            }
        }
    }
}
```

The Container may map semantic state into SwiftUI presentation. The Product E2E asserts `destination`; rendered presentation remains outside this skill.

## Make Convenience Components Safe

Provide helpers that bridge SwiftUI mechanics without owning product outcomes:

```swift
struct AsyncIntentButton<Label: View>: View {
    let isBusy: Bool
    let action: @MainActor () async -> Void
    @ViewBuilder let label: (_ isBusy: Bool) -> Label

    var body: some View {
        Button {
            guard !isBusy else { return }
            Task { await action() }
        } label: {
            label(isBusy)
        }
        .disabled(isBusy)
    }
}
```

Keep duplicate-intent protection in the Feature Model too. The component only prevents redundant UI interaction.

Reject convenience components that:

- catch and swallow product errors;
- make a toast the only failure state;
- own semantic loading or completion independently of the Model;
- navigate or present product destinations directly; or
- mutate repositories, sessions, or persistence.

## Refactor Incrementally

Use this sequence:

1. Name the complete user outcome and semantic assertions.
2. Mark visual-only state that remains in the View.
3. Extract product phase, failure, recovery, and destination into a production model.
4. Convert effectful closures into public user intents.
5. Move production dependency resolution to composition or model initialization.
6. Make one-shot intents `async` and meaningfully awaitable.
7. Keep long-lived observation behind explicit start/stop intents and observable state.
8. Turn the original View into a translation-only Container plus Presentation Components.
9. Add the smallest local State Test needed for deterministic branches.
10. Create one retained, Git-ignored Scratch Product E2E happy path when the workflow is critical.

Do not expose private implementation, add test-only product branches, or redesign unrelated features merely to satisfy the audit.

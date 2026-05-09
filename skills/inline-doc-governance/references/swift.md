# Swift Patterns

Use these patterns for `.swift` files.

## File Header

Keep the file header at the top before imports.

Good:

```swift
// NetworkRetryPolicy.swift
//
// Handles automatic retry logic for failed network requests.
// Uses exponential backoff with jitter to avoid thundering herd
// when the server comes back online after an outage.
//
// Used by: APIClient, BackgroundSyncManager
// See also: NetworkError.swift for error classification

import Foundation
```

Bad:

```swift
import Foundation
```

## Type Docs

Document public, open, package-visible, cross-boundary, or otherwise important types by default. Document every type only when the repo has adopted strict mode.

### Struct

```swift
/// App-facing result for one recognition request.
///
/// Keeps the transcript stable even when provider metadata is partial.
public struct VoiceRecognitionResult: Sendable, Equatable {
    public let transcript: String
    public let metadata: VoiceRecognitionMetadata
}
```

### Enum

```swift
/// UI states for the audit screen.
///
/// Keeps rendering decisions explicit instead of scattering booleans across the view.
public enum AuditViewState {
    case idle
    case loading
    case failed(String)
}
```

### Class

Put the doc above attributes.

```swift
/// Coordinates one long-lived chat session in the app layer.
///
/// Keeps navigation, transcript loading, and composer state together so views
/// do not need to understand session bootstrap rules.
@MainActor
public final class ChatSessionCoordinator {
}
```

### Protocol

```swift
/// Stable app-owned seam for voice recognition.
///
/// Product surfaces depend on this protocol instead of talking to GraphQL mutations directly.
public protocol VoiceRecognitionStore: Sendable {
    /// Runs voice recognition for one previously uploaded file.
    ///
    /// - Parameter fileID: The stored file identifier the app should send through
    ///   the voice-recognition workflow.
    /// - Returns: A normalized recognition result containing the transcript and
    ///   any optional provider metadata the backend returned.
    func recognize(fileID: UUID) async throws -> VoiceRecognitionResult
}
```

### Extension

```swift
/// Dependency wiring for the app-owned voice recognition store.
///
/// Centralizes the dependency key so callers read and override one stable value.
public extension DependencyValues {
    var voiceRecognitionStore: any VoiceRecognitionStore {
        get { self[VoiceRecognitionStoreKey.self] }
        set { self[VoiceRecognitionStoreKey.self] = newValue }
    }
}
```

### Type Alias

```swift
/// Shared closure shape for retry decisions.
///
/// Keeps retry call sites readable once the closure grows beyond a simple inline block.
public typealias RetryDecision = (_ attempt: Int, _ error: Error) -> Bool
```

## Initializers And Methods

Document public and important surface APIs with Swift doc comments.

```swift
/// Creates the app-facing result for one recognition request.
///
/// - Parameters:
///   - transcript: The recognized speech text returned by the backend.
///   - metadata: Optional provider metadata associated with the transcript.
public init(transcript: String, metadata: VoiceRecognitionMetadata) {
    self.transcript = transcript
    self.metadata = metadata
}
```

```swift
/// Loads the bundled sample and uploads it through the real app flow.
///
/// - Returns: The uploaded file handle the catalog should later pass into recognition.
/// - Throws: A user-visible error when the fixture cannot be loaded or uploaded.
public func uploadFixture() async throws -> UploadedFileHandle {
}
```

## Inline Body Comments

Good:

```swift
// Force unwrap is safe here because the storyboard guarantees the outlet.
// Crashing early is better than letting the controller limp into a broken state.
let tableView = tableView!
```

Good:

```swift
// Process the oldest pending item first. Newer items are more likely to be
// edited again, so this ordering avoids wasted work during bursts of changes.
queue.sort { $0.createdAt < $1.createdAt }
```

Bad:

```swift
// Set the value to nil.
currentUser = nil
```

## Practical Rules

- Put docs above attributes like `@MainActor`, `@Observable`, or `@Dependency`.
- Use `///` for type, method, and initializer docs unless a block comment is materially clearer.
- Document why optional fields are optional when the reason comes from an upstream provider or cross-layer boundary.
- Use inline comments only when the reader needs the decision, constraint, or safety reason.

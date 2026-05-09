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
/// App-facing result for one cache read.
///
/// Keeps the payload stable even when the backing store has partial metadata.
public struct CacheReadResult: Sendable, Equatable {
    public let payload: Data
    public let metadata: CacheMetadata
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
/// Coordinates one long-lived editor session in the app layer.
///
/// Keeps navigation, document loading, and draft state together so views
/// do not need to understand session bootstrap rules.
@MainActor
public final class EditorSessionCoordinator {
}
```

### Protocol

```swift
/// Stable app-owned seam for cached documents.
///
/// Product surfaces depend on this protocol instead of talking to persistence directly.
public protocol DocumentCache: Sendable {
    /// Loads one document from the local cache.
    ///
    /// - Parameter documentID: The stored document identifier the app should read.
    /// - Returns: A normalized cache result containing the payload and any optional metadata.
    func load(documentID: UUID) async throws -> CacheReadResult
}
```

### Extension

```swift
/// Dependency wiring for the app-owned document cache.
///
/// Centralizes the dependency key so callers read and override one stable value.
public struct DocumentCacheContainer {
    public var cache: any DocumentCache

    public init(cache: any DocumentCache) {
        self.cache = cache
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
/// Creates the app-facing result for one cache read.
///
/// - Parameters:
///   - payload: The cached bytes returned by the backing store.
///   - metadata: Optional storage metadata associated with the payload.
public init(payload: Data, metadata: CacheMetadata) {
    self.payload = payload
    self.metadata = metadata
}
```

```swift
/// Loads the bundled sample and uploads it through the real app flow.
///
/// - Returns: The loaded fixture bytes the caller can pass into tests.
/// - Throws: A user-visible error when the fixture cannot be loaded.
public func loadFixture() async throws -> Data {
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

# TypeScript And JavaScript Patterns

Use these patterns for `.ts`, `.tsx`, `.js`, and `.jsx` files.

## File Header

Put a short header before imports.

Good:

```ts
// user-auth-context.ts
//
// Manages authentication state for the app shell and exposes login state,
// session data, and auth actions to child components.
//
// Why this file exists: auth is read from many places and changes rarely,
// so this context keeps the surface smaller than a global store.

import { createContext } from 'react';
```

Bad:

```ts
import { createContext } from 'react';
```

## Type Docs

Document exported, public, package-facing, or cross-boundary types by default. Document every type only when the repo has adopted strict mode.

### Interface

```ts
/**
 * Stable request shape for one documentation audit run.
 *
 * Keeps CLI parsing separate from the scan engine so the engine can be reused
 * from tests later without depending on process arguments.
 */
export interface AuditRequest {
  root: string;
  failOnWarnings: boolean;
}
```

### Type Alias

```ts
/**
 * Union of issues the audit can report without reading code semantics.
 *
 * These are deterministic failures the script can prove from syntax alone.
 */
export type AuditIssue =
  | { kind: 'missing-file-header'; path: string }
  | { kind: 'missing-type-doc'; path: string; line: number; name: string };
```

### Enum

```ts
/**
 * Output modes supported by the audit command.
 *
 * Human mode is for local use. JSON mode exists so other tools can consume the result.
 */
export enum OutputFormat {
  Human = 'human',
  Json = 'json',
}
```

### Class

Put the doc above decorators.

```ts
/**
 * Queue-facing seam for backend callers.
 *
 * Callers enqueue work here instead of talking to the worker transport directly,
 * which keeps retry and routing details behind one module boundary.
 */
@Injectable()
export class JobQueueService {
  /**
   * Enqueues one job for asynchronous processing.
   *
   * @param input Job request with the queue name, payload, and optional delay.
   * @returns A stable job handle callers can use for status checks.
   */
  enqueue(input: EnqueueJobInput): Promise<QueuedJob> {
    return this.client.enqueue(input);
  }
}
```

## Function And Method Docs

Document the contract, not the implementation.

```ts
/**
 * Maps the worker result into the public API response shape.
 *
 * @param result Feature-layer job result with normalized status and optional output.
 * @returns A plain object that matches the API contract exposed to callers.
 */
export function toJobResponse(result: JobResult) {
  return {
    id: result.id,
    status: result.status,
    output: result.output,
    completedAt: result.completedAt,
  };
}
```

Good method docs explain:

- what the input means, not just its type
- what the return value means
- important failure modes or side effects

## Inline Body Comments

Use inline comments where the code hides a decision.

Good:

```ts
// The worker drops delayed jobs without a dedupe key, so fail before making
// a request the queue cannot safely retry.
if (input.delayMs > 0 && !input.dedupeKey) {
  throw new QueueRequestError('Delayed jobs require a dedupe key');
}
```

Good:

```ts
// HTTP/2 streams can emit timeout, error, and end in close succession.
// This guard keeps the public promise on one predictable completion path.
const finish = (callback: () => void) => {
  if (settled) return;
  settled = true;
  callback();
};
```

Bad:

```ts
// Set settled to true.
settled = true;
```

## Practical Rules

- Put docs above decorators, not between decorators and the declaration.
- If a type is so trivial the doc feels awkward, explain the role of the type in the module.
- If a file holds a cross-layer seam, the file header should say which layer owns it.
- If logic encodes a provider quirk, timeout rule, ordering rule, or retry rule, add a local why-comment.

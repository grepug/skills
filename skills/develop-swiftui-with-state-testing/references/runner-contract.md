# Runner Contract

Use this reference to create or audit the one canonical repo-owned command that executes local State Tests and retained Git-ignored Product E2E scenarios.

## Contents

- [Expose one command](#expose-one-command)
- [Keep the runner project-specific](#keep-the-runner-project-specific)
- [Follow the lifecycle](#follow-the-lifecycle)
- [Support client-only products](#support-client-only-products)
- [Support an external authoritative system](#support-an-external-authoritative-system)
- [Enforce safety](#enforce-safety)
- [Enforce the hard watchdog](#enforce-the-hard-watchdog)
- [Validate adoption](#validate-adoption)

## Expose One Command

Require one canonical local command. Follow repository naming conventions; a portable default is:

```bash
STATE_TEST_WORKFLOW_ENABLED=1 \
STATE_E2E_FILTER=CreateNoteStateE2E \
scripts/run-swiftui-state-e2e
```

Require one exact suite/test filter. Do not run every ignored or promoted local scenario implicitly.

The runner is permanent project infrastructure. Business scenarios remain ignored, uncommitted, and retained in the worktree until user-authorized deletion.

## Keep the Runner Project-Specific

Adapt `../assets/run-state-e2e.sh.template` into the target repository. Remove unused hooks instead of creating a generic configuration framework.

The skill owns the lifecycle contract. The adopting repository owns:

- the canonical Swift test command and target/scheme;
- authoritative-system startup and readiness;
- production environment rejection;
- Test Authentication Bootstrap;
- production dependency configuration;
- run-owned data cleanup; and
- repository-specific diagnostics.

Do not hide the executable runner in the installed skill. Reviewable behavior belongs with the project it affects.

## Follow the Lifecycle

Implement these steps in order:

1. Require an explicit local workflow gate.
2. Reject production configuration before creating data.
3. Validate tools and one safe test filter.
4. Generate a safe Run Identity.
5. Create a run-scoped private directory.
6. Start or reuse the authoritative system when needed.
7. Wait for readiness when needed.
8. Bootstrap temporary authentication when needed.
9. Write protected test configuration without exposing credentials in process arguments.
10. Execute one selected test process under a hard watchdog.
11. Preserve test output and failure status.
12. Clean exact run-owned product data and client files.
13. Stop only processes started by this run.
14. Report cleanup failure separately without hiding the original test failure.

Runner cleanup covers processes, credentials, run-owned product data, client files, and the run sandbox. It must never delete or mutate Scratch test source.

## Support Client-Only Products

For a product whose authoritative system is entirely in-client:

- omit system startup and readiness;
- use production in-client adapters;
- create run-scoped databases, files, defaults, or other storage;
- keep platform capabilities outside the scenario when they require app hosting; and
- keep the runner small.

A client-only runner may contain only preflight, sandbox creation, the test command, watchdog, and cleanup. Do not retain empty abstractions merely to resemble an external-system project.

## Support an External Authoritative System

When a real local or reachable system is part of the claim:

- discover and use the repository's canonical startup command;
- prefer reusing a developer-owned running system after a positive readiness check;
- record whether the runner started the system;
- capture the exact PID or project-owned stop handle;
- wait on a narrow health/readiness contract;
- fail when the system is unavailable instead of switching to a controlled adapter; and
- stop only what the runner started.

Real external-provider work is an explicit provider scenario. Use the provider deadline, avoid retries that hide a first failure, and assert product state or structure rather than exact generated content.

## Enforce Safety

Require all of these:

- `set -euo pipefail` and `umask 077`;
- an explicit gate such as `STATE_TEST_WORKFLOW_ENABLED=1`;
- fail-closed production-environment detection;
- a Run Identity restricted to letters, numbers, underscores, and hyphens;
- `mktemp -d` under a narrow known root;
- protected configuration files (`chmod 600`);
- no credentials in committed files or command arguments;
- exact principal/data cleanup keyed by Run Identity;
- validated paths before recursive removal;
- signal traps for ordinary interruption; and
- signal handlers that stop and reap the selected test process before cleaning external state; and
- failure when cleanup cannot prove ownership.

Do not use a home directory, repository root, unresolved variable, broad glob, or `/tmp` itself as a cleanup target.

## Enforce the Hard Watchdog

Use the runner watchdog to terminate the selected test process after the project deadline, normally five minutes.

The project test function should `exec` the real test process so the recorded PID belongs to the process that must be terminated. Send `TERM`, wait briefly, then send `KILL` only if it remains alive. Write a timeout marker so an exit caused by the watchdog reports status `124` rather than an unexplained signal.

The watchdog complements Swift operation deadlines. It is the final guard for ignored cancellation, deadlock, or a hung test runner.

External cleanup must remain possible after the test process is killed. Keep Run Identity and cleanup credentials in the runner process, not only inside Swift.

## Validate Adoption

Before declaring the runner ready:

1. Run `bash -n` on the generated script.
2. Prove it fails when the local gate is absent.
3. Prove it rejects a production-like environment.
4. Prove it rejects an empty or unsafe filter.
5. Run one client-only or real-system smoke scenario.
6. Force a scenario failure and confirm the original status is preserved.
7. Force a timeout and confirm status `124` plus diagnostic state.
8. Signal the runner and confirm the selected test process stops before cleanup.
9. Confirm client files and run-owned product data are removed.
10. Confirm a reused external system is not stopped.
11. Inspect CI configuration and confirm the gate cannot be activated.
12. Confirm successful, failed, timed-out, and signaled runs leave Scratch source unchanged.

Record any unavailable validation as a blocker. Do not substitute a screenshot or controlled-adapter pass for missing Product E2E evidence.

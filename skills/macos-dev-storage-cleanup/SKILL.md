---
name: macos-dev-storage-cleanup
description: Measure and safely clean reclaimable macOS developer storage, including Xcode, simulator, CoreDevice, rebuildable project artifacts, Docker or OrbStack, VS Code, app cache, WeChat media, and Time Machine local snapshots.
---

# macOS Developer Storage Cleanup

Use this skill when a user wants an agent to inspect, plan, or apply cleanup for reclaimable storage on a macOS development machine.

The default posture is read-first and plan-driven. Measure actual size before deleting, classify every cleanup item by risk, ask for explicit user authorization, and verify free space after cleanup.

## Prerequisites

- macOS for live cleanup.
- Python 3 for bundled scripts.
- `xcrun`, `tmutil`, `docker`, or `orb` only when those tools are present and relevant.
- User approval before any command that removes files, simulator devices, simulator runtimes, or Time Machine local snapshots.

## Safety Rules

- Never run a broad system cleaner or delete arbitrary user data.
- Never delete source directories wholesale.
- Never edit generated files or generated output; delete only selected rebuildable artifact directories when the user approves that cleanup item.
- Never delete WeChat `db_storage`, account databases, chat databases, or equivalent app-owned message stores.
- Never delete Time Machine local snapshots first. Clean selected files, then handle local snapshots only if the user explicitly selects that category.
- Do not use `sudo` for the main workflow.
- Use `/tmp` files for long cleanup plans passed to CLI commands.
- If a deletion fails, report the exact cleanup item and continue verifying the remaining selected cleanup items.

## Workflow

1. Discover the user goal and constraints:
   - requested categories, if any
   - whether Xcode archives should preserve the latest archive per project/platform
   - project roots that may contain rebuildable artifacts
   - custom archive roots
   - whether app-owned media/cache cleanup is in scope
2. Run a read-only scan:

   ```bash
   python3 skills/macos-dev-storage-cleanup/scripts/scan_macos_storage.py --format human
   ```

   For a reusable plan, write JSON to `/tmp`:

   ```bash
   python3 skills/macos-dev-storage-cleanup/scripts/scan_macos_storage.py --format json > /tmp/macos-storage-plan.json
   ```

3. Review the size-ordered output and classify cleanup items:
   - `regeneratable`: safe to recreate or re-download, such as build artifacts and caches
   - `review-required`: user-owned, app-owned, tool-owned, or high-regeneration-cost data that needs explicit selection
   - `leave-alone`: reported for awareness only
4. Present one concrete cleanup plan before deleting anything. Use consistent wording: call each selected target a `cleanup item`.
5. Apply only the selected categories or item IDs after the user authorizes deletion:

   ```bash
   python3 skills/macos-dev-storage-cleanup/scripts/apply_macos_storage_cleanup.py \
     --plan /tmp/macos-storage-plan.json \
     --category xcode-derived-data \
     --category developer-artifact \
     --apply
   ```

6. For long category or item selections, write the plan to `/tmp` and pass the path instead of embedding large JSON inline.
7. Verify final state:
   - rerun the scan for selected categories
   - check `df -h /`
   - list remaining local snapshots when Time Machine snapshots were discussed
   - report deleted bytes, skipped cleanup items, and follow-up cleanup items requiring human review

## Script Notes

Use `scan_macos_storage.py` for read-only discovery. It supports:

- `--format human|json`
- `--category <name>` repeated to narrow scanning
- `--min-size-mb <number>` for filesystem cleanup items
- `--home <path>` for test or alternate home roots
- `--artifact-root <path>` repeated for project artifact discovery
- `--archive-root <path>` repeated for custom archive discovery
- `--latest-xcode-version` and `--latest-simulator-version` as review hints

Use `apply_macos_storage_cleanup.py` for plan application. It defaults to dry-run. It requires:

- `--plan <json>` for the scan output
- `--apply` before deletion
- at least one `--category` or `--item` when `--apply` is present

The cleanup script refuses paths outside known cleanup categories unless `--allow-path <root>` is supplied. Use `--allow-path` only for user-approved custom roots.

## Target Reference

Read [cleanup-targets.md](references/cleanup-targets.md) when you need exact target categories, risk classification, and deletion behavior.

## Output

Report:

- cleanup items scanned, grouped by selected category
- reclaimable bytes selected for deletion
- cleanup items skipped and the reason
- exact log path under `/tmp`
- validation commands and final free-space evidence

## Bundled Files

- `scripts/scan_macos_storage.py` - read-only scanner that emits human or JSON cleanup reports.
- `scripts/apply_macos_storage_cleanup.py` - dry-run-first cleanup plan applier with explicit category and item gates.
- `scripts/test_macos_storage_cleanup.py` - fixture smoke tests for classification, selection, and guardrails.
- `references/cleanup-targets.md` - target categories, risk classes, and cleanup rules.

# Cleanup Targets

This reference defines the selected cleanup contract for `macos-dev-storage-cleanup`.

## Risk Classes

- `regenerateable`: data can be rebuilt, re-downloaded, or recreated by developer tools.
- `review-required`: data may be user-owned, app-owned, high-cost to recreate, or tied to active work.
- `leave-alone`: report-only data that this skill must not delete.

## Categories

| Category | Typical paths or source | Risk | Cleanup behavior |
| --- | --- | --- | --- |
| `xcode-derived-data` | `~/Library/Developer/Xcode/DerivedData` | `regenerateable` | Delete selected directories after explicit category or item selection. |
| `xcode-archives` | `~/Library/Developer/Xcode/Archives` | `review-required` | Report by date folder or archive. Delete only selected cleanup items. |
| `xcode-devicesupport` | `~/Library/Developer/Xcode/iOS DeviceSupport` | `review-required` | Delete selected old device support folders only when the user accepts redownload cost. |
| `xcode-cache` | `~/Library/Caches/com.apple.dt.Xcode` and related Xcode caches | `regenerateable` | Delete selected cache directories. |
| `xcode-application` | `/Applications/Xcode*.app`, Xcode installers, Xcode archives | `review-required` | Report only by default; do not remove installed Xcode apps without direct user instruction. |
| `simulator-device` | CoreSimulator devices from `xcrun simctl` or `~/Library/Developer/CoreSimulator/Devices` | `review-required` | Prefer `xcrun simctl delete <udid>` when a UDID is known. |
| `simulator-runtime` | CoreSimulator runtime bundles from `xcrun simctl` or `~/Library/Developer/CoreSimulator/Profiles/Runtimes` | `review-required` | Prefer `xcrun simctl runtime delete <identifier>` when an identifier is known. |
| `coredevice-delta` | `~/Library/Developer/CoreDevice/AppInstallationBinaryDeltas` | `regenerateable` | Delete selected delta cache directories. |
| `developer-artifact` | `.build`, `node_modules`, `.next`, `.turbo`, `Pods`, `dist`, `build` under selected artifact roots | `regenerateable` | Delete selected artifact directories only, never the source root. |
| `custom-xcode-archive` | User-provided archive roots such as `~/Developer/xcode-build/*/archives` | `review-required` | Preserve the latest archive per parent folder unless `--delete-latest-archives` is supplied. |
| `docker-summary` | `docker system df` | `review-required` | Report only; Docker pruning requires a separate user-approved command. |
| `orbstack-summary` | OrbStack command output and storage roots | `review-required` | Report only; OrbStack pruning requires a separate user-approved command. |
| `vscode-storage` | VS Code `workspaceStorage` | `review-required` | Delete selected workspace storage only after the user understands settings/state impact. |
| `vscode-cache` | VS Code `Cache`, `CachedData`, `GPUCache`, `logs` | `regenerateable` | Delete selected cache directories. |
| `common-cache` | common developer caches under `~/Library/Caches` | `regenerateable` | Delete selected cache directories. |
| `wechat-media` | WeChat media folders such as `Message/MessageTemp`, `File`, `Image`, `Video` | `review-required` | Report and delete only selected media/cache paths. |
| `wechat-cache` | WeChat cache folders under container caches | `regenerateable` | Delete selected cache directories. |
| `wechat-database` | WeChat `db_storage`, account databases, message databases | `leave-alone` | Report only. Never delete in this skill. |
| `time-machine-snapshot` | `tmutil listlocalsnapshots /` | `review-required` | Delete only selected local snapshots after cleanup, never as the first default action. |

## Cleanup Plan Rules

- Every cleanup item should have a stable item ID, category, path or command target, size when available, risk class, default eligibility, and skip reason when not eligible.
- JSON scan output is the cleanup plan input for the apply script.
- Deletion requires both `--apply` and explicit `--category` or `--item` selection.
- App-owned databases and report-only summaries stay ineligible even when selected.
- Unknown paths require `--allow-path <root>` and explicit selection.
- Time Machine local snapshots should be considered only after file cleanup, because snapshots can keep deleted blocks allocated until the snapshot is removed.

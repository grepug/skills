---
name: xcode-archive-release
description: Bump version/build number, archive an Xcode project, upload to TestFlight, upload an internal test IPA through ipa-server, then tag and push TestFlight releases in git. Use when a user wants to release an iOS or macOS app to TestFlight/App Store Connect, publish an internal test IPA, upload to both destinations, reuse an existing archive or IPA, bump version and release, release from git tag, or retry a failed upload.
---

# Xcode Archive & Release

Release an Apple app by bumping version/build metadata, archiving with Xcode, exporting and uploading to TestFlight/App Store Connect, publishing an internal test IPA through ipa-server, then tagging successful TestFlight releases in git.

## Use when

- The user wants to archive and upload an iOS or macOS app to TestFlight/App Store Connect
- The user wants to upload an internal iOS `.ipa` to ipa-server
- The user wants one run to upload the same iOS build to both TestFlight and ipa-server
- The user wants to reuse an existing `.xcarchive` or `.ipa`
- The user wants to release from an explicit version/build or infer them from a git tag
- The user needs to retry an upload without rebuilding unless necessary

## Prerequisites

- macOS with Xcode and `xcodebuildmcp` CLI available for supported discovery/build operations
- Xcode command-line tools available for archive/exportArchive inside the release helper
- A signed Xcode project with a valid scheme
- Access to the correct Apple Developer team and App Store Connect account
- A clean understanding of the target project, scheme, platform list, version, and build number
- For existing artifact runs, a readable `.xcarchive` or `.ipa`; `--project` and `--scheme` are not required unless creating a release tag for the current git repo
- For `test-ipa` or `both`, the external `ipa-server-usage` skill helper and an ipa-server URL from `--ipa-server` or `IPA_SERVER_URL`

The main helper is `scripts/xcode-release.sh`. The default upload mode is `testflight`. The bundled `assets/ExportOptions-AppStore.plist` sets `method=app-store` and `destination=upload`, so the `testflight` flow uploads directly to App Store Connect without a separate upload step. After all requested TestFlight uploads succeed, the script creates the annotated git tag `v<version>-<build>` on the current `HEAD` and pushes that exact tag to the branch's upstream remote, or `origin` if no upstream remote is configured.

`test-ipa` and `both` use the external ipa-server helper:

```bash
python3 <ipa-server-helper> \
  --server <url> \
  upload \
  --ipa <ipa> \
  --project <project> \
  --version <version> \
  --build-number <build> \
  --bundle-id <bundle-id>
```

The helper path is resolved from `--ipa-server-helper`, then `IPA_SERVER_HELPER`, then the sibling skill path `skills/ipa-server-usage/scripts/ipa_server.py`.

## Confirm before acting

Before running the script, confirm:

- the Xcode project path
- the scheme name for new archive runs
- the version and build number, or that git tag inference is intended
- the target platform list: any ordered subset of `ios`, `macos`, and `mac_catalyst`
- the upload mode: `testflight`, `test-ipa`, or `both`
- for `test-ipa` or `both`, the ipa-server URL and helper path
- whether an existing `.xcarchive` or `.ipa` should be reused, and the `--project-name` if artifact metadata does not provide a clear app name
- whether the user wants a preflight-only validation run first

For mixed-target or higher-risk projects, prefer a dry run with `--preflight-only` before touching source files.

## Workflow

### 1. Discover project details

If the user hasn't specified `--project` or `--scheme`, find them:

```bash
# List .xcodeproj files near the current directory
find . -name "*.xcodeproj" -maxdepth 3

# List available schemes for a project
xcodebuildmcp project-discovery list-schemes --project-path MyApp.xcodeproj
```

### 2. Confirm before running

Present a dry-run summary to the user before executing:

```
Project : MyApp.xcodeproj
Scheme  : MyApp_iOS
Version : 2.1.0  Build: 42
Platform: ios (generic/platform=iOS)
Mode    : testflight
Archive : ~/.xcode-archive/MyApp/2.1.0-42/MyApp-ios.xcarchive
```

For complex or mixed-target projects (e.g. iOS + watchOS), run `--preflight-only` first to validate the scheme and export plist before any source files are touched:

```bash
xcode-release.sh --project MyApp.xcodeproj --scheme MyApp_iOS --version 2.1.0 --build 42 --preflight-only
```

Ask for confirmation, then proceed.

### 3. Run the script

Run the bundled script:

```bash
chmod +x path/to/skills/xcode-archive-release/scripts/xcode-release.sh

# Infer version + build from the git tag on HEAD (tag must contain both components):
path/to/skills/xcode-archive-release/scripts/xcode-release.sh \
  --project  MyApp/MyApp.xcodeproj \
  --scheme   MyApp_iOS \
  --platform ios,macos

# Or specify explicitly:
path/to/skills/xcode-archive-release/scripts/xcode-release.sh \
  --project  MyApp/MyApp.xcodeproj \
  --scheme   MyApp_iOS \
  --version  2.1.0 \
  --build    42 \
  [--platform ios|macos|mac_catalyst[,ios|macos|mac_catalyst...]] \
  [--upload-mode testflight|test-ipa|both] \
  [--test-ipa-export-method development|ad-hoc|enterprise] \
  [--test-ipa-export-plist /custom/ExportOptions-DirectInstall.plist] \
  [--ipa-server https://ipa.example.com] \
  [--ipa-server-helper path/to/ipa_server.py] \
  [--archive-path /path/to/App.xcarchive] \
  [--ipa-path /path/to/App.ipa] \
  [--project-name "Project Name"] \
  [--bundle-id com.example.app] \
  [--tag-existing-artifact] \
  [--export-plist /custom/ExportOptions.plist]  \  # override bundled plist
  [--preflight-only]           # validate setup without building or touching source
  [--force]                    # re-archive even if archive already exists
```

When multiple platforms are listed, the script builds them sequentially in the order provided. Version/build resolution happens once for the whole batch.

**Git tag format** — must contain exactly one semver component and one integer component, separated by `-`, `+`, `/`, or `_`. Leading `v` is stripped.

| Tag                | Version     | Build |
| ------------------ | ----------- | ----- |
| `v2.1.0-42`        | 2.1.0       | 42    |
| `2.1.0+42`         | 2.1.0       | 42    |
| `2.1.0/42`         | 2.1.0       | 42    |
| `v2.1.0`           | ✗ no build  | —     |
| `release-2.1.0-42` | ✗ ambiguous | —     |

If the tag is ambiguous or missing a component, the script errors with a message directing you to pass `--version` and `--build` explicitly.

### Upload modes

- `testflight` uploads to TestFlight/App Store Connect and tags after a successful automatic upload.
- `test-ipa` exports a direct-install iOS `.ipa`, uploads it to ipa-server, and does not create a git tag.
- `both` exports a direct-install iOS `.ipa`, uploads it to ipa-server, then uploads to TestFlight through the App Store Connect export path. The run is complete only after both uploads succeed, and tagging happens after both requested uploads complete.

`test-ipa` and `both` are iOS-only because ipa-server accepts `.ipa` artifacts. For ipa-server upload, provide `--ipa-server` or set `IPA_SERVER_URL`.

For ipa-server OTA installs, the IPA must be signed for direct installation, not App Store Connect/TestFlight distribution. The default test IPA export method is `development`; pass `--test-ipa-export-method ad-hoc` or `--test-ipa-export-method enterprise` when that better matches the intended device audience. If the project needs custom signing options, pass `--test-ipa-export-plist`; its `method` must be `development`, `ad-hoc`, or `enterprise`.

### Existing artifacts

Use `--archive-path /path/App.xcarchive` to reuse an existing archive for `testflight`, `test-ipa`, or `both`. Existing archive mode never bumps project files and never infers the next build from archive history. It does not require `--project` or `--scheme` unless `--tag-existing-artifact` is used. Metadata is read from the archive and can be overridden with `--project-name`, `--version`, `--build`, or `--bundle-id`. For `test-ipa`/`both`, the archive is exported with the direct-install test IPA method. `--archive-path` cannot be combined with `--ipa-path`; choose archive reuse when the helper still needs to export an IPA.

Use `--ipa-path /path/App.ipa` only with `--upload-mode test-ipa`. It does not require `--project` or `--scheme`. The script reads project name, version/build, and bundle ID from `Payload/*.app/Info.plist` when possible, accepts explicit overrides, and uploads the IPA without archiving or exporting. The caller is responsible for ensuring that an existing IPA is signed for direct OTA installation. `--ipa-path` cannot be combined with `--archive-path`, `--force`, `--test-ipa-export-method`, or `--test-ipa-export-plist`; upload an existing IPA only when no export step is needed.

Do not upload App Store Connect/TestFlight export IPAs to ipa-server. iOS OTA installs via `itms-services` need direct-install signing; use `--archive-path` so the script exports a `development` IPA by default, or provide an existing IPA that was exported with `development`, `ad-hoc`, or `enterprise` signing.

By default, `--archive-path` does not create a git tag because the archive may not correspond to the current `HEAD`. Add `--tag-existing-artifact --project /path/App.xcodeproj` only when the user explicitly wants to tag the current `HEAD` for that existing archive.

Existing artifact examples:

```bash
# Export an IPA from an archive and upload it to ipa-server.
xcode-release.sh \
  --upload-mode test-ipa \
  --archive-path /path/App.xcarchive \
  --test-ipa-export-method development \
  --ipa-server https://ipa.example.com

# Upload an already exported IPA; no Xcode project is needed.
xcode-release.sh \
  --upload-mode test-ipa \
  --ipa-path /path/App.ipa \
  --project-name "Project Name" \
  --ipa-server https://ipa.example.com
```

### 4. Create and push release tag

After successful `testflight` or `both` uploads, the script creates and pushes an annotated release tag:

- tag format: `v<version>-<build>`
- example: `v2.1.0-42`
- tag message: `Release 2.1.0 (42)`

The tag is created on the current `HEAD`. The script does **not** create a git commit for the version/build edits it made during the release. If those edits are still uncommitted, the tag still points at the pre-existing `HEAD` commit. `test-ipa` only runs do not tag.

If the tag already exists locally or on the remote, the script fails without moving or force-pushing the tag.

### 5. Report results

On success, the script prints the artifact path. Tell the user:

- Where artifacts are: `~/.xcode-archive/<project-name>/<version>-<build>/`
- To check App Store Connect → TestFlight or the Builds tab to confirm the upload processed
- For `test-ipa` or `both`, the ipa-server build id and OTA install URL printed by the helper
- Which git tag was created and which remote it was pushed to

The platform variant is `ios`, `macos`, or `mac_catalyst`. The script keeps the same version/build folder and makes the archive, export, DerivedData, and log names platform-specific.

If the archive succeeds but automatic export/upload hits a missing App Store provisioning profile for the app’s bundle ID, the script opens the `.xcarchive` in Xcode Organizer instead. In that case, tell the user the archive is ready and they should upload it to App Store Connect manually from Organizer.

## Output

Successful runs produce:

- a versioned archive folder at `~/.xcode-archive/<ProjectName>/<version>-<build>/`
- the `.xcarchive`
- exported artifacts under `export-<platform-variant>/`
- logs under `logs-<platform-variant>/`, including `archive.log`, `export.log`, `test-ipa-export.log`, or `test-ipa-upload.log` depending on mode
- a per-platform and per-mode completion marker used to skip already completed variants on rerun
- an annotated git tag `v<version>-<build>` pushed to the configured remote after automatic TestFlight upload succeeds for `testflight` or `both`

The user should verify the build appears in App Store Connect after processing finishes.

## Retry a Failed Upload

If one platform or upload destination in a batch fails (network issue, ASC outage, ipa-server outage, etc.):

1. If the original run already pinned version/build explicitly, or inferred them from a git tag, run the **exact same command** — already completed platforms are skipped, and incomplete platforms are retried in sequence.
2. If the original run inferred version/build from archive history, use the retry command printed on failure instead. That retry command pins the resolved `--version` and `--build`, so it retries the same release instead of advancing to the next build number.
3. Use `--force` only if you need to rebuild all listed platforms from scratch (e.g. wrong code was archived).

If upload succeeded but tag creation or tag push failed, do **not** re-run the full release command blindly. The binary may already be uploaded, and a retry can fail with duplicate upload or duplicate tag errors. Use the script's tag-specific failure message to decide whether to create or push the tag manually.

For `both`, treat ipa-server and TestFlight as separate upload destinations. If ipa-server upload succeeds but TestFlight fails, the retry skips the already completed ipa-server upload unless `--force` is used. If TestFlight succeeds but ipa-server fails, do not consider the run complete until ipa-server succeeds too.

## Output Folder Structure

```
~/.xcode-archive/<ProjectName>/
└── <version>-<build>/              e.g. 2.1.0-42/
    ├── MyApp-ios.xcarchive         iOS archive
    ├── MyApp-macos.xcarchive       macOS archive when present
    ├── MyApp-mac_catalyst.xcarchive Catalyst archive when present
    ├── DerivedData-ios/            isolated DerivedData per platform variant
    ├── DerivedData-macos/
    ├── DerivedData-mac_catalyst/
    ├── export-ios/                 export output
    │   ├── MyApp.ipa
    │   ├── ExportOptions.plist     copy of the options used
    │   └── UploadSessionLogs/      ASC upload diagnostic logs
    ├── export-macos/
    ├── export-mac_catalyst/
    ├── logs-ios/
    │   ├── archive.log             full archive output
    │   ├── export.log              full TestFlight export/upload output
    │   ├── test-ipa-export.log     IPA export output when using ipa-server
    │   └── test-ipa-upload.log     ipa-server helper output
    ├── logs-macos/
    ├── logs-mac_catalyst/
    ├── .completed-ios
    ├── .completed-ios-test-ipa
    ├── .completed-ios-both
    ├── .completed-macos
    └── .completed-mac_catalyst
```

Each run has its own versioned folder, and each platform variant gets its own artifact names inside that folder. That lets the same version/build coexist across platforms without overwriting the archive.

## Bundled files

- `scripts/xcode-release.sh` — main release workflow
- `assets/ExportOptions-AppStore.plist` — default App Store export settings

## Troubleshooting

| Symptom                                                               | Fix                                                                                                                                                            |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Code signing failed`                                                 | Open Xcode → project target → Signing & Capabilities, ensure a valid provisioning profile and team are set for Release                                         |
| `error: exportArchive No profiles for '<bundle-id>' were found`       | Treat this as an Organizer handoff: open the generated `.xcarchive` in Xcode Organizer and tell the user to upload it to App Store Connect manually            |
| `No schemes found`                                                    | Run `xcodebuildmcp project-discovery list-schemes --project-path MyApp.xcodeproj` to list valid scheme names; or use `--preflight-only` to check before running |
| `ERROR ITMS-90189: Duplicate binary upload`                           | The build number already exists in ASC. Increment `--build`                                                                                                    |
| `Duplicate platform in --platform list`                               | Remove repeated platform entries. Each batch should list each of `ios`, `macos`, and `mac_catalyst` at most once                                              |
| `--upload-mode test-ipa supports ios only`                            | Use `--platform ios`; ipa-server accepts `.ipa` artifacts only                                                                                                 |
| `Missing ipa-server URL`                                               | Pass `--ipa-server https://...` or set `IPA_SERVER_URL`                                                                                                        |
| `ipa-server helper not found`                                          | Install the `ipa-server-usage` skill, pass `--ipa-server-helper`, or set `IPA_SERVER_HELPER`                                                                   |
| `--ipa-path can only be used with --upload-mode test-ipa`              | Use an archive for TestFlight uploads, or switch the mode to `test-ipa`                                                                                        |
| `--archive-path and --ipa-path cannot be combined`                     | Use `--archive-path` when the helper should export from an archive, or `--ipa-path` when uploading an existing IPA directly                                    |
| `--test-ipa-export-method cannot be combined with --ipa-path`          | `--ipa-path` uploads an already exported IPA; re-export from `.xcarchive` when you need a different signing method                                             |
| `Test IPA ExportOptions.plist must use method development...`          | The test IPA export plist is using an App Store/TestFlight method; use `development`, `ad-hoc`, or `enterprise`                                               |
| `Could not resolve project name`                                       | Pass `--project-name`, pass `--project`, or use an archive/IPA with readable app name metadata                                                                |
| `--tag-existing-artifact requires --project`                           | Pass the Xcode project path only when intentionally tagging current `HEAD` for an existing archive                                                            |
| `Missing bundle id for ipa-server upload`                              | Pass `--bundle-id` or use an archive/IPA with readable Info.plist metadata                                                                                     |
| `Archive not found` on retry                                          | Check the path `~/.xcode-archive/<name>/<version>-<build>/<name>-<platform-variant>.xcarchive` exists; if not, re-run with the same `--platform` list used for the original archive |
| `PlistBuddy: Entry, ":CFBundleShortVersionString", Does Not Exist`    | Harmless — the Info.plist doesn't have that key (modern Xcode projects); the `project.pbxproj` patch handles it                                                |
| `No git tag on HEAD`                                                  | HEAD isn't tagged. Create a tag (`git tag v2.1.0-42 && git push --tags`) or pass `--version` and `--build` explicitly                                          |
| `Tag(s) on HEAD ... don't contain one semver + one integer component` | Tag is missing the build number (e.g. `v2.1.0`) or has an unrecognised part (e.g. `release-2.1.0-42`). Rename the tag or pass `--version`/`--build` explicitly |
| Script fails with `✗ FAILED at step: archive`                         | Check `~/.xcode-archive/<name>/<ver>-<build>/logs-<platform-variant>/archive.log` for the root cause; the failure block prints the last 20 lines automatically |
| `Release tag already exists locally`                                  | The current repo already has `v<version>-<build>`. Do not force-move it; use a new build number if this is a new release attempt                               |
| `Release tag already exists on remote`                                | The remote already has `v<version>-<build>`. Treat the tag as immutable; verify whether the release already happened before retrying                            |
| `✗ FAILED at step: tag` after upload succeeded                        | The app upload completed but tagging did not. Follow the printed recovery command to push the local tag, or resolve the duplicate-tag/git-remote issue manually |

## ExportOptions Customization

The bundled plist (`assets/ExportOptions-AppStore.plist`) works for standard App Store uploads. To customize (e.g. add `teamID`, `signingStyle`, or `iCloudContainerEnvironment`), copy it to the project folder and pass `--export-plist`. This plist is required only when the helper exports from a new or existing archive; `--ipa-path` uploads an already exported IPA and ignores App Store export settings.

```bash
cp path/to/skills/xcode-archive-release/assets/ExportOptions-AppStore.plist ./ExportOptions.plist
# edit as needed
xcode-release.sh ... --export-plist ./ExportOptions.plist
```

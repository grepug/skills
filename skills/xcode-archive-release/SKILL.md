---
name: xcode-archive-release
description: Bump version/build number, archive an Xcode project, and upload to App Store Connect in one workflow. Use when a user wants to release an iOS or macOS app to the App Store — tasks like "archive and upload to ASC", "bump version and release", "release version 2.1.0 build 42", "release from git tag", or "retry a failed upload".
---

# Xcode Archive & Release

Release an Apple app by bumping version/build metadata, archiving with Xcode, then exporting and uploading to App Store Connect.

## Use when

- The user wants to archive and upload an iOS or macOS app to App Store Connect
- The user wants to release from an explicit version/build or infer them from a git tag
- The user needs to retry an upload without rebuilding unless necessary

## Prerequisites

- macOS with Xcode and `xcodebuild` available
- A signed Xcode project with a valid scheme
- Access to the correct Apple Developer team and App Store Connect account
- A clean understanding of the target project, scheme, platform, version, and build number

The main helper is `scripts/xcode-release.sh`. The bundled `assets/ExportOptions-AppStore.plist` sets `method=app-store` and `destination=upload`, so the default flow uploads directly to App Store Connect without a separate `altool` step.

## Confirm before acting

Before running the script, confirm:

- the Xcode project path
- the scheme name
- the version and build number, or that git tag inference is intended
- the target platform: `ios` or `macos`
- whether the user wants a preflight-only validation run first

For mixed-target or higher-risk projects, prefer a dry run with `--preflight-only` before touching source files.

## Workflow

### 1. Discover project details

If the user hasn't specified `--project` or `--scheme`, find them:

```bash
# List .xcodeproj files near the current directory
find . -name "*.xcodeproj" -maxdepth 3

# List available schemes for a project
xcodebuild -project MyApp.xcodeproj -list
```

### 2. Confirm before running

Present a dry-run summary to the user before executing:

```
Project : MyApp.xcodeproj
Scheme  : MyApp_iOS
Version : 2.1.0  Build: 42
Platform: ios (generic/platform=iOS)
Catalyst: no
Archive : ~/.xcode-archive/MyApp/2.1.0-42/MyApp.xcarchive
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
  --scheme   MyApp_iOS

# Or specify explicitly:
path/to/skills/xcode-archive-release/scripts/xcode-release.sh \
  --project  MyApp/MyApp.xcodeproj \
  --scheme   MyApp_iOS \
  --version  2.1.0 \
  --build    42 \
  [--platform ios|macos]   \  # default: ios (uses generic/platform=iOS destination)
  [--catalyst]              \  # adds SUPPORTS_MACCATALYST=YES
  [--export-plist /custom/ExportOptions.plist]  \  # override bundled plist
  [--preflight-only]           # validate setup without building or touching source
  [--force]                    # re-archive even if archive already exists
```

**Git tag format** — must contain exactly one semver component and one integer component, separated by `-`, `+`, `/`, or `_`. Leading `v` is stripped.

| Tag                | Version     | Build |
| ------------------ | ----------- | ----- |
| `v2.1.0-42`        | 2.1.0       | 42    |
| `2.1.0+42`         | 2.1.0       | 42    |
| `2.1.0/42`         | 2.1.0       | 42    |
| `v2.1.0`           | ✗ no build  | —     |
| `release-2.1.0-42` | ✗ ambiguous | —     |

If the tag is ambiguous or missing a component, the script errors with a message directing you to pass `--version` and `--build` explicitly.

### 4. Report results

On success, the script prints the artifact path. Tell the user:

- Where artifacts are: `~/.xcode-archive/<project-name>/<version>-<build>/`
- To check App Store Connect → TestFlight or the Builds tab to confirm the upload processed

If the archive succeeds but automatic export/upload hits a missing App Store provisioning profile for the app’s bundle ID, the script opens the `.xcarchive` in Xcode Organizer instead. In that case, tell the user the archive is ready and they should upload it to App Store Connect manually from Organizer.

## Output

Successful runs produce:

- a versioned archive folder at `~/.xcode-archive/<ProjectName>/<version>-<build>/`
- the `.xcarchive`
- exported artifacts under `export/`
- logs under `logs/archive.log` and `logs/export.log`

The user should verify the build appears in App Store Connect after processing finishes.

## Retry a Failed Upload

If the archive succeeded but upload failed (network issue, ASC outage, etc.):

1. Run the **exact same command** — the script detects the existing `.xcarchive` and skips straight to export/upload.
2. Use `--force` only if you need to rebuild the archive from scratch (e.g. wrong code was archived).

## Output Folder Structure

```
~/.xcode-archive/<ProjectName>/
└── <version>-<build>/              e.g. 2.1.0-42/
    ├── MyApp.xcarchive             the Xcode archive
    ├── DerivedData/                isolated DerivedData for this build
    ├── export/                     export output
    │   ├── MyApp.ipa
    │   ├── ExportOptions.plist     copy of the options used
    │   └── UploadSessionLogs/      ASC upload diagnostic logs
    └── logs/
        ├── archive.log             full xcodebuild archive output
        └── export.log              full xcodebuild -exportArchive output
```

Each run has its own versioned folder — previous builds are preserved for comparison or re-upload.

## Bundled files

- `scripts/xcode-release.sh` — main release workflow
- `assets/ExportOptions-AppStore.plist` — default App Store export settings

## Troubleshooting

| Symptom                                                               | Fix                                                                                                                                                            |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Code signing failed`                                                 | Open Xcode → project target → Signing & Capabilities, ensure a valid provisioning profile and team are set for Release                                         |
| `error: exportArchive No profiles for '<bundle-id>' were found`       | Treat this as an Organizer handoff: open the generated `.xcarchive` in Xcode Organizer and tell the user to upload it to App Store Connect manually            |
| `No schemes found`                                                    | Run `xcodebuild -project MyApp.xcodeproj -list` to list valid scheme names; or use `--preflight-only` to check before running                                  |
| `ERROR ITMS-90189: Duplicate binary upload`                           | The build number already exists in ASC. Increment `--build`                                                                                                    |
| `Archive not found` on retry                                          | Check the path `~/.xcode-archive/<name>/<version>-<build>/<name>.xcarchive` exists; if not, remove `--force` flag confusion and re-run without `--force`       |
| `PlistBuddy: Entry, ":CFBundleShortVersionString", Does Not Exist`    | Harmless — the Info.plist doesn't have that key (modern Xcode projects); the `project.pbxproj` patch handles it                                                |
| `No git tag on HEAD`                                                  | HEAD isn't tagged. Create a tag (`git tag v2.1.0-42 && git push --tags`) or pass `--version` and `--build` explicitly                                          |
| `Tag(s) on HEAD ... don't contain one semver + one integer component` | Tag is missing the build number (e.g. `v2.1.0`) or has an unrecognised part (e.g. `release-2.1.0-42`). Rename the tag or pass `--version`/`--build` explicitly |
| Script fails with `✗ FAILED at step: archive`                         | Check `~/.xcode-archive/<name>/<ver>-<build>/logs/archive.log` for the root cause; the failure block prints the last 20 lines automatically                    |

## ExportOptions Customization

The bundled plist (`assets/ExportOptions-AppStore.plist`) works for standard App Store uploads. To customize (e.g. add `teamID`, `signingStyle`, or `iCloudContainerEnvironment`), copy it to the project folder and pass `--export-plist`:

```bash
cp path/to/skills/xcode-archive-release/assets/ExportOptions-AppStore.plist ./ExportOptions.plist
# edit as needed
xcode-release.sh ... --export-plist ./ExportOptions.plist
```

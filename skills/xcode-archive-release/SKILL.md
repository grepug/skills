---
name: xcode-archive-release
description: Bump version/build number, refresh signing, archive an Xcode project through asc, upload to App Store Connect, upload an internal development IPA through ipa-server, then tag App Store releases in git. Use when a user wants to release an iOS or macOS app to the App Store, upload a development IPA to an internal IPA server, or retry a failed release/upload.
---

# Xcode Archive & Release

Release an Apple app by bumping version/build metadata, then either archiving/exporting through `asc` for App Store Connect or building a development IPA with `xcodebuildmcp` and uploading it to an internal IPA server. App Store Connect releases tag the released `HEAD` in git; internal IPA server uploads do not create release tags.

## Use when

- The user wants to archive and upload an iOS or macOS app to App Store Connect.
- The user wants to build and upload an internal iOS development IPA to an IPA server.
- The user wants to release from an explicit version/build or infer them from a git tag.
- The user needs to retry a failed upload without rebuilding completed platform variants.
- The user wants a scriptable signing refresh instead of manually archiving once in Xcode after an Xcode update.

## Prerequisites

- macOS with Xcode selected.
- `asc` available and authenticated (`asc auth status --validate`).
- `xcodebuildmcp` available for project and scheme discovery.
- A signed Xcode project with a valid scheme.
- App Store Connect app ID and bundle identifier for App Store Connect release paths.
- For internal IPA server uploads, the `ipa-server-usage` skill from `github.com/grepug/ipa-server` or its bundled `ipa_server.py` helper, plus an IPA server base URL from `--ipa-server-url`, `IPA_SERVER_URL`, or project `.env`.
- A usable signing identity in the keychain. `asc signing fetch` downloads profiles and public certificates; it cannot recreate a missing private key.

When changing this skill, edit the source skill folder in the skills repository rather than an installed copy.

## Confirm before acting

Before running the script, confirm:

- Xcode project path.
- Scheme name.
- App Store Connect app ID (`--app` or `ASC_APP_ID`).
- Bundle identifier (`--bundle-id`) unless signing refresh is intentionally skipped.
- Version and build number, or that git tag/archive-history inference is intended.
- Target platform list: any ordered subset of `ios`, `macos`, and `mac_catalyst`.
- Release path: `direct_upload` (default), `publish`, or `ipa_server`.
- For `ipa_server`, infer the IPA server URL from `IPA_SERVER_URL` or project `.env` before asking; confirm the helper path only if the `ipa-server-usage` skill is not installed.
- Whether a preflight-only validation run should happen first.

For mixed-target or higher-risk projects, prefer `--preflight-only` before touching source files.

## Workflow

### 1. Discover project details

Use `xcodebuildmcp` for discovery:

```bash
xcodebuildmcp project-discovery discover-projects --scan-path . --max-depth 3
xcodebuildmcp project-discovery list-schemes --project-path MyApp.xcodeproj
```

### 2. Confirm before running

Present a dry-run summary before executing:

```text
Project      : MyApp.xcodeproj
Scheme       : MyApp_iOS
App          : 123456789
Bundle ID    : com.example.myapp
Version      : 2.1.0 (42)
Release path : direct_upload
Platform     : ios
Archive      : ~/.xcode-archive/MyApp/2.1.0-42/MyApp-ios.xcarchive
IPA path     : ~/.xcode-archive/MyApp/2.1.0-42/export-ios/MyApp-ios.ipa
```

Preflight:

```bash
scripts/xcode-release.sh \
  --project MyApp.xcodeproj \
  --scheme MyApp_iOS \
  --app 123456789 \
  --bundle-id com.example.myapp \
  --version 2.1.0 \
  --build 42 \
  --preflight-only
```

### 3. Run the script

Direct upload is the default release path. It uses `asc xcode archive` and `asc xcode export --wait` with the bundled direct-upload export plist (`destination=upload`):

```bash
scripts/xcode-release.sh \
  --project MyApp.xcodeproj \
  --scheme MyApp_iOS \
  --app 123456789 \
  --bundle-id com.example.myapp \
  --version 2.1.0 \
  --build 42 \
  --platform ios
```

Publish mode exports a local IPA, then runs `asc publish appstore`. It uploads and attaches only; it does not submit for review:

```bash
scripts/xcode-release.sh \
  --project MyApp.xcodeproj \
  --scheme MyApp_iOS \
  --app 123456789 \
  --bundle-id com.example.myapp \
  --version 2.1.0 \
  --build 42 \
  --platform ios \
  --release-path publish
```

IPA server mode builds a Debug device app with `xcodebuildmcp`, packages a development IPA, then uploads it through the `ipa-server-usage` helper. It does not use `asc`, does not submit to App Store Connect, and does not create a git release tag:

```bash
scripts/xcode-release.sh \
  --project MyApp.xcodeproj \
  --scheme MyApp_iOS \
  --bundle-id com.example.myapp \
  --version 2.1.0 \
  --build 42 \
  --platform ios \
  --release-path ipa_server \
  --ipa-server-url https://ipa.example.com
```

If `IPA_SERVER_URL` is set in the environment or in the nearest project `.env`, omit `--ipa-server-url`.

Useful options:

```bash
--profile-type IOS_APP_STORE          # override signing refresh profile type
--signing-output ./signing-release    # override signing refresh output dir
--skip-signing-refresh                # skip asc signing fetch/profile install
--import-certificates                 # import downloaded .cer files into login keychain
--export-plist ./Upload.plist         # direct_upload export plist override
--local-export-plist ./Local.plist    # publish-mode export plist override
--ipa-server-project "Project Name"   # override IPA server project metadata
--ipa-server-helper ./ipa_server.py   # override ipa-server-usage helper path
--device-configuration Debug          # ipa_server build configuration
--force                               # rebuild even if archive/marker exists
```

When multiple platforms are listed, the script builds them sequentially in the order provided. Version/build resolution happens once for the whole batch.

## Version and build inference

Git tag format must contain exactly one semver component and one integer component, separated by `-`, `+`, `/`, or `_`. Leading `v` is stripped.

| Tag                | Version | Build |
| ------------------ | ------- | ----- |
| `v2.1.0-42`        | 2.1.0   | 42    |
| `2.1.0+42`         | 2.1.0   | 42    |
| `2.1.0/42`         | 2.1.0   | 42    |
| `v2.1.0`           | invalid | -     |
| `release-2.1.0-42` | invalid | -     |

If no parseable tag exists, the script scans `~/.xcode-archive/<ProjectName>/` for the highest prior `<version>-<build>` folder and increments the build. `--bumpPatch`, `--bumpMinor`, and `--bumpMajor` are valid only with archive-history inference.

## Signing refresh

Signing refresh runs before version edits and archive unless `--skip-signing-refresh` is set:

```bash
asc signing fetch \
  --app "$APP" \
  --bundle-id "$BUNDLE_ID" \
  --profile-type "$PROFILE_TYPE" \
  --create-missing \
  --output "$SIGNING_OUTPUT" \
  --format json
```

The script installs fetched `.mobileprovision` files into `~/Library/MobileDevice/Provisioning Profiles/`, optionally imports `.cer` files with `--import-certificates`, and fails early if `security find-identity -v -p codesigning` reports no usable signing identity.

Default profile types:

| Platform      | Profile type              |
| ------------- | ------------------------- |
| `ios`         | `IOS_APP_STORE`           |
| `macos`       | `MAC_APP_STORE`           |
| `mac_catalyst`| `MAC_CATALYST_APP_STORE`  |

For `ipa_server`, signing is delegated to `xcodebuildmcp device build` with `-allowProvisioningUpdates`. This matches development IPA workflows where Xcode automatic signing creates or refreshes development profiles. The script packages the built `.app` into an IPA and verifies `Payload/<App>.app/embedded.mobileprovision` exists before upload.

## IPA server uploads

The IPA server upload path delegates HTTP behavior to the `ipa-server-usage` skill from `github.com/grepug/ipa-server`. Prefer installing that skill and letting the script discover its `ipa_server.py` helper. If discovery is not possible, pass `--ipa-server-helper`.

Required inputs for `ipa_server`:

- `--bundle-id`
- `--ipa-server-url`, `IPA_SERVER_URL`, or nearest project `.env` containing `IPA_SERVER_URL`
- `--platform ios`
- version/build, or tag/archive-history inference

The helper uploads with:

```bash
python3 "$IPA_SERVER_HELPER" \
  --server "$IPA_SERVER_URL" \
  upload \
  --ipa "$IPA_PATH" \
  --project "$IPA_SERVER_PROJECT" \
  --version "$VERSION" \
  --build-number "$BUILD" \
  --bundle-id "$BUNDLE_ID"
```

## Git tag

After a successful App Store Connect upload, the script creates and pushes an annotated release tag:

- tag format: `v<version>-<build>`
- example: `v2.1.0-42`
- tag message: `Release 2.1.0 (42)`

The tag is created on the current `HEAD`. The script does not create a git commit for version/build edits. If the tag already exists locally or on the remote, the script fails without moving or force-pushing the tag.

The `ipa_server` release path skips git release tags because it is an internal development upload, not an immutable App Store release marker.

## Output

Successful runs produce:

- a versioned archive folder at `~/.xcode-archive/<ProjectName>/<version>-<build>/`
- the `.xcarchive`
- exported artifacts under `export-<platform-variant>/`
- logs under `logs-<platform-variant>/`
- fetched signing assets under `signing-<platform-variant>/`
- a per-platform completion marker used to skip already completed variants on rerun
- an annotated git tag `v<version>-<build>` pushed to the configured remote after upload succeeds

The user should verify the build appears in App Store Connect after processing finishes.

## Retry a failed upload

If one platform in a batch fails:

1. If the original run pinned version/build explicitly or inferred them from a git tag, run the exact same command.
2. If the original run inferred version/build from archive history, use the retry command printed on failure.
3. Use `--force` only when the archive or signing state must be rebuilt from scratch.

If upload succeeded but tag creation or tag push failed, do not rerun the full release command blindly. Use the tag-specific failure message to create or push the tag manually.

## Bundled files

- `scripts/xcode-release.sh` — main release workflow
- `assets/ExportOptions-AppStore.plist` — direct-upload App Store export settings
- `assets/ExportOptions-AppStore-Local.plist` — local IPA App Store export settings for publish mode
- `github.com/grepug/ipa-server/skills/ipa-server-usage` — referenced helper skill for internal IPA server uploads

## Troubleshooting

| Symptom | Fix |
| ------- | --- |
| `--app is required` | Pass `--app` or set `ASC_APP_ID`. |
| `--bundle-id is required` | Pass `--bundle-id`, or use `--skip-signing-refresh` only when signing assets are already installed. |
| `--ipa-server-url is required` | Pass `--ipa-server-url`, export `IPA_SERVER_URL`, or add `IPA_SERVER_URL` to the project `.env`. |
| `ipa-server-usage helper not found` | Install the skill from `github.com/grepug/ipa-server` or pass `--ipa-server-helper`. |
| Packaged IPA missing `embedded.mobileprovision` | Fix development signing for the device build; OTA installation needs an embedded provisioning profile. |
| `asc signing fetch` fails | Check `asc auth status --validate`, bundle ID, app ID, and profile type. |
| No usable code signing identity | Install the distribution certificate with its private key; public `.cer` files alone are not enough. |
| Archive or export fails after signing refresh | Check `logs-<platform>/archive.log` or `logs-<platform>/export.log`; retry with `--force` after fixing signing or project settings. |
| Duplicate binary upload | Increment `--build`. |
| Release tag already exists | Treat tags as immutable; use a new build number for a new release attempt. |

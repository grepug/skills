#!/usr/bin/env bash
# xcode-release.sh — bump version, archive, upload to TestFlight and/or ipa-server, and tag releases
# Usage:
#   xcode-release.sh --project Foo.xcodeproj --scheme FooScheme \
#                    [--version 2.1.0 --build 42]  # or infer from git tag on HEAD
#                    [--platform ios|macos|mac_catalyst[,ios|macos|mac_catalyst...]] \
#                    [--export-plist /path/to/ExportOptions.plist] \
#                    [--upload-mode testflight|test-ipa|both] \
#                    [--force] [--preflight-only]

set -Eeuo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $(basename "$0") OPTIONS

Required:
  --project   <path>    Path to the .xcodeproj file for new archive runs
  --scheme    <name>    Xcode scheme for new archive runs

Version (provide both for new archives, or use artifact metadata/auto-inference):
  --version   <semver>  Marketing version, e.g. 2.1.0
  --build     <int>     Build number, e.g. 42

  For new archives, when both are omitted, version/build are inferred in this order:
    1. Git tag on HEAD — must contain one semver + one integer component,
       separated by any of: - + / _  (e.g. v2.1.0-42  2.1.0+42)
    2. Archive history — scans ~/.xcode-archive/<project>/ for the folder
       with the highest build number; new build = max + 1.

Version bump (only with archive-history inference; cannot combine with --version/--build):
  --bumpPatch                   Increment patch: 2.1.4 → 2.1.5
  --bumpMinor                   Increment minor, reset patch: 2.1.4 → 2.2.0
  --bumpMajor                   Increment major, reset minor+patch: 2.1.4 → 3.0.0

Optional:
  --platform  <list>            Comma-separated platforms in execution order.
                                Allowed values: ios, macos, mac_catalyst
                                Default: ios
  --upload-mode <mode>          Upload destination: testflight, test-ipa, or both
                                Default: testflight
  --export-plist  <path>        Override the bundled ExportOptions.plist
  --test-ipa-export-plist <path> Override ExportOptions.plist for direct-install
                                IPA export used by test-ipa/both
  --test-ipa-export-method <m>  Direct-install export method for test-ipa/both.
                                Allowed: ad-hoc, development, enterprise.
                                Default: development
  --ipa-server <url>            ipa-server base URL for test-ipa/both
                                Falls back to IPA_SERVER_URL
  --ipa-server-helper <path>    Path to ipa_server.py helper
                                Falls back to IPA_SERVER_HELPER, then sibling
                                ipa-server-usage skill path
  --archive-path <path>         Reuse an existing .xcarchive instead of bumping
                                project files and archiving
                                Cannot be combined with --ipa-path
  --ipa-path <path>             Reuse an existing .ipa for test-ipa upload only
                                Cannot be combined with --archive-path
  --project-name <name>         Project/app name for ipa-server metadata.
                                Falls back to artifact metadata or project name.
  --bundle-id <id>              Bundle identifier override for ipa-server upload
  --tag-existing-artifact       Allow release tag creation from --archive-path
                                after all requested uploads succeed
  --force                       Re-archive even if an archive already exists
  --preflight-only              Validate setup (scheme, plist, paths) without
                                mutating files or building anything
                                Successful automatic uploads create and push
                                the annotated git tag v<version>-<build>
  -h, --help                    Show this help
EOF
}

log()  { echo "[xcode-release] $*"; }
err()  { echo "[xcode-release] ERROR: $*" >&2; exit 1; }

TAG_NAME=""
TAG_REMOTE=""
TAG_CREATED=0
UPLOAD_SUCCEEDED=0
TESTFLIGHT_UPLOAD_SUCCEEDED=0
TEST_IPA_UPLOAD_SUCCEEDED=0
TEST_IPA_INSTALL_OUTPUT=""

build_retry_cmd() {
  RETRY_CMD="$(basename "$0")"
  if [[ -n "${PROJECT:-}" ]]; then
    RETRY_CMD="${RETRY_CMD} --project \"$PROJECT\""
  fi
  if [[ -n "${SCHEME:-}" ]]; then
    RETRY_CMD="${RETRY_CMD} --scheme \"$SCHEME\""
  fi
  if [[ -n "${PROJECT_NAME:-}" ]]; then
    RETRY_CMD="${RETRY_CMD} --project-name \"$PROJECT_NAME\""
  fi
  RETRY_CMD="${RETRY_CMD} --version \"${VERSION:-?}\" --build \"${BUILD:-?}\" --platform \"${PLATFORM:-?}\" --upload-mode \"${UPLOAD_MODE:-testflight}\""
  if [[ -n "$EXPORT_PLIST" ]]; then
    RETRY_CMD="${RETRY_CMD} --export-plist \"$EXPORT_PLIST\""
  fi
  if [[ -n "${TEST_IPA_EXPORT_PLIST:-}" ]]; then
    RETRY_CMD="${RETRY_CMD} --test-ipa-export-plist \"$TEST_IPA_EXPORT_PLIST\""
  fi
  if [[ -n "${TEST_IPA_EXPORT_METHOD:-}" && "${TEST_IPA_EXPORT_METHOD:-}" != "development" ]]; then
    RETRY_CMD="${RETRY_CMD} --test-ipa-export-method \"$TEST_IPA_EXPORT_METHOD\""
  fi
  if [[ -n "${BUNDLE_ID:-}" ]]; then
    RETRY_CMD="${RETRY_CMD} --bundle-id \"$BUNDLE_ID\""
  fi
  if [[ -n "${IPA_SERVER:-}" ]]; then
    RETRY_CMD="${RETRY_CMD} --ipa-server \"$IPA_SERVER\""
  fi
  if [[ -n "${IPA_SERVER_HELPER:-}" ]]; then
    RETRY_CMD="${RETRY_CMD} --ipa-server-helper \"$IPA_SERVER_HELPER\""
  fi
  if [[ -n "${ARCHIVE_PATH_OVERRIDE:-}" ]]; then
    RETRY_CMD="${RETRY_CMD} --archive-path \"$ARCHIVE_PATH_OVERRIDE\""
  fi
  if [[ -n "${IPA_PATH:-}" ]]; then
    RETRY_CMD="${RETRY_CMD} --ipa-path \"$IPA_PATH\""
  fi
  if [[ ${TAG_EXISTING_ARTIFACT:-0} -eq 1 ]]; then
    RETRY_CMD="${RETRY_CMD} --tag-existing-artifact"
  fi
  if [[ $FORCE -eq 1 ]]; then
    RETRY_CMD="${RETRY_CMD} --force"
  fi
  if [[ $PREFLIGHT_ONLY -eq 1 ]]; then
    RETRY_CMD="${RETRY_CMD} --preflight-only"
  fi
}

open_archive_in_xcode() {
  local archive_path="$1"
  if [[ -d "$archive_path" ]]; then
    log "Opening archive in Xcode Organizer for manual upload…"
    open -a Xcode "$archive_path" >/dev/null 2>&1 || true
  fi
}

release_tag_name() {
  echo "v${VERSION}-${BUILD}"
}

resolve_push_remote() {
  if [[ -z "$PROJECT_DIR" ]]; then
    echo "[xcode-release] Tagging skipped: no project directory is available." >&2
    return 1
  fi

  if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[xcode-release] Tagging skipped: project is not inside a git repository." >&2
    return 1
  fi

  local remote_name=""
  remote_name="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null | sed 's#/.*##' || true)"

  if [[ -z "$remote_name" ]] && git -C "$PROJECT_DIR" remote get-url origin >/dev/null 2>&1; then
    remote_name="origin"
  fi

  if [[ -z "$remote_name" ]]; then
    echo "[xcode-release] Tagging skipped: no upstream remote configured and no origin remote found." >&2
    return 1
  fi

  echo "$remote_name"
}

local_tag_exists() {
  local tag_name="$1"
  git -C "$PROJECT_DIR" rev-parse -q --verify "refs/tags/${tag_name}" >/dev/null 2>&1
}

remote_tag_exists() {
  local remote_name="$1"
  local tag_name="$2"
  local remote_output=""

  if ! remote_output="$(git -C "$PROJECT_DIR" ls-remote --tags "$remote_name" "refs/tags/${tag_name}" 2>&1)"; then
    log "Unable to query tags on remote '${remote_name}': ${remote_output}"
    return 2
  fi

  [[ -n "$remote_output" ]]
}

# ── argument parsing ─────────────────────────────────────────────────────────

PROJECT=""
PROJECT_NAME=""
SCHEME=""
VERSION=""
BUILD=""
BUNDLE_ID=""
BUMP=""     # patch | minor | major | ""
PLATFORM="ios"
UPLOAD_MODE="testflight"
EXPORT_PLIST=""
TEST_IPA_EXPORT_PLIST=""
TEST_IPA_EXPORT_METHOD="development"
TEST_IPA_EXPORT_METHOD_SET=0
IPA_SERVER="${IPA_SERVER_URL:-}"
IPA_SERVER_HELPER="${IPA_SERVER_HELPER:-}"
ARCHIVE_PATH_OVERRIDE=""
IPA_PATH=""
TAG_EXISTING_ARTIFACT=0
FORCE=0
PREFLIGHT_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)        PROJECT="$2";      shift 2 ;;
    --project-name)   PROJECT_NAME="$2"; shift 2 ;;
    --scheme)         SCHEME="$2";       shift 2 ;;
    --version)        VERSION="$2";      shift 2 ;;
    --build)          BUILD="$2";        shift 2 ;;
    --bumpPatch)      BUMP="patch";      shift   ;;
    --bumpMinor)      BUMP="minor";      shift   ;;
    --bumpMajor)      BUMP="major";      shift   ;;
    --bundle-id)      BUNDLE_ID="$2";    shift 2 ;;
    --platform)       PLATFORM="$2";     shift 2 ;;
    --upload-mode)    UPLOAD_MODE="$2";  shift 2 ;;
    --export-plist)   EXPORT_PLIST="$2"; shift 2 ;;
    --test-ipa-export-plist) TEST_IPA_EXPORT_PLIST="$2"; shift 2 ;;
    --test-ipa-export-method) TEST_IPA_EXPORT_METHOD="$2"; TEST_IPA_EXPORT_METHOD_SET=1; shift 2 ;;
    --ipa-server)     IPA_SERVER="$2";   shift 2 ;;
    --ipa-server-helper) IPA_SERVER_HELPER="$2"; shift 2 ;;
    --archive-path)   ARCHIVE_PATH_OVERRIDE="$2"; shift 2 ;;
    --ipa-path)       IPA_PATH="$2";     shift 2 ;;
    --tag-existing-artifact) TAG_EXISTING_ARTIFACT=1; shift ;;
    --force)          FORCE=1;           shift   ;;
    --preflight-only) PREFLIGHT_ONLY=1;  shift   ;;
    -h|--help)        usage; exit 0 ;;
    *) err "Unknown argument: $1" ;;
  esac
done

# ── validate required args ────────────────────────────────────────────────────

NEW_ARCHIVE_RUN=0
if [[ -z "$ARCHIVE_PATH_OVERRIDE" && -z "$IPA_PATH" ]]; then
  NEW_ARCHIVE_RUN=1
fi

if [[ $NEW_ARCHIVE_RUN -eq 1 ]]; then
  [[ -n "$PROJECT" ]] || err "--project is required for new archive runs"
  [[ -n "$SCHEME" ]] || err "--scheme is required for new archive runs"
fi

if [[ $TAG_EXISTING_ARTIFACT -eq 1 && -z "$PROJECT" ]]; then
  err "--tag-existing-artifact requires --project so the script can resolve the git repository and remote"
fi

case "$UPLOAD_MODE" in
  testflight|test-ipa|both) ;;
  *) err "--upload-mode must be testflight, test-ipa, or both (got: $UPLOAD_MODE)" ;;
esac

case "$TEST_IPA_EXPORT_METHOD" in
  ad-hoc|development|enterprise) ;;
  *) err "--test-ipa-export-method must be ad-hoc, development, or enterprise (got: $TEST_IPA_EXPORT_METHOD)" ;;
esac

if [[ -n "$TEST_IPA_EXPORT_PLIST" && "$UPLOAD_MODE" == "testflight" ]]; then
  err "--test-ipa-export-plist only applies to --upload-mode test-ipa or both"
fi

if [[ -n "$IPA_PATH" && "$UPLOAD_MODE" != "test-ipa" ]]; then
  err "--ipa-path can only be used with --upload-mode test-ipa"
fi

if [[ -n "$ARCHIVE_PATH_OVERRIDE" && -n "$IPA_PATH" ]]; then
  err "--archive-path and --ipa-path cannot be combined. Use --archive-path to export from an archive, or --ipa-path to upload an existing IPA."
fi

if [[ -n "$IPA_PATH" && $FORCE -eq 1 ]]; then
  err "--ipa-path cannot be combined with --force because no archive is built"
fi

if [[ -n "$IPA_PATH" && -n "$TEST_IPA_EXPORT_PLIST" ]]; then
  err "--test-ipa-export-plist cannot be combined with --ipa-path because no export is performed"
fi

if [[ -n "$IPA_PATH" && $TEST_IPA_EXPORT_METHOD_SET -eq 1 ]]; then
  err "--test-ipa-export-method cannot be combined with --ipa-path because no export is performed"
fi

if [[ -n "$ARCHIVE_PATH_OVERRIDE" && -n "$BUMP" ]]; then
  err "--archive-path cannot be combined with version bump flags"
fi

if [[ -n "$IPA_PATH" && -n "$BUMP" ]]; then
  err "--ipa-path cannot be combined with version bump flags"
fi

# version/build: normal archive runs must be both-or-neither. Existing artifact
# runs may provide one override and infer the other from artifact metadata.
if [[ -z "$ARCHIVE_PATH_OVERRIDE" && -z "$IPA_PATH" ]] && { [[ -n "$VERSION" && -z "$BUILD" ]] || [[ -z "$VERSION" && -n "$BUILD" ]]; }; then
  err "Provide both --version and --build, or omit both to auto-infer."
fi

# --bump* flags are only valid when version/build are inferred, not explicit
if [[ -n "$BUMP" && ( -n "$VERSION" || -n "$BUILD" ) ]]; then
  err "--bump${BUMP^} cannot be combined with explicit --version/--build."
fi

if [[ -n "$PROJECT" ]]; then
  [[ -d "$PROJECT" ]] || err "Project not found: $PROJECT"
  PROJECT="$(cd "$PROJECT" && pwd)"
fi

# ── git tag inference ─────────────────────────────────────────────────────────

TAG_SOURCE=""

infer_from_tag() {
  local project_dir="$1"

  # Collect all tags pointing exactly at HEAD (more reliable than git-describe on macOS)
  local -a tags
  IFS=$'\n' read -r -d '' -a tags < <(git -C "$project_dir" tag --points-at HEAD 2>/dev/null && printf '\0') || true

  if [[ ${#tags[@]} -eq 0 ]]; then
    return 1
  fi

  # Try to parse each tag; collect the ones that yield version+build
  local matched_tag="" matched_version="" matched_build=""

  for tag in "${tags[@]}"; do
    [[ -z "$tag" ]] && continue

    # Strip optional leading 'v' (case-insensitive)
    local stripped="${tag#[vV]}"

    # Normalise separators (-, +, /, _) → space then split into parts
    # Use sed for BSD/macOS compatibility (avoids tr argument ordering quirks)
    local -a parts
    IFS=' ' read -r -a parts <<< "$(echo "$stripped" | sed 's/[-+\/_]/ /g')"

    local fv="" fb="" ok=1
    for part in "${parts[@]+"${parts[@]}"}"; do
      if [[ "$part" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        [[ -n "$fv" ]] && ok=0 && break   # two semver components
        fv="$part"
      elif [[ "$part" =~ ^[0-9]+$ ]]; then
        [[ -n "$fb" ]] && ok=0 && break   # two integer components
        fb="$part"
      else
        ok=0 && break                     # unrecognised component
      fi
    done

    [[ -z "$fv" || -z "$fb" ]] && ok=0

    if [[ $ok -eq 1 ]]; then
      if [[ -n "$matched_tag" ]]; then
        err "Multiple parseable tags on HEAD ('$matched_tag', '$tag'). Provide --version and --build explicitly, or remove the ambiguous tags."
      fi
      matched_tag="$tag"; matched_version="$fv"; matched_build="$fb"
    fi
  done

  if [[ -z "$matched_tag" ]]; then
    return 1
  fi

  log "Found git tag: $matched_tag"
  VERSION="$matched_version"
  BUILD="$matched_build"
  TAG_SOURCE=" (from git tag: $matched_tag)"
}

# ── archive history inference ─────────────────────────────────────────────────

infer_from_archives() {
  local dir="${HOME}/.xcode-archive/${PROJECT_NAME}"

  if [[ ! -d "$dir" ]]; then
    return 1
  fi

  local best_build=-1
  local best_version=""

  while IFS= read -r -d '' folder; do
    local name
    name="$(basename "$folder")"
    # Match folders produced by this script: semver-integer
    if [[ "$name" =~ ^([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)$ ]]; then
      local fv="${BASH_REMATCH[1]}"
      local fb="${BASH_REMATCH[3]}"
      if [[ "$fb" -gt "$best_build" ]]; then
        best_build="$fb"
        best_version="$fv"
      fi
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -print0)

  if [[ -z "$best_version" ]]; then
    return 1
  fi

  local new_build=$(( best_build + 1 ))
  local new_version="$best_version"

  if [[ -n "$BUMP" ]]; then
    local major minor patch
    IFS='.' read -r major minor patch <<< "$best_version"
    patch="${patch:-0}"
    case "$BUMP" in
      patch) patch=$(( patch + 1 )) ;;
      minor) minor=$(( minor + 1 )); patch=0 ;;
      major) major=$(( major + 1 )); minor=0; patch=0 ;;
    esac
    new_version="${major}.${minor}.${patch}"
  fi

  log "Found archive history: ${best_version}-${best_build}"
  VERSION="$new_version"
  BUILD="$new_build"
  if [[ -n "$BUMP" ]]; then
    TAG_SOURCE=" (from archive history: ${best_version}-${best_build} → ${new_version}, build ${new_build})"
  else
    TAG_SOURCE=" (from archive history: ${best_version}-${best_build} → build ${new_build})"
  fi
}

# ── step tracking + failure trap ─────────────────────────────────────────────

CURRENT_STEP="init"
RETRY_CMD=""

on_error() {
  echo ""
  log "──────────────────────────────────────────"
  log "✗ FAILED at step: ${CURRENT_STEP}"
  local log_file=""
  case "$CURRENT_STEP" in
    archive)         log_file="${LOGS_DIR:-}/archive.log" ;;
    export)          log_file="${LOGS_DIR:-}/export.log"  ;;
    test-ipa-export) log_file="${LOGS_DIR:-}/test-ipa-export.log" ;;
    test-ipa-upload) log_file="${LOGS_DIR:-}/test-ipa-upload.log" ;;
  esac
  if [[ -n "$log_file" && -f "$log_file" ]]; then
    log "  Log: $log_file"
    log "  Tail:"
    tail -20 "$log_file" | sed 's/^/    /'
  fi

  if [[ "$CURRENT_STEP" == "tag" ]]; then
    if [[ $UPLOAD_SUCCEEDED -eq 1 ]]; then
      log "  Upload status: upload to App Store Connect succeeded before tagging failed."
    fi

    if [[ -n "$TAG_NAME" ]]; then
      log "  Release tag: ${TAG_NAME}"
    fi

    if [[ $TAG_CREATED -eq 1 && -n "$TAG_REMOTE" ]]; then
      log "  Local tag status: created locally, but push failed."
      log "  Manual recovery:"
      log "    git -C \"$PROJECT_DIR\" push \"$TAG_REMOTE\" \"$TAG_NAME\""
    else
      log "  Local tag status: no new remote tag was pushed."
    fi
  else
    log "  Retry command:"
    build_retry_cmd
    log "    ${RETRY_CMD}"
  fi
  log "──────────────────────────────────────────"
}

trap 'on_error' ERR

# ── preflight checks ──────────────────────────────────────────────────────────

run_preflight() {
  local ok=1
  log "Running preflight checks…"

  # 1. XcodeBuildMCP is preferred for supported discovery/build operations.
  if command -v xcodebuildmcp &>/dev/null; then
    log "  ✓ xcodebuildmcp: $(xcodebuildmcp --version 2>/dev/null || echo available)"
  elif [[ $NEW_ARCHIVE_RUN -eq 1 ]]; then
    log "  ✗ xcodebuildmcp not found in PATH"; ok=0
  else
    log "  - xcodebuildmcp not found; not required for existing artifact mode"
  fi

  # Archive/export still uses the release helper's xcodebuild path because
  # xcodebuildmcp does not currently expose archive/exportArchive commands.
  if [[ -z "$IPA_PATH" ]]; then
    if command -v xcodebuild &>/dev/null; then
      local xcode_version=""
      xcode_version="$(xcodebuild -version 2>/dev/null | sed -n '1p')"
      log "  ✓ Xcode archive/export support: ${xcode_version:-available}"
    else
      log "  ✗ xcodebuild not found in PATH for archive/export"; ok=0
    fi
  fi

  # 2. Project directory exists when this run uses a project.
  if [[ -n "$PROJECT" ]]; then
    if [[ -d "$PROJECT" ]]; then
      log "  ✓ Project: $PROJECT"
    else
      log "  ✗ Project not found: $PROJECT"; ok=0
    fi
  else
    log "  - Project: not required for existing artifact mode"
  fi

  # 3. Scheme exists in project
  if [[ $NEW_ARCHIVE_RUN -eq 1 ]]; then
    local schemes_output=""
    schemes_output="$(xcodebuildmcp project-discovery list-schemes --project-path "$PROJECT" --output raw 2>/dev/null || true)"
    if echo "$schemes_output" | grep -qF "$SCHEME"; then
      log "  ✓ Scheme: $SCHEME"
    else
      log "  ✗ Scheme '$SCHEME' not found. Available schemes:"
      echo "$schemes_output" | head -20 | sed 's/^/      /'
      ok=0
    fi
  fi

  # 4. Export plist valid
  if [[ -z "$IPA_PATH" ]]; then
    if [[ -f "$EXPORT_PLIST" ]] && /usr/libexec/PlistBuddy -c "Print :method" "$EXPORT_PLIST" &>/dev/null; then
      log "  ✓ ExportOptions.plist: $EXPORT_PLIST"
    else
      log "  ✗ ExportOptions.plist missing or invalid: $EXPORT_PLIST"; ok=0
    fi
  fi

  if [[ "$UPLOAD_MODE" == "test-ipa" || "$UPLOAD_MODE" == "both" ]]; then
    if [[ -n "$TEST_IPA_EXPORT_PLIST" ]]; then
      if [[ -f "$TEST_IPA_EXPORT_PLIST" ]] && /usr/libexec/PlistBuddy -c "Print :method" "$TEST_IPA_EXPORT_PLIST" &>/dev/null; then
        local test_ipa_method=""
        test_ipa_method="$(plist_value "$TEST_IPA_EXPORT_PLIST" ":method")"
        case "$test_ipa_method" in
          ad-hoc|development|enterprise)
            log "  ✓ Test IPA ExportOptions.plist: $TEST_IPA_EXPORT_PLIST ($test_ipa_method)"
            ;;
          *)
            log "  ✗ Test IPA ExportOptions.plist must use method development, ad-hoc, or enterprise (got: ${test_ipa_method:-missing})"; ok=0
            ;;
        esac
      else
        log "  ✗ Test IPA ExportOptions.plist missing or invalid: $TEST_IPA_EXPORT_PLIST"; ok=0
      fi
    else
      log "  ✓ Test IPA export method: $TEST_IPA_EXPORT_METHOD"
    fi
  fi

  # 5. Version + build resolved
  [[ -n "$PROJECT_NAME" ]] && log "  ✓ Project name: $PROJECT_NAME"
  log "  ✓ Version: $VERSION, Build: $BUILD${TAG_SOURCE}"
  [[ -n "$BUNDLE_ID" ]] && log "  ✓ Bundle id: $BUNDLE_ID"

  if [[ "$UPLOAD_MODE" == "test-ipa" || "$UPLOAD_MODE" == "both" ]]; then
    if [[ -n "$BUNDLE_ID" ]]; then
      :
    else
      log "  ✗ Bundle id missing. Pass --bundle-id or use an artifact with readable metadata."; ok=0
    fi
    if [[ -n "$IPA_SERVER" ]]; then
      log "  ✓ ipa-server: $IPA_SERVER"
    else
      log "  ✗ ipa-server URL missing. Pass --ipa-server or set IPA_SERVER_URL"; ok=0
    fi
    if [[ -f "$IPA_SERVER_HELPER" ]]; then
      log "  ✓ ipa-server helper: $IPA_SERVER_HELPER"
    else
      log "  ✗ ipa-server helper not found: $IPA_SERVER_HELPER"; ok=0
    fi
  fi

  # 6. Output dir writable
  local archive_parent
  archive_parent="$(dirname "$RUN_DIR")"
  mkdir -p "$archive_parent" 2>/dev/null || true
  if [[ -w "$archive_parent" ]]; then
    log "  ✓ Output dir: $RUN_DIR"
  else
    log "  ✗ Cannot write to output dir: $archive_parent"; ok=0
  fi

  local ready_action="archive"
  if [[ -n "$IPA_PATH" ]]; then
    ready_action="upload existing IPA"
  elif [[ -n "$ARCHIVE_PATH_OVERRIDE" ]]; then
    ready_action="export/upload existing archive"
  fi

  if [[ $ok -eq 1 ]]; then
    log "Preflight passed. Ready to $ready_action."
  else
    log "Preflight FAILED. Fix the issues above before continuing."
    exit 1
  fi
}

# ── resolve paths ─────────────────────────────────────────────────────────────

PROJECT_DIR=""
if [[ -n "$PROJECT" ]]; then
  PROJECT_DIR="$(cd "$(dirname "$PROJECT")" && pwd)"
  if [[ -z "$PROJECT_NAME" ]]; then
    PROJECT_NAME="$(basename "$PROJECT" .xcodeproj)"
  fi
fi

# Bundled ExportOptions plist is next to this script in ../assets/. The
# ipa-server helper lives in a sibling skill when that external dependency is
# installed from the same skills catalog.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PLIST="${SCRIPT_DIR}/../assets/ExportOptions-AppStore.plist"
EXPORT_PLIST="${EXPORT_PLIST:-$DEFAULT_PLIST}"
DEFAULT_IPA_SERVER_HELPER="${SCRIPT_DIR}/../../ipa-server-usage/scripts/ipa_server.py"
IPA_SERVER_HELPER="${IPA_SERVER_HELPER:-$DEFAULT_IPA_SERVER_HELPER}"

plist_value() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print ${key}" "$plist" 2>/dev/null || true
}

absolutize_existing_file() {
  local input_path="$1"
  [[ -f "$input_path" ]] || err "File not found: $input_path"
  local parent
  parent="$(cd "$(dirname "$input_path")" && pwd)"
  echo "${parent}/$(basename "$input_path")"
}

absolutize_existing_dir() {
  local input_path="$1"
  [[ -d "$input_path" ]] || err "Directory not found: $input_path"
  (cd "$input_path" && pwd)
}

if [[ -n "$TEST_IPA_EXPORT_PLIST" ]]; then
  TEST_IPA_EXPORT_PLIST="$(absolutize_existing_file "$TEST_IPA_EXPORT_PLIST")"
fi

if [[ -z "$IPA_PATH" ]]; then
  [[ -f "$EXPORT_PLIST" ]] || err "ExportOptions.plist not found: $EXPORT_PLIST"
fi

apply_metadata_if_missing() {
  local source="$1"
  local source_version="$2"
  local source_build="$3"
  local source_bundle_id="$4"
  local source_project_name="${5:-}"

  if [[ -z "$PROJECT_NAME" && -n "$source_project_name" ]]; then
    PROJECT_NAME="$source_project_name"
    log "Inferred project name from ${source}: $PROJECT_NAME"
  fi
  if [[ -z "$VERSION" && -n "$source_version" ]]; then
    VERSION="$source_version"
    log "Inferred version from ${source}: $VERSION"
  fi
  if [[ -z "$BUILD" && -n "$source_build" ]]; then
    BUILD="$source_build"
    log "Inferred build from ${source}: $BUILD"
  fi
  if [[ -z "$BUNDLE_ID" && -n "$source_bundle_id" ]]; then
    BUNDLE_ID="$source_bundle_id"
    log "Inferred bundle id from ${source}: $BUNDLE_ID"
  fi
}

infer_archive_metadata() {
  local archive_path="$1"
  local archive_info="${archive_path}/Info.plist"
  local source_version="" source_build="" source_bundle_id="" source_project_name=""

  if [[ -f "$archive_info" ]]; then
    source_project_name="$(plist_value "$archive_info" ":Name")"
    source_version="$(plist_value "$archive_info" ":ApplicationProperties:CFBundleShortVersionString")"
    source_build="$(plist_value "$archive_info" ":ApplicationProperties:CFBundleVersion")"
    source_bundle_id="$(plist_value "$archive_info" ":ApplicationProperties:CFBundleIdentifier")"
  fi

  if [[ -z "$source_build" || -z "$source_bundle_id" || -z "$source_version" ]]; then
    local app_info=""
    app_info="$(find "${archive_path}/Products/Applications" -maxdepth 2 -name Info.plist -print 2>/dev/null | head -1 || true)"
    if [[ -n "$app_info" ]]; then
      [[ -n "$source_version" ]] || source_version="$(plist_value "$app_info" ":CFBundleShortVersionString")"
      [[ -n "$source_build" ]] || source_build="$(plist_value "$app_info" ":CFBundleVersion")"
      [[ -n "$source_bundle_id" ]] || source_bundle_id="$(plist_value "$app_info" ":CFBundleIdentifier")"
      [[ -n "$source_project_name" ]] || source_project_name="$(plist_value "$app_info" ":CFBundleName")"
      [[ -n "$source_project_name" ]] || source_project_name="$(basename "$(dirname "$app_info")" .app)"
    fi
  fi

  apply_metadata_if_missing "$archive_path" "$source_version" "$source_build" "$source_bundle_id" "$source_project_name"
}

infer_ipa_metadata() {
  local ipa_path="$1"
  local info_entry=""
  local tmp_info="/tmp/xcode-release-ipa-info-$$.plist"
  local source_version="" source_build="" source_bundle_id="" source_project_name=""

  command -v unzip >/dev/null 2>&1 || err "unzip is required to infer metadata from --ipa-path"

  info_entry="$(unzip -Z1 "$ipa_path" 2>/dev/null | awk '$0 ~ "^Payload/[^/]+[.]app/Info[.]plist$" { print; exit }')"
  [[ -n "$info_entry" ]] || err "Could not find Payload/*.app/Info.plist in IPA: $ipa_path"

  unzip -p "$ipa_path" "$info_entry" > "$tmp_info"
  source_version="$(plist_value "$tmp_info" ":CFBundleShortVersionString")"
  source_build="$(plist_value "$tmp_info" ":CFBundleVersion")"
  source_bundle_id="$(plist_value "$tmp_info" ":CFBundleIdentifier")"
  source_project_name="$(plist_value "$tmp_info" ":CFBundleName")"
  [[ -n "$source_project_name" ]] || source_project_name="$(basename "$(dirname "$info_entry")" .app)"
  rm -f "$tmp_info"

  apply_metadata_if_missing "$ipa_path" "$source_version" "$source_build" "$source_bundle_id" "$source_project_name"
}

if [[ -n "$ARCHIVE_PATH_OVERRIDE" ]]; then
  ARCHIVE_PATH_OVERRIDE="$(absolutize_existing_dir "$ARCHIVE_PATH_OVERRIDE")"
  [[ "$ARCHIVE_PATH_OVERRIDE" == *.xcarchive ]] || err "--archive-path must point to a .xcarchive directory"
  infer_archive_metadata "$ARCHIVE_PATH_OVERRIDE"
fi

if [[ -n "$IPA_PATH" ]]; then
  IPA_PATH="$(absolutize_existing_file "$IPA_PATH")"
  [[ "$IPA_PATH" == *.ipa ]] || err "--ipa-path must point to a .ipa file"
  infer_ipa_metadata "$IPA_PATH"
fi

# ── platform parsing ──────────────────────────────────────────────────────────

PLATFORM_LIST=()

parse_platforms() {
  local raw_list="$1"
  local raw_platform cleaned
  local -a parsed=()

  IFS=',' read -r -a parsed <<< "$raw_list"
  [[ ${#parsed[@]} -gt 0 ]] || err "--platform must not be empty"

  local -a unique=()
  for raw_platform in "${parsed[@]+"${parsed[@]}"}"; do
    cleaned="$(echo "$raw_platform" | tr -d '[:space:]')"
    [[ -n "$cleaned" ]] || err "--platform contains an empty entry"
    case "$cleaned" in
      ios|macos|mac_catalyst) ;;
      *) err "--platform entries must be ios, macos, or mac_catalyst (got: $cleaned)" ;;
    esac

    local seen=0 existing
    for existing in "${unique[@]+"${unique[@]}"}"; do
      if [[ "$existing" == "$cleaned" ]]; then
        seen=1
        break
      fi
    done
    [[ $seen -eq 0 ]] || err "Duplicate platform in --platform list: $cleaned"
    unique+=("$cleaned")
  done

  PLATFORM_LIST=("${unique[@]}")
}

setup_platform_context() {
  local requested_platform="$1"
  PLATFORM_VARIANT="$requested_platform"
  EXTRA_XCODEBUILD_SETTING=""

  case "$requested_platform" in
    ios)
      DESTINATION="generic/platform=iOS"
      ;;
    macos)
      DESTINATION="generic/platform=macOS"
      ;;
    mac_catalyst)
      DESTINATION="generic/platform=iOS"
      EXTRA_XCODEBUILD_SETTING="SUPPORTS_MACCATALYST=YES"
      ;;
    *)
      err "Unsupported platform: $requested_platform"
      ;;
  esac
}

set_artifact_paths() {
  RUN_DIR="${HOME}/.xcode-archive/${PROJECT_NAME}/${VERSION}-${BUILD}"
  ARCHIVE_PATH="${RUN_DIR}/${PROJECT_NAME}-${PLATFORM_VARIANT}.xcarchive"
  DERIVED_DATA="${RUN_DIR}/DerivedData-${PLATFORM_VARIANT}"
  EXPORT_PATH="${RUN_DIR}/export-${PLATFORM_VARIANT}"
  LOGS_DIR="${RUN_DIR}/logs-${PLATFORM_VARIANT}"
  COMPLETE_MARKER="$(completion_marker_for_variant "$PLATFORM_VARIANT" "$UPLOAD_MODE")"
}

completion_marker_for_variant() {
  local variant="$1"
  local mode="${2:-$UPLOAD_MODE}"
  if [[ "$mode" == "testflight" ]]; then
    echo "${HOME}/.xcode-archive/${PROJECT_NAME}/${VERSION}-${BUILD}/.completed-${variant}"
  else
    echo "${HOME}/.xcode-archive/${PROJECT_NAME}/${VERSION}-${BUILD}/.completed-${variant}-${mode}"
  fi
}

parse_platforms "$PLATFORM"

if [[ -n "$ARCHIVE_PATH_OVERRIDE" || -n "$IPA_PATH" ]] && [[ ${#PLATFORM_LIST[@]} -gt 1 ]]; then
  err "Existing artifact inputs support a single --platform value only"
fi

if [[ "$UPLOAD_MODE" == "test-ipa" || "$UPLOAD_MODE" == "both" ]]; then
  local_bad_platform=""
  for platform_item in "${PLATFORM_LIST[@]+"${PLATFORM_LIST[@]}"}"; do
    if [[ "$platform_item" != "ios" ]]; then
      local_bad_platform="$platform_item"
      break
    fi
  done
  [[ -z "$local_bad_platform" ]] || err "--upload-mode $UPLOAD_MODE supports ios only because ipa-server accepts .ipa artifacts"
fi

# Infer version/build: git tag on HEAD → archive history → error
if [[ -z "$VERSION" && -z "$ARCHIVE_PATH_OVERRIDE" && -z "$IPA_PATH" ]]; then
  if infer_from_tag "$PROJECT_DIR"; then
    :
  elif infer_from_archives; then
    :
  else
    err "Could not infer version/build: no parseable git tag on HEAD and no archive history found in ~/.xcode-archive/${PROJECT_NAME}/. Provide --version and --build explicitly."
  fi
fi

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
  err "Could not resolve both version and build. Provide --version/--build explicitly or use an artifact with readable metadata."
fi

if [[ -z "$PROJECT_NAME" ]]; then
  err "Could not resolve project name. Pass --project-name, --project, or use an artifact with readable name metadata."
fi

if [[ ${#PLATFORM_LIST[@]} -eq 1 ]]; then
  PLATFORM="${PLATFORM_LIST[0]}"
  setup_platform_context "$PLATFORM"
  set_artifact_paths
  if [[ -n "$ARCHIVE_PATH_OVERRIDE" ]]; then
    ARCHIVE_PATH="$ARCHIVE_PATH_OVERRIDE"
  fi
else
  PLATFORM_VARIANT=""
  DESTINATION=""
  EXTRA_XCODEBUILD_SETTING=""
  RUN_DIR="${HOME}/.xcode-archive/${PROJECT_NAME}/${VERSION}-${BUILD}"
  ARCHIVE_PATH=""
  DERIVED_DATA=""
  EXPORT_PATH=""
  LOGS_DIR=""
  COMPLETE_MARKER=""
fi

# ── summaries ────────────────────────────────────────────────────────────────

print_single_platform_summary() {
  log "──────────────────────────────────────────"
  log "  Project : ${PROJECT:-<none>}"
  log "  Name    : $PROJECT_NAME"
  log "  Scheme  : $SCHEME"
  log "  Version : $VERSION ($BUILD)${TAG_SOURCE}"
  log "  Mode    : $UPLOAD_MODE"
  log "  Platform: $PLATFORM ($DESTINATION)"
  log "  Archive : $ARCHIVE_PATH"
  log "  Export  : $EXPORT_PATH"
  [[ -n "$IPA_PATH" ]] && log "  IPA     : $IPA_PATH"
  log "──────────────────────────────────────────"
}

print_batch_summary() {
  log "──────────────────────────────────────────"
  log "  Project   : ${PROJECT:-<none>}"
  log "  Name      : $PROJECT_NAME"
  log "  Scheme    : $SCHEME"
  log "  Version   : $VERSION ($BUILD)${TAG_SOURCE}"
  log "  Mode      : $UPLOAD_MODE"
  log "  Platforms : $PLATFORM"
  log "  Run dir   : $RUN_DIR"
  log "──────────────────────────────────────────"
}

# ── step 1: version bump ──────────────────────────────────────────────────────

bump_versions() {
  log "Bumping versions → $VERSION ($BUILD)…"

  local pbxproj="${PROJECT}/project.pbxproj"
  [[ -f "$pbxproj" ]] || err "project.pbxproj not found: $pbxproj"

  # Patch only the selected app project's pbxproj. Broad directory scans can hit
  # SwiftPM checkouts or generated build trees with read-only files.
  log "  Patching $pbxproj"
  sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = ${VERSION}/" "$pbxproj"
  sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = ${BUILD}/" "$pbxproj"

  # Patch only Info.plist files explicitly referenced by this project.
  local -a plists=()
  local raw_plist resolved_plist
  while IFS= read -r raw_plist; do
    [[ -z "$raw_plist" ]] && continue
    resolved_plist="$raw_plist"
    resolved_plist="${resolved_plist%\"}"
    resolved_plist="${resolved_plist#\"}"
    resolved_plist="${resolved_plist//\$(SRCROOT)/$PROJECT_DIR}"
    resolved_plist="${resolved_plist//\${SRCROOT}/$PROJECT_DIR}"
    resolved_plist="${resolved_plist//\$(PROJECT_DIR)/$PROJECT_DIR}"
    resolved_plist="${resolved_plist//\${PROJECT_DIR}/$PROJECT_DIR}"

    # Skip unresolved build-setting expressions instead of guessing.
    if [[ "$resolved_plist" == *'$('* || "$resolved_plist" == *'${'* ]]; then
      log "  Skipping unresolved Info.plist path: $raw_plist"
      continue
    fi

    if [[ "$resolved_plist" != /* ]]; then
      resolved_plist="${PROJECT_DIR}/${resolved_plist}"
    fi

    [[ -f "$resolved_plist" ]] || continue
    local seen=0
    local existing_plist
    for existing_plist in "${plists[@]+"${plists[@]}"}"; do
      if [[ "$existing_plist" == "$resolved_plist" ]]; then
        seen=1
        break
      fi
    done
    [[ $seen -eq 1 ]] || plists+=("$resolved_plist")
  done < <(
    grep -E 'INFOPLIST_FILE(\[[^]]+\])?[[:space:]]*=' "$pbxproj" \
      | sed -E 's/^[[:space:]]*INFOPLIST_FILE(\[[^]]+\])?[[:space:]]*=[[:space:]]*//; s/;[[:space:]]*$//'
  )

  local plist
  for plist in "${plists[@]+"${plists[@]}"}"; do
    if /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" &>/dev/null; then
      log "  Patching $plist"
      /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$plist"
      /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD}" "$plist"
    fi
  done

  log "Version bump complete."
}

# ── step 2: archive ───────────────────────────────────────────────────────────

run_archive() {
  log "Archiving ${PROJECT_NAME} (${SCHEME}) → ${DESTINATION}…"
  mkdir -p "$LOGS_DIR"
  local log_file="${LOGS_DIR}/archive.log"
  log "  Log: $log_file"

  local -a extra_settings=()
  [[ -n "$EXTRA_XCODEBUILD_SETTING" ]] && extra_settings+=("$EXTRA_XCODEBUILD_SETTING")

  xcodebuild \
    -project         "$PROJECT" \
    -scheme          "$SCHEME" \
    -destination     "$DESTINATION" \
    -configuration   Release \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath     "$ARCHIVE_PATH" \
    -skipMacroValidation \
    "${extra_settings[@]+"${extra_settings[@]}"}" \
    archive 2>&1 | tee "$log_file"

  # tee masks xcodebuild exit code; check PIPESTATUS explicitly
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { log "xcodebuild archive failed (see $log_file)"; return 1; }

  log "Archive complete: $ARCHIVE_PATH"
}

# ── step 3: export + upload ───────────────────────────────────────────────────

set_plist_string() {
  local plist="$1"
  local key="$2"
  local value="$3"

  if /usr/libexec/PlistBuddy -c "Print ${key}" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set ${key} ${value}" "$plist"
  else
    /usr/libexec/PlistBuddy -c "Add ${key} string ${value}" "$plist"
  fi
}

make_test_ipa_export_plist() {
  local source_plist="$1"
  local output_plist="$2"

  mkdir -p "$(dirname "$output_plist")"
  if [[ -n "$TEST_IPA_EXPORT_PLIST" ]]; then
    cp "$TEST_IPA_EXPORT_PLIST" "$output_plist"
  else
    cp "$source_plist" "$output_plist"
    set_plist_string "$output_plist" ":method" "$TEST_IPA_EXPORT_METHOD"
  fi

  set_plist_string "$output_plist" ":destination" "export"
  local method
  method="$(plist_value "$output_plist" ":method")"
  case "$method" in
    ad-hoc|development|enterprise) ;;
    *)
      err "Test IPA export plist must use a direct-install method (ad-hoc, development, or enterprise), got: ${method:-missing}"
      ;;
  esac
  echo "$output_plist"
}

find_exported_ipa() {
  local export_dir="$1"
  find "$export_dir" -maxdepth 2 -type f -name "*.ipa" -print 2>/dev/null | head -1
}

run_export_ipa() {
  log "Exporting IPA for ipa-server upload…"
  mkdir -p "$LOGS_DIR"
  local log_file="${LOGS_DIR}/test-ipa-export.log"
  local export_plist_for_ipa="${RUN_DIR}/ExportOptions-test-ipa-${PLATFORM_VARIANT}.plist"
  local ipa_export_plist
  ipa_export_plist="$(make_test_ipa_export_plist "$EXPORT_PLIST" "$export_plist_for_ipa")"
  log "  Log: $log_file"
  log "  Export method: $(plist_value "$ipa_export_plist" ":method")"

  xcodebuild \
    -exportArchive \
    -archivePath        "$ARCHIVE_PATH" \
    -exportPath         "$EXPORT_PATH" \
    -exportOptionsPlist "$ipa_export_plist" 2>&1 | tee "$log_file"

  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    log "IPA export failed (see $log_file)"
    return 1
  fi

  IPA_PATH="$(find_exported_ipa "$EXPORT_PATH")"
  [[ -n "$IPA_PATH" ]] || { log "IPA export succeeded but no .ipa was found in $EXPORT_PATH"; return 1; }
  log "IPA export complete: $IPA_PATH"
}

run_testflight_upload() {
  log "Exporting and uploading to App Store Connect…"
  mkdir -p "$LOGS_DIR"
  local log_file="${LOGS_DIR}/export.log"
  log "  Log: $log_file"

  xcodebuild \
    -exportArchive \
    -archivePath        "$ARCHIVE_PATH" \
    -exportPath         "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST" 2>&1 | tee "$log_file"

  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    if grep -q "No profiles for '" "$log_file"; then
      log "Automatic App Store export is blocked by missing distribution signing."
      open_archive_in_xcode "$ARCHIVE_PATH"
      log "Manual next step: in Xcode Organizer, select the archive and upload it to App Store Connect manually."
      log "See export log for details: $log_file"
      return 0
    fi
    log "xcodebuild export failed (see $log_file)"
    return 1
  fi

  log "Upload complete."
  UPLOAD_SUCCEEDED=1
  TESTFLIGHT_UPLOAD_SUCCEEDED=1
}

ensure_test_ipa_inputs() {
  [[ -n "$IPA_PATH" ]] || err "No IPA path is available for ipa-server upload"
  [[ -f "$IPA_PATH" ]] || err "IPA does not exist: $IPA_PATH"
  [[ -n "$IPA_SERVER" ]] || err "Missing ipa-server URL. Pass --ipa-server or set IPA_SERVER_URL."
  [[ -f "$IPA_SERVER_HELPER" ]] || err "ipa-server helper not found: $IPA_SERVER_HELPER"
  [[ -n "$VERSION" ]] || err "Missing version for ipa-server upload"
  [[ -n "$BUILD" ]] || err "Missing build number for ipa-server upload"
  [[ -n "$BUNDLE_ID" ]] || err "Missing bundle id for ipa-server upload. Pass --bundle-id or use an artifact with readable metadata."
}

run_test_ipa_upload() {
  ensure_test_ipa_inputs
  log "Uploading IPA to ipa-server…"
  mkdir -p "$LOGS_DIR"
  local log_file="${LOGS_DIR}/test-ipa-upload.log"
  log "  Log: $log_file"

  python3 "$IPA_SERVER_HELPER" \
    --server "$IPA_SERVER" \
    upload \
    --ipa "$IPA_PATH" \
    --project "$PROJECT_NAME" \
    --version "$VERSION" \
    --build-number "$BUILD" \
    --bundle-id "$BUNDLE_ID" 2>&1 | tee "$log_file"

  [[ ${PIPESTATUS[0]} -eq 0 ]] || { log "ipa-server upload failed (see $log_file)"; return 1; }

  TEST_IPA_UPLOAD_SUCCEEDED=1
  TEST_IPA_INSTALL_OUTPUT="$log_file"
  log "ipa-server upload complete."
}

complete_successful_run() {
  touch "$COMPLETE_MARKER"
  if [[ -n "$DERIVED_DATA" && -d "$DERIVED_DATA" ]]; then
    log ""
    log "Cleaning up DerivedData…"
    rm -rf "$DERIVED_DATA"
    log "DerivedData removed."
  fi
  log ""
  log "Artifacts saved to: $RUN_DIR"
}

run_tag_release() {
  TAG_NAME="$(release_tag_name)"
  TAG_REMOTE="$(resolve_push_remote)" || return 1

  log "Creating and pushing release tag ${TAG_NAME}…"

  if local_tag_exists "$TAG_NAME"; then
    log "Release tag already exists locally: ${TAG_NAME}"
    return 1
  fi

  local remote_check_status=0
  if remote_tag_exists "$TAG_REMOTE" "$TAG_NAME"; then
    log "Release tag already exists on remote '${TAG_REMOTE}': ${TAG_NAME}"
    return 1
  else
    remote_check_status=$?
  fi

  if [[ $remote_check_status -eq 2 ]]; then
    return 1
  fi

  git -C "$PROJECT_DIR" tag -a "$TAG_NAME" -m "Release ${VERSION} (${BUILD})"
  TAG_CREATED=1

  git -C "$PROJECT_DIR" push "$TAG_REMOTE" "$TAG_NAME"
  log "Release tag pushed: ${TAG_NAME} -> ${TAG_REMOTE}"
}

# ── execution ─────────────────────────────────────────────────────────────────

run_single_platform_flow() {
  print_single_platform_summary
  mkdir -p "$RUN_DIR"
  local test_ipa_marker=""
  test_ipa_marker="$(completion_marker_for_variant "$PLATFORM_VARIANT" "test-ipa")"

  TAG_NAME=""
  TAG_REMOTE=""
  TAG_CREATED=0
  UPLOAD_SUCCEEDED=0
  TESTFLIGHT_UPLOAD_SUCCEEDED=0
  TEST_IPA_UPLOAD_SUCCEEDED=0

  if [[ $PREFLIGHT_ONLY -eq 1 ]]; then
    run_preflight
    return 0
  fi

  if [[ -f "$COMPLETE_MARKER" && $FORCE -eq 0 ]]; then
    log "Platform ${PLATFORM_VARIANT} already completed — skipping."
    return 0
  fi

  if [[ $FORCE -eq 1 ]]; then
    rm -f "$COMPLETE_MARKER"
    [[ "$UPLOAD_MODE" == "both" ]] && rm -f "$test_ipa_marker"
  fi

  if [[ -n "$IPA_PATH" ]]; then
    CURRENT_STEP="test-ipa-upload"
    run_test_ipa_upload
    complete_successful_run
    return 0
  fi

  if [[ -n "$ARCHIVE_PATH_OVERRIDE" ]]; then
    log "Using existing archive: $ARCHIVE_PATH"
    infer_archive_metadata "$ARCHIVE_PATH"
  elif [[ -d "$ARCHIVE_PATH" && $FORCE -eq 0 ]]; then
    log "Archive already exists — skipping version bump and archive step."
    log "  (Use --force to rebuild the archive.)"
    infer_archive_metadata "$ARCHIVE_PATH"
  else
    CURRENT_STEP="bump"
    bump_versions
    CURRENT_STEP="archive"
    run_archive
    infer_archive_metadata "$ARCHIVE_PATH"
  fi

  case "$UPLOAD_MODE" in
    testflight)
      CURRENT_STEP="export"
      run_testflight_upload
      ;;
    test-ipa)
      CURRENT_STEP="test-ipa-export"
      run_export_ipa
      infer_ipa_metadata "$IPA_PATH"
      CURRENT_STEP="test-ipa-upload"
      run_test_ipa_upload
      ;;
    both)
      if [[ -f "$test_ipa_marker" && $FORCE -eq 0 ]]; then
        log "ipa-server upload already completed for this version/build — skipping."
      else
        CURRENT_STEP="test-ipa-export"
        run_export_ipa
        infer_ipa_metadata "$IPA_PATH"
        CURRENT_STEP="test-ipa-upload"
        run_test_ipa_upload
        touch "$test_ipa_marker"
      fi
      CURRENT_STEP="export"
      run_testflight_upload
      ;;
  esac

  if [[ "$UPLOAD_MODE" != "test-ipa" && $TESTFLIGHT_UPLOAD_SUCCEEDED -ne 1 ]]; then
    log "Skipping release tag and completion marker because TestFlight upload did not complete automatically."
    return 0
  fi

  if [[ "$UPLOAD_MODE" != "test-ipa" && $TESTFLIGHT_UPLOAD_SUCCEEDED -eq 1 ]]; then
    CURRENT_STEP="tag"
    if [[ -z "$ARCHIVE_PATH_OVERRIDE" || $TAG_EXISTING_ARTIFACT -eq 1 ]]; then
      run_tag_release
    else
      log "Skipping release tag creation for --archive-path. Pass --tag-existing-artifact to tag the current HEAD anyway."
    fi
  fi

  complete_successful_run
}

run_batch_flow() {
  local script_self="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
  local bash_bin="${BASH:-bash}"
  local platform_item marker
  local successes=0 failures=0 skipped=0
  local -a summary_lines=()
  local -a child_cmd=()

  print_batch_summary
  mkdir -p "$RUN_DIR"

  for platform_item in "${PLATFORM_LIST[@]+"${PLATFORM_LIST[@]}"}"; do
    marker="$(completion_marker_for_variant "$platform_item")"

    if [[ $PREFLIGHT_ONLY -eq 0 && $FORCE -eq 0 && -f "$marker" ]]; then
      log "Skipping ${platform_item}: already completed."
      summary_lines+=("${platform_item}: skipped-existing")
      skipped=$(( skipped + 1 ))
      continue
    fi

    log ""
    log "=== Running platform: ${platform_item} ==="

    child_cmd=(
      "$bash_bin"
      "$script_self"
      --version "$VERSION"
      --build "$BUILD"
      --platform "$platform_item"
      --upload-mode "$UPLOAD_MODE"
    )
    [[ -n "$PROJECT" ]] && child_cmd+=(--project "$PROJECT")
    [[ -n "$SCHEME" ]] && child_cmd+=(--scheme "$SCHEME")
    [[ -n "$PROJECT_NAME" ]] && child_cmd+=(--project-name "$PROJECT_NAME")
    [[ -n "$EXPORT_PLIST" ]] && child_cmd+=(--export-plist "$EXPORT_PLIST")
    [[ -n "$BUNDLE_ID" ]] && child_cmd+=(--bundle-id "$BUNDLE_ID")
    [[ -n "$IPA_SERVER" ]] && child_cmd+=(--ipa-server "$IPA_SERVER")
    [[ -n "$IPA_SERVER_HELPER" ]] && child_cmd+=(--ipa-server-helper "$IPA_SERVER_HELPER")
    [[ $TAG_EXISTING_ARTIFACT -eq 1 ]] && child_cmd+=(--tag-existing-artifact)
    [[ $FORCE -eq 1 ]] && child_cmd+=(--force)
    [[ $PREFLIGHT_ONLY -eq 1 ]] && child_cmd+=(--preflight-only)

    if "${child_cmd[@]}"; then
      summary_lines+=("${platform_item}: success")
      successes=$(( successes + 1 ))
    else
      summary_lines+=("${platform_item}: failed")
      failures=$(( failures + 1 ))
    fi
  done

  log ""
  log "Batch summary:"
  local summary_line
  for summary_line in "${summary_lines[@]+"${summary_lines[@]}"}"; do
    log "  ${summary_line}"
  done
  log "Result: ${successes} succeeded, ${failures} failed, ${skipped} skipped-existing"

  [[ $failures -eq 0 ]]
}

if [[ ${#PLATFORM_LIST[@]} -gt 1 ]]; then
  if run_batch_flow; then
    exit 0
  fi
  exit 1
fi

run_single_platform_flow

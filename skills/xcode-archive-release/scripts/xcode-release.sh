#!/usr/bin/env bash
# xcode-release.sh — bump version, archive/upload with asc or IPA server, and tag App Store releases
# Usage:
#   xcode-release.sh --project Foo.xcodeproj --scheme FooScheme --app APP_ID \
#                    --bundle-id com.example.foo \
#                    [--version 2.1.0 --build 42]  # or infer from git tag on HEAD
#                    [--platform ios|macos|mac_catalyst[,ios|macos|mac_catalyst...]] \
#                    [--release-path direct_upload|publish|ipa_server] [--publish] \
#                    [--export-plist /path/to/ExportOptions.plist] \
#                    [--ipa-server-url https://ipa.example.com] \
#                    [--profile-type IOS_APP_STORE] [--skip-signing-refresh] \
#                    [--force] [--preflight-only]

set -Eeuo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") OPTIONS

Required:
  --project   <path>    Path to the .xcodeproj file
  --scheme    <name>    Xcode scheme to archive
  --app       <id>      App Store Connect app ID (or set ASC_APP_ID).
                        Required for direct_upload and publish; unused for ipa_server.

Signing refresh:
  --bundle-id <id>      Bundle identifier; required unless --skip-signing-refresh
  --profile-type <type> Provisioning profile type. Defaults by platform:
                         ios          -> IOS_APP_STORE
                         macos        -> MAC_APP_STORE
                         mac_catalyst -> MAC_CATALYST_APP_STORE
  --signing-output <dir> Directory for asc signing fetch output.
                         Default: <run-dir>/signing-<platform>
  --skip-signing-refresh Skip asc signing fetch/profile install
  --import-certificates  Import downloaded .cer files into login keychain

Version (provide both, or omit both to auto-infer):
  --version   <semver>  Marketing version, e.g. 2.1.0
  --build     <int>     Build number, e.g. 42

  When omitted, version/build are inferred in this order:
    1. Git tag on HEAD — must contain one semver + one integer component,
       separated by any of: - + / _  (e.g. v2.1.0-42  2.1.0+42)
    2. Archive history — scans ~/.xcode-archive/<project>/ for the folder
       with the highest build number; new build = max + 1.

Version bump (only with archive-history inference; cannot combine with --version/--build):
  --bumpPatch                   Increment patch: 2.1.4 -> 2.1.5
  --bumpMinor                   Increment minor, reset patch: 2.1.4 -> 2.2.0
  --bumpMajor                   Increment major, reset minor+patch: 2.1.4 -> 3.0.0

Release path:
  --release-path <mode>         direct_upload, publish, or ipa_server.
                                Default: direct_upload
  --publish                     Alias for --release-path publish

IPA server:
  --ipa-server-url <url>        Internal IPA server URL (or set IPA_SERVER_URL).
                                Required for --release-path ipa_server.
  --ipa-server-project <name>   Project name stored on IPA server.
                                Default: Xcode project name.
  --ipa-server-helper <path>    ipa-server-usage scripts/ipa_server.py path.
                                Defaults to IPA_SERVER_HELPER or installed skill lookup.
  --device-configuration <cfg>  Configuration for xcodebuildmcp device build.
                                Default: Debug

Optional:
  --platform  <list>            Comma-separated platforms in execution order.
                                Allowed values: ios, macos, mac_catalyst
                                Default: ios
  --export-plist <path>         Override the bundled direct-upload ExportOptions.plist
  --local-export-plist <path>   Override publish-mode local IPA ExportOptions.plist
  --force                       Re-archive even if an archive already exists
  --preflight-only              Validate setup without mutating files or building
  -h, --help                    Show this help
EOF
}

log()  { echo "[xcode-release] $*"; }
err()  { echo "[xcode-release] ERROR: $*" >&2; exit 1; }

TAG_NAME=""
TAG_REMOTE=""
TAG_CREATED=0
UPLOAD_SUCCEEDED=0
SIGNING_OUTPUT=""
SIGNING_OUTPUT_EXPLICIT=0
PROFILE_TYPE=""
PROFILE_TYPE_EXPLICIT=0
LOCAL_EXPORT_PLIST=""

build_retry_cmd() {
  RETRY_CMD="$(basename "$0") --project \"$PROJECT\" --scheme \"$SCHEME\" --version \"${VERSION:-?}\" --build \"${BUILD:-?}\" --platform \"${PLATFORM:-?}\" --release-path \"$RELEASE_PATH\""
  if [[ -n "$APP" ]]; then
    RETRY_CMD="${RETRY_CMD} --app \"$APP\""
  fi
  if [[ -n "$BUNDLE_ID" ]]; then
    RETRY_CMD="${RETRY_CMD} --bundle-id \"$BUNDLE_ID\""
  fi
  if [[ "$RELEASE_PATH" == "ipa_server" ]]; then
    RETRY_CMD="${RETRY_CMD} --ipa-server-url \"$IPA_SERVER_URL\" --ipa-server-project \"$IPA_SERVER_PROJECT\" --device-configuration \"$DEVICE_CONFIGURATION\""
    if [[ -n "$IPA_SERVER_HELPER" ]]; then
      RETRY_CMD="${RETRY_CMD} --ipa-server-helper \"$IPA_SERVER_HELPER\""
    fi
  fi
  if [[ -n "$EXPORT_PLIST" ]]; then
    RETRY_CMD="${RETRY_CMD} --export-plist \"$EXPORT_PLIST\""
  fi
  if [[ -n "$LOCAL_EXPORT_PLIST" ]]; then
    RETRY_CMD="${RETRY_CMD} --local-export-plist \"$LOCAL_EXPORT_PLIST\""
  fi
  if [[ $PROFILE_TYPE_EXPLICIT -eq 1 ]]; then
    RETRY_CMD="${RETRY_CMD} --profile-type \"$PROFILE_TYPE\""
  fi
  if [[ $SIGNING_OUTPUT_EXPLICIT -eq 1 ]]; then
    RETRY_CMD="${RETRY_CMD} --signing-output \"$SIGNING_OUTPUT\""
  fi
  if [[ $SKIP_SIGNING_REFRESH -eq 1 ]]; then
    RETRY_CMD="${RETRY_CMD} --skip-signing-refresh"
  fi
  if [[ $IMPORT_CERTIFICATES -eq 1 ]]; then
    RETRY_CMD="${RETRY_CMD} --import-certificates"
  fi
  if [[ $FORCE -eq 1 ]]; then
    RETRY_CMD="${RETRY_CMD} --force"
  fi
  if [[ $PREFLIGHT_ONLY -eq 1 ]]; then
    RETRY_CMD="${RETRY_CMD} --preflight-only"
  fi
}

release_tag_name() {
  echo "v${VERSION}-${BUILD}"
}

resolve_push_remote() {
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

run_logged() {
  local log_file="$1"
  shift

  mkdir -p "$(dirname "$log_file")"
  log "  Log: $log_file"
  log "  Command: $*"

  set +e
  "$@" 2>&1 | tee "$log_file"
  local status=${PIPESTATUS[0]}
  set -e

  return "$status"
}

PROJECT=""
SCHEME=""
APP="${ASC_APP_ID:-}"
BUNDLE_ID=""
VERSION=""
BUILD=""
BUMP=""
PLATFORM="ios"
RELEASE_PATH="direct_upload"
EXPORT_PLIST=""
FORCE=0
PREFLIGHT_ONLY=0
SKIP_SIGNING_REFRESH=0
IMPORT_CERTIFICATES=0
IPA_SERVER_URL="${IPA_SERVER_URL:-}"
IPA_SERVER_URL_EXPLICIT=0
IPA_SERVER_PROJECT=""
IPA_SERVER_HELPER="${IPA_SERVER_HELPER:-}"
DEVICE_CONFIGURATION="Debug"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)              PROJECT="$2"; shift 2 ;;
    --scheme)               SCHEME="$2"; shift 2 ;;
    --app)                  APP="$2"; shift 2 ;;
    --bundle-id)            BUNDLE_ID="$2"; shift 2 ;;
    --version)              VERSION="$2"; shift 2 ;;
    --build)                BUILD="$2"; shift 2 ;;
    --bumpPatch)            BUMP="patch"; shift ;;
    --bumpMinor)            BUMP="minor"; shift ;;
    --bumpMajor)            BUMP="major"; shift ;;
    --platform)             PLATFORM="$2"; shift 2 ;;
    --release-path)         RELEASE_PATH="$2"; shift 2 ;;
    --publish)              RELEASE_PATH="publish"; shift ;;
    --ipa-server-url)       IPA_SERVER_URL="$2"; IPA_SERVER_URL_EXPLICIT=1; shift 2 ;;
    --ipa-server-project)   IPA_SERVER_PROJECT="$2"; shift 2 ;;
    --ipa-server-helper)    IPA_SERVER_HELPER="$2"; shift 2 ;;
    --device-configuration) DEVICE_CONFIGURATION="$2"; shift 2 ;;
    --export-plist)         EXPORT_PLIST="$2"; shift 2 ;;
    --local-export-plist)   LOCAL_EXPORT_PLIST="$2"; shift 2 ;;
    --profile-type)         PROFILE_TYPE="$2"; PROFILE_TYPE_EXPLICIT=1; shift 2 ;;
    --signing-output)       SIGNING_OUTPUT="$2"; SIGNING_OUTPUT_EXPLICIT=1; shift 2 ;;
    --skip-signing-refresh) SKIP_SIGNING_REFRESH=1; shift ;;
    --import-certificates)  IMPORT_CERTIFICATES=1; shift ;;
    --force)                FORCE=1; shift ;;
    --preflight-only)       PREFLIGHT_ONLY=1; shift ;;
    -h|--help)              usage; exit 0 ;;
    *) err "Unknown argument: $1" ;;
  esac
done

[[ -n "$PROJECT" ]] || err "--project is required"
[[ -n "$SCHEME" ]] || err "--scheme is required"

case "$RELEASE_PATH" in
  direct_upload|publish|ipa_server) ;;
  *) err "--release-path must be direct_upload, publish, or ipa_server (got: $RELEASE_PATH)" ;;
esac

if [[ -n "$VERSION" && -z "$BUILD" ]] || [[ -z "$VERSION" && -n "$BUILD" ]]; then
  err "Provide both --version and --build, or omit both to auto-infer."
fi

if [[ -n "$BUMP" && ( -n "$VERSION" || -n "$BUILD" ) ]]; then
  err "--bump${BUMP^} cannot be combined with explicit --version/--build."
fi

[[ -d "$PROJECT" ]] || err "Project not found: $PROJECT"
PROJECT="$(cd "$PROJECT" && pwd)"
PROJECT_DIR="$(cd "$(dirname "$PROJECT")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT" .xcodeproj)"

find_project_env_file() {
  local dir="$PROJECT_DIR"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.env" ]]; then
      echo "$dir/.env"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

read_env_value() {
  local env_file="$1"
  local key="$2"
  python3 - "$env_file" "$key" <<'PY'
import re
import sys

path, key = sys.argv[1:]
pattern = re.compile(rf"^\s*{re.escape(key)}\s*=\s*(.*)\s*$")
with open(path, encoding="utf-8") as handle:
    for line in handle:
        match = pattern.match(line)
        if not match:
            continue
        value = match.group(1).strip()
        if value and value[0] in {"'", '"'} and value[-1:] == value[0]:
            value = value[1:-1]
        print(value)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

ENV_FILE=""
if ENV_FILE="$(find_project_env_file 2>/dev/null)"; then
  :
else
  ENV_FILE=""
fi

if [[ -z "$IPA_SERVER_URL" && -n "$ENV_FILE" ]]; then
  IPA_SERVER_URL="$(read_env_value "$ENV_FILE" IPA_SERVER_URL 2>/dev/null || true)"
fi

if [[ "$RELEASE_PATH" == "ipa_server" ]]; then
  [[ -n "$IPA_SERVER_URL" ]] || err "--ipa-server-url is required for --release-path ipa_server, or set IPA_SERVER_URL or project .env IPA_SERVER_URL"
  [[ -n "$BUNDLE_ID" ]] || err "--bundle-id is required for --release-path ipa_server"
else
  [[ -n "$APP" ]] || err "--app is required, or set ASC_APP_ID"
  if [[ $SKIP_SIGNING_REFRESH -eq 0 && -z "$BUNDLE_ID" ]]; then
    err "--bundle-id is required unless --skip-signing-refresh is set"
  fi
fi

TAG_SOURCE=""

infer_from_tag() {
  local project_dir="$1"
  local -a tags
  IFS=$'\n' read -r -d '' -a tags < <(git -C "$project_dir" tag --points-at HEAD 2>/dev/null && printf '\0') || true

  if [[ ${#tags[@]} -eq 0 ]]; then
    return 1
  fi

  local matched_tag="" matched_version="" matched_build=""

  for tag in "${tags[@]}"; do
    [[ -z "$tag" ]] && continue

    local stripped="${tag#[vV]}"
    local -a parts
    IFS=' ' read -r -a parts <<< "$(echo "$stripped" | sed 's/[-+\/_]/ /g')"

    local fv="" fb="" ok=1
    for part in "${parts[@]+"${parts[@]}"}"; do
      if [[ "$part" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        [[ -n "$fv" ]] && ok=0 && break
        fv="$part"
      elif [[ "$part" =~ ^[0-9]+$ ]]; then
        [[ -n "$fb" ]] && ok=0 && break
        fb="$part"
      else
        ok=0 && break
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
    TAG_SOURCE=" (from archive history: ${best_version}-${best_build} -> ${new_version}, build ${new_build})"
  else
    TAG_SOURCE=" (from archive history: ${best_version}-${best_build} -> build ${new_build})"
  fi
}

CURRENT_STEP="init"
RETRY_CMD=""

on_error() {
  echo ""
  log "──────────────────────────────────────────"
  log "FAILED at step: ${CURRENT_STEP}"
  local log_file=""
  case "$CURRENT_STEP" in
    signing) log_file="${LOGS_DIR:-}/signing.log" ;;
    device_build) log_file="${LOGS_DIR:-}/device-build.log" ;;
    package_ipa) log_file="${LOGS_DIR:-}/package-ipa.log" ;;
    archive) log_file="${LOGS_DIR:-}/archive.log" ;;
    export)  log_file="${LOGS_DIR:-}/export.log" ;;
    publish) log_file="${LOGS_DIR:-}/publish.log" ;;
    ipa_server_upload) log_file="${LOGS_DIR:-}/ipa-server-upload.log" ;;
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
      ASC_PLATFORM="IOS"
      DEFAULT_PROFILE_TYPE="IOS_APP_STORE"
      ;;
    macos)
      DESTINATION="generic/platform=macOS"
      ASC_PLATFORM="MAC_OS"
      DEFAULT_PROFILE_TYPE="MAC_APP_STORE"
      ;;
    mac_catalyst)
      DESTINATION="generic/platform=iOS"
      ASC_PLATFORM="MAC_OS"
      DEFAULT_PROFILE_TYPE="MAC_CATALYST_APP_STORE"
      EXTRA_XCODEBUILD_SETTING="SUPPORTS_MACCATALYST=YES"
      ;;
    *)
      err "Unsupported platform: $requested_platform"
      ;;
  esac

  if [[ $PROFILE_TYPE_EXPLICIT -eq 0 ]]; then
    PROFILE_TYPE="$DEFAULT_PROFILE_TYPE"
  fi
}

set_artifact_paths() {
  RUN_DIR="${HOME}/.xcode-archive/${PROJECT_NAME}/${VERSION}-${BUILD}"
  ARCHIVE_PATH="${RUN_DIR}/${PROJECT_NAME}-${PLATFORM_VARIANT}.xcarchive"
  DERIVED_DATA="${RUN_DIR}/DerivedData-${PLATFORM_VARIANT}"
  EXPORT_PATH="${RUN_DIR}/export-${PLATFORM_VARIANT}"
  IPA_PATH="${EXPORT_PATH}/${PROJECT_NAME}-${PLATFORM_VARIANT}.ipa"
  LOGS_DIR="${RUN_DIR}/logs-${PLATFORM_VARIANT}"
  COMPLETE_MARKER="${RUN_DIR}/.completed-${PLATFORM_VARIANT}"
  if [[ $SIGNING_OUTPUT_EXPLICIT -eq 0 ]]; then
    SIGNING_OUTPUT="${RUN_DIR}/signing-${PLATFORM_VARIANT}"
  fi
}

completion_marker_for_variant() {
  local variant="$1"
  echo "${HOME}/.xcode-archive/${PROJECT_NAME}/${VERSION}-${BUILD}/.completed-${variant}"
}

parse_platforms "$PLATFORM"

if [[ "$RELEASE_PATH" == "ipa_server" ]]; then
  if [[ ${#PLATFORM_LIST[@]} -ne 1 || "${PLATFORM_LIST[0]}" != "ios" ]]; then
    err "--release-path ipa_server supports only --platform ios"
  fi
  SKIP_SIGNING_REFRESH=1
  IPA_SERVER_PROJECT="${IPA_SERVER_PROJECT:-$PROJECT_NAME}"
fi

if [[ -z "$VERSION" ]]; then
  if infer_from_tag "$PROJECT_DIR"; then
    :
  elif infer_from_archives; then
    :
  else
    err "Could not infer version/build: no parseable git tag on HEAD and no archive history found in ~/.xcode-archive/${PROJECT_NAME}/. Provide --version and --build explicitly."
  fi
fi

if [[ ${#PLATFORM_LIST[@]} -eq 1 ]]; then
  PLATFORM="${PLATFORM_LIST[0]}"
  setup_platform_context "$PLATFORM"
  set_artifact_paths
else
  PLATFORM_VARIANT=""
  DESTINATION=""
  ASC_PLATFORM=""
  EXTRA_XCODEBUILD_SETTING=""
  RUN_DIR="${HOME}/.xcode-archive/${PROJECT_NAME}/${VERSION}-${BUILD}"
  ARCHIVE_PATH=""
  DERIVED_DATA=""
  EXPORT_PATH=""
  IPA_PATH=""
  LOGS_DIR=""
  COMPLETE_MARKER=""
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PLIST="${SCRIPT_DIR}/../assets/ExportOptions-AppStore.plist"
DEFAULT_LOCAL_PLIST="${SCRIPT_DIR}/../assets/ExportOptions-AppStore-Local.plist"
EXPORT_PLIST="${EXPORT_PLIST:-$DEFAULT_PLIST}"
LOCAL_EXPORT_PLIST="${LOCAL_EXPORT_PLIST:-$DEFAULT_LOCAL_PLIST}"

if [[ "$RELEASE_PATH" != "ipa_server" ]]; then
  [[ -f "$EXPORT_PLIST" ]] || err "ExportOptions.plist not found: $EXPORT_PLIST"
  [[ -f "$LOCAL_EXPORT_PLIST" ]] || err "Local ExportOptions.plist not found: $LOCAL_EXPORT_PLIST"
fi

print_single_platform_summary() {
  log "──────────────────────────────────────────"
  log "  Project      : $PROJECT"
  log "  Scheme       : $SCHEME"
  log "  App          : ${APP:-<not used>}"
  log "  Bundle ID    : ${BUNDLE_ID:-<signing refresh skipped>}"
  log "  Version      : $VERSION ($BUILD)${TAG_SOURCE}"
  log "  Release path : $RELEASE_PATH"
  log "  Platform     : $PLATFORM ($DESTINATION / $ASC_PLATFORM)"
  log "  Profile type : ${PROFILE_TYPE:-<none>}"
  if [[ "$RELEASE_PATH" == "ipa_server" ]]; then
    log "  IPA server   : $IPA_SERVER_URL"
    log "  IPA project  : $IPA_SERVER_PROJECT"
    log "  Configuration: $DEVICE_CONFIGURATION"
  fi
  log "  Archive      : ${ARCHIVE_PATH:-<not used>}"
  log "  IPA path     : $IPA_PATH"
  log "  Export       : $EXPORT_PATH"
  log "──────────────────────────────────────────"
}

print_batch_summary() {
  log "──────────────────────────────────────────"
  log "  Project      : $PROJECT"
  log "  Scheme       : $SCHEME"
  log "  App          : ${APP:-<not used>}"
  log "  Bundle ID    : ${BUNDLE_ID:-<signing refresh skipped>}"
  log "  Version      : $VERSION ($BUILD)${TAG_SOURCE}"
  log "  Release path : $RELEASE_PATH"
  log "  Platforms    : $PLATFORM"
  log "  Run dir      : $RUN_DIR"
  if [[ "$RELEASE_PATH" == "ipa_server" ]]; then
    log "  IPA server   : $IPA_SERVER_URL"
    log "  IPA project  : $IPA_SERVER_PROJECT"
    log "  Configuration: $DEVICE_CONFIGURATION"
  fi
  log "──────────────────────────────────────────"
}

bump_versions() {
  log "Bumping versions -> $VERSION ($BUILD)..."

  local pbxproj="${PROJECT}/project.pbxproj"
  [[ -f "$pbxproj" ]] || err "project.pbxproj not found: $pbxproj"

  log "  Patching $pbxproj"
  sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = ${VERSION}/" "$pbxproj"
  sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = ${BUILD}/" "$pbxproj"

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

run_preflight() {
  local ok=1
  log "Running preflight checks..."

  if [[ "$RELEASE_PATH" == "ipa_server" ]]; then
    log "  OK asc not required for ipa_server"
  elif command -v asc >/dev/null 2>&1; then
    log "  OK asc: $(asc version 2>/dev/null | head -1)"
  else
    log "  FAIL asc not found in PATH"; ok=0
  fi

  if command -v xcodebuildmcp >/dev/null 2>&1; then
    log "  OK xcodebuildmcp: $(xcodebuildmcp --version 2>/dev/null | head -1)"
  else
    log "  FAIL xcodebuildmcp not found in PATH"; ok=0
  fi

  if command -v python3 >/dev/null 2>&1; then
    log "  OK python3: $(python3 --version 2>/dev/null | head -1)"
  else
    log "  FAIL python3 not found in PATH"; ok=0
  fi

  if [[ -d "$PROJECT" ]]; then
    log "  OK Project: $PROJECT"
  else
    log "  FAIL Project not found: $PROJECT"; ok=0
  fi

  local schemes_output=""
  if schemes_output="$(xcodebuildmcp project-discovery list-schemes --project-path "$PROJECT" --output text 2>/dev/null)" && grep -qF "$SCHEME" <<< "$schemes_output"; then
    log "  OK Scheme: $SCHEME"
  else
    log "  FAIL Scheme '$SCHEME' not found via xcodebuildmcp project-discovery list-schemes"
    if [[ -n "$schemes_output" ]]; then
      printf '%s\n' "$schemes_output" | sed 's/^/      /'
    fi
    ok=0
  fi

  if [[ "$RELEASE_PATH" == "ipa_server" ]]; then
    if resolve_ipa_server_helper; then
      log "  OK IPA server helper: $IPA_SERVER_HELPER"
    else
      ok=0
    fi
    if python3 "$IPA_SERVER_HELPER" --server "$IPA_SERVER_URL" list --project "$IPA_SERVER_PROJECT" >/dev/null 2>&1; then
      log "  OK IPA server reachable: $IPA_SERVER_URL"
    else
      log "  FAIL IPA server not reachable: $IPA_SERVER_URL"; ok=0
    fi
  else
    if [[ -f "$EXPORT_PLIST" ]] && /usr/libexec/PlistBuddy -c "Print :method" "$EXPORT_PLIST" >/dev/null 2>&1; then
      log "  OK Direct upload ExportOptions.plist: $EXPORT_PLIST"
    else
      log "  FAIL ExportOptions.plist missing or invalid: $EXPORT_PLIST"; ok=0
    fi

    if [[ -f "$LOCAL_EXPORT_PLIST" ]] && /usr/libexec/PlistBuddy -c "Print :method" "$LOCAL_EXPORT_PLIST" >/dev/null 2>&1; then
      log "  OK Local ExportOptions.plist: $LOCAL_EXPORT_PLIST"
    else
      log "  FAIL Local ExportOptions.plist missing or invalid: $LOCAL_EXPORT_PLIST"; ok=0
    fi
  fi

  log "  OK Version: $VERSION, Build: $BUILD${TAG_SOURCE}"

  local archive_parent
  archive_parent="$(dirname "$RUN_DIR")"
  mkdir -p "$archive_parent" 2>/dev/null || true
  if [[ -w "$archive_parent" ]]; then
    log "  OK Output dir: $RUN_DIR"
  else
    log "  FAIL Cannot write to output dir: $archive_parent"; ok=0
  fi

  if [[ "$RELEASE_PATH" == "ipa_server" ]]; then
    log "  OK Signing: xcodebuildmcp device build with -allowProvisioningUpdates"
  elif [[ $SKIP_SIGNING_REFRESH -eq 0 ]]; then
    log "  OK Signing refresh: $BUNDLE_ID / $PROFILE_TYPE"
  else
    log "  OK Signing refresh skipped"
  fi

  if [[ $ok -eq 1 ]]; then
    log "Preflight passed. Ready to archive."
  else
    log "Preflight FAILED. Fix the issues above before archiving."
    exit 1
  fi
}

install_signing_profile_files() {
  local profile_dir="${HOME}/Library/MobileDevice/Provisioning Profiles"
  local -a profiles=()
  mkdir -p "$profile_dir"

  while IFS= read -r -d '' profile; do
    profiles+=("$profile")
  done < <(find "$SIGNING_OUTPUT" -maxdepth 1 -type f -name '*.mobileprovision' -print0 2>/dev/null)

  if [[ ${#profiles[@]} -eq 0 ]]; then
    err "asc signing fetch did not produce any .mobileprovision files in $SIGNING_OUTPUT"
  fi

  local profile
  for profile in "${profiles[@]+"${profiles[@]}"}"; do
    log "  Installing provisioning profile: $(basename "$profile")"
    cp "$profile" "$profile_dir/"
  done
}

import_certificate_files() {
  local -a certs=()
  while IFS= read -r -d '' cert; do
    certs+=("$cert")
  done < <(find "$SIGNING_OUTPUT" -maxdepth 1 -type f -name '*.cer' -print0 2>/dev/null)

  if [[ ${#certs[@]} -eq 0 ]]; then
    log "  No .cer files produced by asc signing fetch."
    return 0
  fi

  local keychain="${HOME}/Library/Keychains/login.keychain-db"
  local cert
  for cert in "${certs[@]+"${certs[@]}"}"; do
    log "  Importing certificate: $(basename "$cert")"
    security import "$cert" -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security
  done
}

assert_code_signing_identity() {
  local identities=""
  if ! identities="$(security find-identity -v -p codesigning 2>&1)"; then
    log "$identities"
    err "Could not inspect code signing identities with security find-identity."
  fi

  if ! grep -q '"' <<< "$identities"; then
    log "$identities"
    err "No usable code signing identity found. Install the distribution certificate with its private key, then retry. asc signing fetch downloads public .cer files and provisioning profiles; it cannot recreate a missing private key."
  fi
}

run_signing_refresh() {
  if [[ $SKIP_SIGNING_REFRESH -eq 1 ]]; then
    log "Signing refresh skipped."
    return 0
  fi

  log "Refreshing signing assets with asc..."
  mkdir -p "$SIGNING_OUTPUT"
  find "$SIGNING_OUTPUT" -maxdepth 1 \( -name '*.mobileprovision' -o -name '*.cer' \) -delete 2>/dev/null || true

  local -a cmd=(
    asc signing fetch
    --app "$APP"
    --bundle-id "$BUNDLE_ID"
    --profile-type "$PROFILE_TYPE"
    --create-missing
    --output "$SIGNING_OUTPUT"
    --format json
  )

  run_logged "$LOGS_DIR/signing.log" "${cmd[@]}" || return 1
  install_signing_profile_files
  if [[ $IMPORT_CERTIFICATES -eq 1 ]]; then
    import_certificate_files
  fi
  assert_code_signing_identity
}

resolve_ipa_server_helper() {
  if [[ -n "$IPA_SERVER_HELPER" ]]; then
    [[ -f "$IPA_SERVER_HELPER" ]] || err "IPA server helper not found: $IPA_SERVER_HELPER"
    return 0
  fi

  local -a candidates=(
    "${PROJECT_DIR}/skills/ipa-server-usage/scripts/ipa_server.py"
    "${SCRIPT_DIR}/../../ipa-server-usage/scripts/ipa_server.py"
  )

  if [[ -n "${CODEX_HOME:-}" ]]; then
    candidates+=("${CODEX_HOME}/skills/ipa-server-usage/scripts/ipa_server.py")
  fi

  if [[ -n "${AGENT_SKILLS_HOME:-}" ]]; then
    candidates+=("${AGENT_SKILLS_HOME}/ipa-server-usage/scripts/ipa_server.py")
  fi

  local candidate
  for candidate in "${candidates[@]+"${candidates[@]}"}"; do
    if [[ -f "$candidate" ]]; then
      IPA_SERVER_HELPER="$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
      return 0
    fi
  done

  err "ipa-server-usage helper not found. Install github.com/grepug/ipa-server skill or pass --ipa-server-helper /path/to/ipa_server.py."
}

write_device_build_json() {
  local json_path="$1"
  python3 - "$json_path" "$PROJECT" "$SCHEME" "$DEVICE_CONFIGURATION" "$DERIVED_DATA" <<'PY'
import json
import sys

path, project, scheme, configuration, derived_data = sys.argv[1:]
payload = {
    "projectPath": project,
    "scheme": scheme,
    "configuration": configuration,
    "derivedDataPath": derived_data,
    "extraArgs": ["-allowProvisioningUpdates"],
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY
}

run_device_build() {
  log "Building development device app with xcodebuildmcp..."
  mkdir -p "$LOGS_DIR" "$DERIVED_DATA"

  local json_path="${LOGS_DIR}/device-build.json"
  write_device_build_json "$json_path"

  local json_payload
  json_payload="$(cat "$json_path")"

  local -a cmd=(
    xcodebuildmcp device build
    --json "$json_payload"
    --output json
  )

  run_logged "$LOGS_DIR/device-build.log" "${cmd[@]}" || return 1
}

resolve_device_app_path() {
  log "Resolving built app path with xcodebuildmcp..."
  mkdir -p "$LOGS_DIR"

  local -a cmd=(
    xcodebuildmcp device get-app-path
    --project-path "$PROJECT"
    --scheme "$SCHEME"
    --configuration "$DEVICE_CONFIGURATION"
    --derived-data-path "$DERIVED_DATA"
    --output json
  )

  log "  Log: $LOGS_DIR/device-app-path.log"
  log "  Command: ${cmd[*]}"

  if ! "${cmd[@]}" > "$LOGS_DIR/device-app-path.log" 2>&1; then
    cat "$LOGS_DIR/device-app-path.log"
    return 1
  fi

  DEVICE_APP_PATH="$(python3 - "$LOGS_DIR/device-app-path.log" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
print(payload["data"]["artifacts"]["appPath"])
PY
)"

  [[ -d "$DEVICE_APP_PATH" ]] || err "Built app not found: $DEVICE_APP_PATH"
  log "  App path: $DEVICE_APP_PATH"
}

package_development_ipa() {
  log "Packaging development IPA..."
  mkdir -p "$LOGS_DIR" "$EXPORT_PATH"

  local package_root="${EXPORT_PATH}/package-root"
  local log_file="${LOGS_DIR}/package-ipa.log"
  rm -rf "$package_root" "$IPA_PATH"
  mkdir -p "$package_root/Payload"

  {
    echo "ditto $DEVICE_APP_PATH $package_root/Payload/${PROJECT_NAME}.app"
    ditto "$DEVICE_APP_PATH" "$package_root/Payload/${PROJECT_NAME}.app"
    echo "ditto -c -k --norsrc --noextattr --keepParent Payload $IPA_PATH"
    (cd "$package_root" && ditto -c -k --norsrc --noextattr --keepParent Payload "$IPA_PATH")
    echo "unzip -l $IPA_PATH"
    unzip -l "$IPA_PATH"
  } > "$log_file" 2>&1 || {
    cat "$log_file"
    return 1
  }

  if ! unzip -l "$IPA_PATH" | awk '{print $4}' | grep -Eq '^Payload/[^/]+\.app/embedded\.mobileprovision$'; then
    err "Packaged IPA is missing Payload/${PROJECT_NAME}.app/embedded.mobileprovision; OTA installation may fail."
  fi

  log "  Log: $log_file"
  log "  IPA: $IPA_PATH"
}

run_ipa_server_upload() {
  log "Uploading IPA to internal IPA server..."
  resolve_ipa_server_helper

  local -a cmd=(
    python3 "$IPA_SERVER_HELPER"
    --server "$IPA_SERVER_URL"
    upload
    --ipa "$IPA_PATH"
    --project "$IPA_SERVER_PROJECT"
    --version "$VERSION"
    --build-number "$BUILD"
    --bundle-id "$BUNDLE_ID"
  )

  run_logged "$LOGS_DIR/ipa-server-upload.log" "${cmd[@]}" || return 1
  UPLOAD_SUCCEEDED=1
  touch "$COMPLETE_MARKER"
  log "Artifacts saved to: $RUN_DIR"
}

run_archive() {
  log "Archiving ${PROJECT_NAME} (${SCHEME}) -> ${DESTINATION}..."
  mkdir -p "$LOGS_DIR"

  local -a cmd=(
    asc xcode archive
    --project "$PROJECT"
    --scheme "$SCHEME"
    --configuration Release
    --archive-path "$ARCHIVE_PATH"
    --xcodebuild-flag=-destination
    --xcodebuild-flag="$DESTINATION"
    --xcodebuild-flag=-derivedDataPath
    --xcodebuild-flag="$DERIVED_DATA"
    --xcodebuild-flag=-skipMacroValidation
    --xcodebuild-flag=-allowProvisioningUpdates
  )
  [[ -n "$EXTRA_XCODEBUILD_SETTING" ]] && cmd+=(--xcodebuild-flag="$EXTRA_XCODEBUILD_SETTING")
  [[ $FORCE -eq 1 ]] && cmd+=(--overwrite)

  run_logged "$LOGS_DIR/archive.log" "${cmd[@]}" || return 1
  log "Archive complete: $ARCHIVE_PATH"
}

copy_export_options() {
  local source_plist="$1"
  local target_name="$2"
  mkdir -p "$EXPORT_PATH"
  cp "$source_plist" "${EXPORT_PATH}/${target_name}"
}

run_export_direct_upload() {
  log "Exporting and uploading to App Store Connect with asc..."
  mkdir -p "$LOGS_DIR" "$EXPORT_PATH"
  copy_export_options "$EXPORT_PLIST" "ExportOptions.plist"

  local -a cmd=(
    asc xcode export
    --archive-path "$ARCHIVE_PATH"
    --export-options "$EXPORT_PLIST"
    --ipa-path "$IPA_PATH"
    --wait
    --xcodebuild-flag=-allowProvisioningUpdates
  )
  [[ $FORCE -eq 1 ]] && cmd+=(--overwrite)

  run_logged "$LOGS_DIR/export.log" "${cmd[@]}" || return 1
  UPLOAD_SUCCEEDED=1
  touch "$COMPLETE_MARKER"
  rm -rf "$DERIVED_DATA"
  log "Artifacts saved to: $RUN_DIR"
}

run_export_local_ipa() {
  log "Exporting local IPA with asc..."
  mkdir -p "$LOGS_DIR" "$EXPORT_PATH"
  copy_export_options "$LOCAL_EXPORT_PLIST" "ExportOptions-Local.plist"

  local -a cmd=(
    asc xcode export
    --archive-path "$ARCHIVE_PATH"
    --export-options "$LOCAL_EXPORT_PLIST"
    --ipa-path "$IPA_PATH"
    --xcodebuild-flag=-allowProvisioningUpdates
  )
  [[ $FORCE -eq 1 ]] && cmd+=(--overwrite)

  run_logged "$LOGS_DIR/export.log" "${cmd[@]}" || return 1
}

run_publish_appstore() {
  log "Publishing local IPA to App Store Connect with asc..."
  local -a cmd=(
    asc publish appstore
    --app "$APP"
    --ipa "$IPA_PATH"
    --version "$VERSION"
    --build-number "$BUILD"
    --platform "$ASC_PLATFORM"
    --wait
  )

  run_logged "$LOGS_DIR/publish.log" "${cmd[@]}" || return 1
  UPLOAD_SUCCEEDED=1
  touch "$COMPLETE_MARKER"
  rm -rf "$DERIVED_DATA"
  log "Artifacts saved to: $RUN_DIR"
}

run_tag_release() {
  TAG_NAME="$(release_tag_name)"
  TAG_REMOTE="$(resolve_push_remote)" || return 1

  log "Creating and pushing release tag ${TAG_NAME}..."

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

run_single_platform_flow() {
  print_single_platform_summary
  mkdir -p "$RUN_DIR"

  TAG_NAME=""
  TAG_REMOTE=""
  TAG_CREATED=0
  UPLOAD_SUCCEEDED=0

  if [[ $PREFLIGHT_ONLY -eq 1 ]]; then
    run_preflight
    return 0
  fi

  if [[ -f "$COMPLETE_MARKER" && $FORCE -eq 0 ]]; then
    log "Platform ${PLATFORM_VARIANT} already completed; skipping."
    return 0
  fi

  if [[ $FORCE -eq 1 ]]; then
    rm -f "$COMPLETE_MARKER"
  fi

  if [[ "$RELEASE_PATH" == "ipa_server" ]]; then
    if [[ -f "$IPA_PATH" && $FORCE -eq 0 ]]; then
      log "IPA already exists; skipping version bump, build, and package steps."
      log "  Use --force to rebuild the development IPA."
    else
      CURRENT_STEP="bump"
      bump_versions
      CURRENT_STEP="device_build"
      run_device_build
      CURRENT_STEP="package_ipa"
      resolve_device_app_path
      package_development_ipa
    fi

    CURRENT_STEP="ipa_server_upload"
    run_ipa_server_upload
    log "Skipping release tag creation for ipa_server path."
    return 0
  fi

  CURRENT_STEP="signing"
  run_signing_refresh

  if [[ -d "$ARCHIVE_PATH" && $FORCE -eq 0 ]]; then
    log "Archive already exists; skipping version bump and archive step."
    log "  Use --force to refresh signing and rebuild the archive."
  else
    CURRENT_STEP="bump"
    bump_versions
    CURRENT_STEP="archive"
    run_archive
  fi

  CURRENT_STEP="export"
  if [[ "$RELEASE_PATH" == "direct_upload" ]]; then
    run_export_direct_upload
  else
    run_export_local_ipa
    CURRENT_STEP="publish"
    run_publish_appstore
  fi

  if [[ $UPLOAD_SUCCEEDED -eq 1 ]]; then
    CURRENT_STEP="tag"
    run_tag_release
  else
    log "Skipping release tag creation because upload did not complete."
  fi
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
      --project "$PROJECT"
      --scheme "$SCHEME"
      --version "$VERSION"
      --build "$BUILD"
      --platform "$platform_item"
      --release-path "$RELEASE_PATH"
    )
    [[ -n "$APP" ]] && child_cmd+=(--app "$APP")
    [[ -n "$BUNDLE_ID" ]] && child_cmd+=(--bundle-id "$BUNDLE_ID")
    if [[ "$RELEASE_PATH" == "ipa_server" ]]; then
      child_cmd+=(--ipa-server-url "$IPA_SERVER_URL")
      child_cmd+=(--ipa-server-project "$IPA_SERVER_PROJECT")
      child_cmd+=(--device-configuration "$DEVICE_CONFIGURATION")
      [[ -n "$IPA_SERVER_HELPER" ]] && child_cmd+=(--ipa-server-helper "$IPA_SERVER_HELPER")
    fi
    [[ -n "$EXPORT_PLIST" ]] && child_cmd+=(--export-plist "$EXPORT_PLIST")
    [[ -n "$LOCAL_EXPORT_PLIST" ]] && child_cmd+=(--local-export-plist "$LOCAL_EXPORT_PLIST")
    [[ $PROFILE_TYPE_EXPLICIT -eq 1 ]] && child_cmd+=(--profile-type "$PROFILE_TYPE")
    [[ $SIGNING_OUTPUT_EXPLICIT -eq 1 ]] && child_cmd+=(--signing-output "$SIGNING_OUTPUT")
    [[ $SKIP_SIGNING_REFRESH -eq 1 ]] && child_cmd+=(--skip-signing-refresh)
    [[ $IMPORT_CERTIFICATES -eq 1 ]] && child_cmd+=(--import-certificates)
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

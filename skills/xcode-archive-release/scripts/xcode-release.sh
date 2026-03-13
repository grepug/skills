#!/usr/bin/env bash
# xcode-release.sh — bump version, archive, and upload to App Store Connect
# Usage:
#   xcode-release.sh --project Foo.xcodeproj --scheme FooScheme \
#                    [--version 2.1.0 --build 42]  # or infer from git tag on HEAD
#                    [--platform ios|macos] [--catalyst] \
#                    [--export-plist /path/to/ExportOptions.plist] \
#                    [--force] [--preflight-only]

set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $(basename "$0") OPTIONS

Required:
  --project   <path>    Path to the .xcodeproj file
  --scheme    <name>    Xcode scheme to archive

Version (provide both, or omit both to auto-infer):
  --version   <semver>  Marketing version, e.g. 2.1.0
  --build     <int>     Build number, e.g. 42

  When omitted, version/build are inferred in this order:
    1. Git tag on HEAD — must contain one semver + one integer component,
       separated by any of: - + / _  (e.g. v2.1.0-42  2.1.0+42)
    2. Archive history — scans ~/.xcode-archive/<project>/ for the folder
       with the highest build number; new build = max + 1.

Version bump (only with archive-history inference; cannot combine with --version/--build):
  --bumpPatch                   Increment patch: 2.1.4 → 2.1.5
  --bumpMinor                   Increment minor, reset patch: 2.1.4 → 2.2.0
  --bumpMajor                   Increment major, reset minor+patch: 2.1.4 → 3.0.0

Optional:
  --platform  ios|macos         Archive destination (default: ios)
  --catalyst                    Pass SUPPORTS_MACCATALYST=YES to xcodebuild
  --export-plist  <path>        Override the bundled ExportOptions.plist
  --force                       Re-archive even if an archive already exists
  --preflight-only              Validate setup (scheme, plist, paths) without
                                mutating files or building anything
  -h, --help                    Show this help
EOF
}

log()  { echo "[xcode-release] $*"; }
err()  { echo "[xcode-release] ERROR: $*" >&2; exit 1; }

open_archive_in_xcode() {
  local archive_path="$1"
  if [[ -d "$archive_path" ]]; then
    log "Opening archive in Xcode Organizer for manual upload…"
    open -a Xcode "$archive_path" >/dev/null 2>&1 || true
  fi
}

# ── argument parsing ─────────────────────────────────────────────────────────

PROJECT=""
SCHEME=""
VERSION=""
BUILD=""
BUMP=""     # patch | minor | major | ""
PLATFORM="ios"
CATALYST=0
EXPORT_PLIST=""
FORCE=0
PREFLIGHT_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)        PROJECT="$2";      shift 2 ;;
    --scheme)         SCHEME="$2";       shift 2 ;;
    --version)        VERSION="$2";      shift 2 ;;
    --build)          BUILD="$2";        shift 2 ;;
    --bumpPatch)      BUMP="patch";      shift   ;;
    --bumpMinor)      BUMP="minor";      shift   ;;
    --bumpMajor)      BUMP="major";      shift   ;;
    --platform)       PLATFORM="$2";     shift 2 ;;
    --catalyst)       CATALYST=1;        shift   ;;
    --export-plist)   EXPORT_PLIST="$2"; shift 2 ;;
    --force)          FORCE=1;           shift   ;;
    --preflight-only) PREFLIGHT_ONLY=1;  shift   ;;
    -h|--help)        usage; exit 0 ;;
    *) err "Unknown argument: $1" ;;
  esac
done

# ── validate required args ────────────────────────────────────────────────────

[[ -n "$PROJECT" ]]  || err "--project is required"
[[ -n "$SCHEME" ]]   || err "--scheme is required"

# version/build: must be both-or-neither
if [[ -n "$VERSION" && -z "$BUILD" ]] || [[ -z "$VERSION" && -n "$BUILD" ]]; then
  err "Provide both --version and --build, or omit both to auto-infer."
fi

# --bump* flags are only valid when version/build are inferred, not explicit
if [[ -n "$BUMP" && ( -n "$VERSION" || -n "$BUILD" ) ]]; then
  err "--bump${BUMP^} cannot be combined with explicit --version/--build."
fi

[[ -d "$PROJECT" ]]  || err "Project not found: $PROJECT"

case "$PLATFORM" in
  ios)   DESTINATION="generic/platform=iOS"   ;;
  macos) DESTINATION="generic/platform=macOS" ;;
  *)     err "--platform must be 'ios' or 'macos' (got: $PLATFORM)" ;;
esac

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

on_error() {
  echo ""
  log "──────────────────────────────────────────"
  log "✗ FAILED at step: ${CURRENT_STEP}"
  local log_file=""
  case "$CURRENT_STEP" in
    archive) log_file="${LOGS_DIR:-}/archive.log" ;;
    export)  log_file="${LOGS_DIR:-}/export.log"  ;;
  esac
  if [[ -n "$log_file" && -f "$log_file" ]]; then
    log "  Log: $log_file"
    log "  Tail:"
    tail -20 "$log_file" | sed 's/^/    /'
  fi
  log "  Retry command:"
  # shellcheck disable=SC2153
  log "    $(basename "$0") --project \"${PROJECT}\" --scheme \"${SCHEME}\" --version \"${VERSION:-?}\" --build \"${BUILD:-?}\""
  log "──────────────────────────────────────────"
}

trap 'on_error' ERR

# ── preflight checks ──────────────────────────────────────────────────────────

run_preflight() {
  local ok=1
  log "Running preflight checks…"

  # 1. xcodebuild available
  if command -v xcodebuild &>/dev/null; then
    log "  ✓ xcodebuild: $(xcodebuild -version 2>/dev/null | head -1)"
  else
    log "  ✗ xcodebuild not found in PATH"; ok=0
  fi

  # 2. Project directory exists
  if [[ -d "$PROJECT" ]]; then
    log "  ✓ Project: $PROJECT"
  else
    log "  ✗ Project not found: $PROJECT"; ok=0
  fi

  # 3. Scheme exists in project
  if xcodebuild -project "$PROJECT" -list 2>/dev/null | grep -qF "    $SCHEME"; then
    log "  ✓ Scheme: $SCHEME"
  else
    log "  ✗ Scheme '$SCHEME' not found. Available schemes:"
    xcodebuild -project "$PROJECT" -list 2>/dev/null \
      | awk '/Schemes:/,0' | tail -n +2 | grep -v '^$' | head -20 | sed 's/^/      /'
    ok=0
  fi

  # 4. Export plist valid
  if [[ -f "$EXPORT_PLIST" ]] && /usr/libexec/PlistBuddy -c "Print :method" "$EXPORT_PLIST" &>/dev/null; then
    log "  ✓ ExportOptions.plist: $EXPORT_PLIST"
  else
    log "  ✗ ExportOptions.plist missing or invalid: $EXPORT_PLIST"; ok=0
  fi

  # 5. Version + build resolved
  log "  ✓ Version: $VERSION, Build: $BUILD${TAG_SOURCE}"

  # 6. Output dir writable
  local archive_parent
  archive_parent="$(dirname "$RUN_DIR")"
  mkdir -p "$archive_parent" 2>/dev/null || true
  if [[ -w "$archive_parent" ]]; then
    log "  ✓ Output dir: $RUN_DIR"
  else
    log "  ✗ Cannot write to output dir: $archive_parent"; ok=0
  fi

  if [[ $ok -eq 1 ]]; then
    log "Preflight passed. Ready to archive."
  else
    log "Preflight FAILED. Fix the issues above before archiving."
    exit 1
  fi
}

# ── resolve paths ─────────────────────────────────────────────────────────────

PROJECT_DIR="$(dirname "$PROJECT")"
PROJECT_NAME="$(basename "$PROJECT" .xcodeproj)"

# Infer version/build: git tag on HEAD → archive history → error
if [[ -z "$VERSION" ]]; then
  if infer_from_tag "$PROJECT_DIR"; then
    :
  elif infer_from_archives; then
    :
  else
    err "Could not infer version/build: no parseable git tag on HEAD and no archive history found in ~/.xcode-archive/${PROJECT_NAME}/. Provide --version and --build explicitly."
  fi
fi
RUN_DIR="${HOME}/.xcode-archive/${PROJECT_NAME}/${VERSION}-${BUILD}"
ARCHIVE_PATH="${RUN_DIR}/${PROJECT_NAME}.xcarchive"
DERIVED_DATA="${RUN_DIR}/DerivedData"
EXPORT_PATH="${RUN_DIR}/export"
LOGS_DIR="${RUN_DIR}/logs"

# Bundled ExportOptions plist is next to this script in ../assets/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PLIST="${SCRIPT_DIR}/../assets/ExportOptions-AppStore.plist"
EXPORT_PLIST="${EXPORT_PLIST:-$DEFAULT_PLIST}"

[[ -f "$EXPORT_PLIST" ]] || err "ExportOptions.plist not found: $EXPORT_PLIST"

# ── dry-run summary ───────────────────────────────────────────────────────────

log "──────────────────────────────────────────"
log "  Project : $PROJECT"
log "  Scheme  : $SCHEME"
log "  Version : $VERSION ($BUILD)${TAG_SOURCE}"
log "  Platform: $PLATFORM ($DESTINATION)"
log "  Catalyst: $([ $CATALYST -eq 1 ] && echo yes || echo no)"
log "  Archive : $ARCHIVE_PATH"
log "  Export  : $EXPORT_PATH"
log "──────────────────────────────────────────"

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
    plists+=("$resolved_plist")
  done < <(
    grep -Eo 'INFOPLIST_FILE = [^;]+' "$pbxproj" \
      | sed -E 's/^INFOPLIST_FILE = //; s/[[:space:]]+$//' \
      | sort -u
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
  [[ $CATALYST -eq 1 ]] && extra_settings+=(SUPPORTS_MACCATALYST=YES)

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
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { log "xcodebuild archive failed (see $log_file)"; exit 1; }

  log "Archive complete: $ARCHIVE_PATH"
}

# ── step 3: export + upload ───────────────────────────────────────────────────

run_export_upload() {
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
    exit 1
  fi

  log "Upload complete."
  log ""
  log "Cleaning up DerivedData…"
  rm -rf "$DERIVED_DATA"
  log "DerivedData removed."
  log ""
  log "Artifacts saved to: $RUN_DIR"
}

# ── main flow ─────────────────────────────────────────────────────────────────

mkdir -p "$RUN_DIR"

# Preflight-only: validate everything and exit before touching source files
if [[ $PREFLIGHT_ONLY -eq 1 ]]; then
  run_preflight
  exit 0
fi

if [[ -d "$ARCHIVE_PATH" && $FORCE -eq 0 ]]; then
  log "Archive already exists — skipping version bump and archive step."
  log "  (Use --force to rebuild the archive.)"
else
  CURRENT_STEP="bump"
  bump_versions
  CURRENT_STEP="archive"
  run_archive
fi

CURRENT_STEP="export"
run_export_upload

# Xcode Release Tagging

**Date:** 2026-03-18
**Status:** Implemented
**Target path:** `skills/xcode-archive-release/`

Based on: `docs/superpowers/specs/2026-03-18-xcode-release-tagging-design.md`

---

## Context

`skills/xcode-archive-release/scripts/xcode-release.sh` currently resolves version/build metadata, archives the app, and uploads it to App Store Connect, but it does not produce a release tag after success. The approved design adds a post-upload git step so a successful release also creates and pushes `v<version>-<build>` on the current `HEAD`. The main risk is partial success: the upload can succeed while local tag creation or tag push fails, so the script and docs need to distinguish release state from git state clearly.

---

## Design

### Release Tag Helpers (`skills/xcode-archive-release/scripts/xcode-release.sh`)

```bash
release_tag_name() {
  echo "v${VERSION}-${BUILD}"
}

resolve_push_remote() {
  :
}

ensure_tag_absent() {
  local remote_name="$1"
  local tag_name="$2"
}
```

Add focused git helper functions near the existing shell helpers so the release script can:

- confirm it is running inside a git repository
- pick a push remote, preferring the current branch's upstream remote and falling back to `origin`
- compute the release tag name from already-resolved `VERSION` and `BUILD`
- reject duplicate local or remote tags before creating anything

> **Why helper functions not inline git commands:** the tagging logic has multiple failure branches, and isolating them keeps the main release flow readable and easier to audit.

**Flow:**

```text
run_tag_release():

1. verify current directory belongs to a git work tree
2. choose remote: branch upstream remote first, otherwise origin
3. set tag_name = "v${VERSION}-${BUILD}"
4. fail if local tag already exists
5. fail if remote tag already exists
6. create annotated tag on HEAD
7. push that exact tag to the selected remote
8. print success output with tag and remote name
```

---

### Post-Upload Tag Phase (`skills/xcode-archive-release/scripts/xcode-release.sh`)

```bash
run_tag_release() {
  local tag_name remote_name
  tag_name="$(release_tag_name)"
  remote_name="$(resolve_push_remote)"
}
```

Add a new release phase after `run_export_upload` succeeds. This phase is part of release completion, but it must not run in `--preflight-only`, and it must not run if export/upload failed or fell into a manual Organizer handoff.

The existing `run_export_upload` function should return success only when automatic upload fully succeeds. The new tagging step should run after that success path in `run_single_platform_flow`. For batch runs, each child platform invocation already executes the single-platform flow, so tagging behavior should remain consistent without special batch logic.

> **Why place tagging after upload instead of after archive:** the tag is meant to mark a completed App Store Connect upload, not merely a built archive.

**Flow:**

```text
run_single_platform_flow():

1. preflight branch returns early without tagging
2. version bump and archive run as they do today
3. export/upload runs
4. if export/upload succeeds, set CURRENT_STEP=tag
5. run_tag_release
6. exit success only if upload and tagging both succeed
```

---

### Partial-Success Error Reporting (`skills/xcode-archive-release/scripts/xcode-release.sh`)

```bash
TAG_NAME=""
TAG_REMOTE=""
TAG_CREATED=0
UPLOAD_SUCCEEDED=0
```

Track enough state to produce accurate error messages:

- whether upload succeeded
- which tag name was targeted
- which remote was selected
- whether the local tag was already created before push failed

Update `on_error()` so `CURRENT_STEP=tag` emits release-aware guidance:

- if upload succeeded and tag creation failed, say upload succeeded but no tag was created
- if upload succeeded and push failed after tag creation, say the tag exists locally and show the manual push command

> **Why explicit state flags instead of parsing logs:** the upload and git phases are separate concerns, and a few explicit flags are more reliable than inferring state from command output.

---

### Skill Documentation (`skills/xcode-archive-release/SKILL.md`)

```md
Release an Apple app by bumping version/build metadata, archiving with Xcode, exporting and uploading to App Store Connect, then tagging the release in git.
```

Update the skill text so it matches the new workflow:

- top-level summary mentions post-upload tag creation and push
- workflow gets a new step after upload for tagging
- success reporting mentions the created tag and remote push
- troubleshooting covers duplicate tag conflicts and tag-push failures
- note that the script tags the current `HEAD`; it does not create a commit for version/build edits

> **Why document the HEAD limitation directly:** without that note, users may assume the release tag points to a commit containing the version bump written during the script run, which is not guaranteed.

---

## Checklist

- [x] Add git tagging helpers and state tracking to `skills/xcode-archive-release/scripts/xcode-release.sh` (see §Release Tag Helpers)
- [x] Add post-upload tagging phase to `skills/xcode-archive-release/scripts/xcode-release.sh` (see §Post-Upload Tag Phase)
- [x] Add partial-success error handling and manual recovery messaging to `skills/xcode-archive-release/scripts/xcode-release.sh` (see §Partial-Success Error Reporting)
- [x] Update release workflow docs in `skills/xcode-archive-release/SKILL.md` (see §Skill Documentation)
- [x] Verify: `bash -n skills/xcode-archive-release/scripts/xcode-release.sh`
- [x] Verify: inspect `skills/xcode-archive-release/scripts/xcode-release.sh --help` output for consistency
- [x] Verify: review the updated `skills/xcode-archive-release/SKILL.md` for workflow and troubleshooting accuracy

## Tweaks

- Removed the older duplicate plan file `docs/superpowers/plans/2026-03-13-xcode-release-post-upload-tagging-plan.md` and kept the newer 2026-03-18 plan as the active record.
- Verified shell syntax with `bash -n`.
- Verified `--help` output and updated it to mention post-upload tag creation.
- Reviewed the updated skill documentation for workflow, HEAD-tagging limitation, and tag-specific troubleshooting coverage.

# Xcode Release Post-Upload Tagging Implementation Plan

Date: 2026-03-13
Spec: `docs/superpowers/specs/2026-03-13-xcode-release-post-upload-tagging-design.md`

## Outcome

Extend `xcode-archive-release` so that a successful App Store Connect upload is followed by:

1. annotated git tag creation using `v<version>-<build>`
2. immediate push of that tag to `origin`
3. hard failure if the tag already exists locally or remotely

## Complexity

Simple

The change is isolated to release automation and documentation, but it needs careful failure messaging because upload success and git failure can happen in separate phases.

## Implementation Steps

### 1. Inspect current release script behavior

Read:

- `skills/xcode-archive-release/scripts/xcode-release.sh`
- any helper assets or shell functions it depends on

Confirm:

- where version and build are finalized
- what exact condition currently counts as upload success
- how the script reports errors and exits

### 2. Add post-upload tagging phase

Update the script to add a new phase that runs only after upload success:

- build tag name as `v${VERSION}-${BUILD}`
- create an annotated tag message like `App Store upload succeeded for ${VERSION} (${BUILD})`
- push the tag to `origin`

This phase should happen after the upload command returns success, not after archive success.

### 3. Add duplicate-tag protection

Before creating the tag, check both:

- local tags
- remote `origin` tags

If the tag already exists in either place:

- print a clear error
- exit non-zero
- explicitly state that the upload already succeeded and only the tagging phase failed

### 4. Preserve partial-success clarity

Make failure output distinguish between:

- archive failure
- export/upload failure
- post-upload git tagging failure

This is important because the remediation differs. A tagging failure after upload success should not imply the binary was not uploaded.

### 5. Update skill documentation

Update `skills/xcode-archive-release/SKILL.md` to reflect the new behavior:

- success output now includes tag creation and push
- retry guidance should note that rerunning with the same version/build will fail once the tag exists
- troubleshooting should mention existing tag conflicts

### 6. Validate behavior

Run focused validation:

1. dry inspection of shell syntax
2. simulate local existing tag failure
3. simulate remote existing tag failure if practical
4. verify success-path command construction

If live upload validation is not practical, document that limitation and validate the shell logic separately.

## Expected File Changes

- `skills/xcode-archive-release/scripts/xcode-release.sh`
- `skills/xcode-archive-release/SKILL.md`

## Risks

- false success messaging if upload completion is detected in the wrong place
- remote tag existence checks adding network-related failure modes
- retrying an already uploaded build now failing earlier because the tag is the idempotency boundary

## Open Implementation Decisions

These can be resolved during implementation without changing the approved design:

- whether remote tag detection uses `git ls-remote --tags origin <tag>` or fetches tags first
- the exact wording of partial-success error messages
- whether to guard tagging behind a clean working tree check or rely on git tag behavior directly

## Verification Target

After implementation, a successful run should produce:

- uploaded archive/export as before
- annotated tag `v<version>-<build>`
- pushed remote tag on `origin`

And a duplicate tag should produce:

- non-zero exit
- explicit message that upload succeeded but tagging did not complete

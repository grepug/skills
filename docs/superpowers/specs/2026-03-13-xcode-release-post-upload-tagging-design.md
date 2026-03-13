# Xcode Release Post-Upload Tagging Design

Date: 2026-03-13
Topic: Post-upload git tagging for `xcode-archive-release`

## Goal

Define the release step that happens immediately after a successful App Store Connect upload in the `xcode-archive-release` workflow.

## Decision

After `xcode-release.sh` reports a successful upload to App Store Connect, the workflow must:

1. Create an annotated git tag for the current `HEAD`.
2. Name the tag with the uploaded version and build number in the format `v<version>-<build>`.
3. Push that tag to `origin` immediately.

Example:

- `v2.1.0-42`

Example commands:

```bash
git tag -a v2.1.0-42 -m "App Store upload succeeded for 2.1.0 (42)"
git push origin v2.1.0-42
```

## Scope

This design changes only the post-upload release policy.

It does not change:

- archive creation
- export behavior
- upload behavior
- version/build bumping
- tag-based version/build inference before release

## Rationale

The tag should act as a release receipt for a successfully uploaded build, not as an input to the upload process.

This keeps the workflow fast while preserving a reliable mapping between:

- the uploaded binary identity: version + build
- the source revision: current `HEAD`

The workflow intentionally does not wait for App Store Connect processing to complete. If Apple later rejects the build or processing fails, the remedy is to ship a new build number and create a new tag, not to rewrite history.

## Existing Tag Policy

If the target tag already exists locally or remotely, the workflow must fail.

The workflow must not:

- reuse the existing tag
- move the tag
- silently skip tagging

This preserves one-to-one release provenance. A version/build tag must refer to one exact uploaded artifact from one exact commit.

## User-Facing Behavior

On upload success, the tool should report:

- upload succeeded
- tag created
- tag pushed

If tag creation or push fails, the tool should report the failure clearly and stop.

## Error Handling

Failure cases that should stop the workflow:

- local tag already exists
- remote tag already exists
- `git tag -a` fails
- `git push origin <tag>` fails
- git working copy is not in a usable state for tagging

The error message should make clear whether the upload already succeeded and the failure happened only in the git tagging phase.

## Testing

Minimum validation for implementation:

1. Successful upload path creates and pushes the expected annotated tag.
2. Existing local tag causes a hard failure.
3. Existing remote tag causes a hard failure.
4. Push failure is reported after upload success with a clear partial-success message.

## Non-Goals

- waiting for App Store Connect processing
- deleting or rewriting tags
- auto-incrementing build numbers after post-upload failures
- creating GitHub releases or changelog entries

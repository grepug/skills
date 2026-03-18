# Xcode Release Tagging Design

Date: 2026-03-18
Topic: Add automatic release tag creation and push to the `xcode-archive-release` skill and script

## Goal

Extend the existing Xcode release workflow so a successful App Store Connect upload also creates and pushes a git release tag for the current `HEAD`.

The tag format is:

`v<version>-<build>`

Example:

`v2.1.0-42`

## Why

The current workflow can infer `version` and `build` from a git tag on `HEAD`, but it does not create a release tag itself. That leaves the release flow asymmetric:

- tags can start a release
- successful releases do not produce a matching tag automatically

Adding a post-upload tagging step makes the release process produce a consistent git artifact that records the uploaded build.

## Scope

In scope:

- update the skill documentation to include release tagging
- update the release script to create a tag after a successful upload
- push the created tag to the remote automatically
- add clear failure messages and troubleshooting guidance for tag-related failures

Out of scope:

- creating a git commit for the version/build bump
- force-updating existing release tags
- changing how version/build are inferred
- changing upload/export behavior

## Recommended Approach

Create and push the release tag only after export/upload succeeds.

This is the preferred approach because it preserves the meaning of the tag: the tag marks a build that was actually uploaded to App Store Connect, not merely attempted.

Rejected alternatives:

1. Tag before archive, push after success.
This leaves behind release-looking local tags for failed archives or failed uploads unless additional cleanup logic is added.

2. Tag and push before archive/upload.
This makes the remote tag unreliable as a release marker because the upload may still fail.

## User-Facing Behavior

After a successful export/upload, the script will:

1. derive the tag name from the resolved `VERSION` and `BUILD`
2. verify that the tag does not already exist locally
3. verify that the tag does not already exist on the remote
4. create an annotated git tag on the current `HEAD`
5. push that exact tag to the remote

The annotated tag message should be:

`Release <version> (<build>)`

Example:

`Release 2.1.0 (42)`

## Git Safety Rules

The tagging step must be strict and must not mutate existing release tags.

Rules:

- run only after export/upload reports success
- do not run during `--preflight-only`
- do not use force push
- fail if the target tag already exists locally
- fail if the target tag already exists on the remote
- fail if the script is not running inside a git repository
- fail if no usable remote is available for pushing the tag

The script should prefer the current branch's configured upstream remote. If no upstream remote is configured, it may fall back to `origin` if `origin` exists. If neither is available, the script should fail with a clear message.

## Failure Handling

The tagging step is part of release completion, but its failures need to distinguish between upload status and git status.

Cases:

1. Upload fails before tagging.
No tag is created. The script exits non-zero as it does today.

2. Upload succeeds, local tag creation fails.
The script exits non-zero and clearly states that the upload succeeded but the release tag was not created.

3. Upload succeeds, local tag is created, push fails.
The script exits non-zero and clearly states that the upload succeeded and the tag exists locally, but pushing the tag failed. It should print the manual recovery command.

4. Tag already exists locally or remotely.
The script exits non-zero before creating or pushing any new tag. Existing release tags are treated as immutable.

## Important Limitation

The requested behavior is to tag the current `HEAD`.

The release script currently updates version/build metadata in working tree files during the run, but it does not create a commit. That means the new tag points to whatever commit `HEAD` already references, not to a new commit created by the script.

This is acceptable for this change because the requested behavior is specifically to tag `HEAD`, but the limitation should be documented in the skill text so users understand that tagging does not commit the version bump automatically.

## Script Changes

File:

`skills/xcode-archive-release/scripts/xcode-release.sh`

Planned changes:

- add helpers to detect git repository context and select a push remote
- add a helper to compute the release tag name from `VERSION` and `BUILD`
- add a helper to check whether the tag exists locally
- add a helper to check whether the tag exists remotely
- add a new `run_tag_release` step after successful `run_export_upload`
- create an annotated tag with message `Release <version> (<build>)`
- push only the created tag to the selected remote
- emit clear success and failure messages
- print a manual recovery command when push fails after local tag creation

## Skill Documentation Changes

File:

`skills/xcode-archive-release/SKILL.md`

Planned changes:

- update the description to mention tag creation/push
- update the top-level summary of the workflow
- add a workflow step after upload for tag creation and push
- document tag format and when tagging happens
- document the `HEAD` limitation around uncommitted version bumps
- add troubleshooting entries for:
  - tag already exists locally
  - tag already exists on remote
  - tag push failed

## Verification Plan

Verification should cover:

- script help and normal path still work
- `--preflight-only` does not tag
- tagging occurs only after successful upload path
- local duplicate tag is rejected
- remote duplicate tag is rejected
- push failure prints a manual recovery command
- skill documentation reflects the new workflow accurately

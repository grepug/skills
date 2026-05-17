# GitHub Issue Workflow Release Milestones Design

Date: 2026-05-17
Topic: Refine milestone selection in `github-issue-workflow` so release-version milestones are selected deterministically from git tags and open GitHub milestones.

## Summary

Update `github-issue-workflow` so milestone selection treats version-like GitHub milestones as release milestones. Git tags represent released versions. Open version-like milestones greater than the greatest released tag represent planned release buckets. The workflow should select the lowest planned release milestone, because that is the next known release target.

The workflow must not guess whether the next release is patch, minor, or major when git tags exist but no greater open milestone exists. In that case it should block and ask the user or maintainer to choose or create the next release milestone, unless repo-local instructions explicitly define GitHub milestones as non-version planning buckets.

## Goals

- Make release milestone selection deterministic.
- Align issue milestones with version-style release planning.
- Preserve the repo's existing version naming style when it can be inferred.
- Default new repos with no tags and no milestones to `v1`.
- Add script support so agents can validate or select the release milestone instead of relying only on prose.
- Keep PR milestones inherited from linked issue milestones.

## Non-Goals

- Do not create guessed patch, minor, or major milestones when tags already exist.
- Do not force version milestones on repos that clearly use non-version milestone planning.
- Do not change label conventions, issue classes, canonical plan comments, or PR body structure except where milestone wording references them.
- Do not edit generated files.

## Terminology

Use **release milestone** consistently for a GitHub milestone that represents a planned release version.

Use **git tag version** for a version parsed from a git tag.

Use **planned release milestone** for an open release milestone whose normalized version is greater than the greatest git tag version.

## Version Normalization

Normalize version-like names for comparison while preserving their original display text when applying a milestone:

- `v1` compares as `1`
- `1` compares as `1`
- `v1.2` compares as `1.2`
- `1.2.0` compares as `1.2.0`
- `v1.2.3` compares as `1.2.3`

The implementation should support numeric dot-separated release versions with an optional leading `v`. Names that include non-version suffixes such as `v1.2-beta`, dates such as `2026-05`, or arbitrary labels such as `Q2` are not release milestones for this rule.

When comparing different version depths, compare missing segments as zero for ordering. For example, `v1`, `v1.0`, and `v1.0.0` sort equivalently. If two open milestones normalize to the same version, choose the one that matches the deterministic style rule below, then choose the milestone with the latest GitHub `updatedAt` value.

## Selection Rule

When creating or updating an execution issue:

1. Inspect git tags and open GitHub milestones.
2. Parse version-like git tags as released versions.
3. Parse open version-like milestones as release milestones.
4. If git tag versions exist:
   - find open release milestones greater than the greatest git tag version
   - select the lowest such milestone
   - if none exist and no explicit non-version milestone instruction applies, block and ask the user or maintainer to choose or create the next release milestone
5. If no git tag versions exist:
   - if open release milestones exist, select the lowest open release milestone
   - if no open milestones exist, create or use the first milestone using repo style, defaulting to `v1`
6. Use the existing due-date milestone rule only when one of these is true:
   - there are no version-like git tags and no version-like open milestones, but non-version open milestones exist
   - repo-local instructions explicitly say GitHub milestones are sprint, quarter, project, or other non-version planning buckets
7. When opening or updating a PR, inherit the milestone from the linked issue instead of selecting independently.

## First Milestone Style

The first milestone should preserve existing repo style with deterministic precedence:

1. If version-like git tags exist, use the leading-`v` style of the greatest git tag version. If several tags normalize to that same greatest version, prefer the tag spelling with a leading `v`, then lexical order.
2. If no version-like git tags exist but version-like milestones exist, use the leading-`v` style of the lowest open release milestone. If several milestones normalize to that same lowest version, prefer the milestone with the latest GitHub `updatedAt` value, then lexical order.
3. If there are no version-like tags and no version-like milestones, default to `v1`.

This style preservation applies only when no release milestone has already been selected. The workflow should never rename an existing milestone just to match style.

## Examples

| Git tags | Open milestones | Result | Reason |
| --- | --- | --- | --- |
| none | none | create or use `v1` | no release history or planning exists |
| none | `v0.1`, `v1` | use `v0.1` | first planned release milestone already exists |
| `v1.2.0` | `v1.3`, `v2` | use `v1.3` | lowest release milestone greater than latest tag |
| `v1.2.0` | `v1.2.1`, `v1.3` | use `v1.2.1` | patch milestone exists and is the next planned release |
| `v1.2.0` | `v1.1`, `v1.2` | block and ask | no open release milestone is greater than latest tag |
| `v1.2.0` | none | block and ask | workflow cannot infer patch, minor, or major |
| `1.2.0` | `1.3`, `2` | use `1.3` | preserves no-`v` existing style by using existing milestone text |
| `v1.2.0` | non-version milestone with nearest due date | block and ask | version tags show release planning, but no greater release milestone exists |
| `v1.2.0` plus repo docs say milestones are sprint buckets | non-version milestone with nearest due date | use due-date fallback | repo-local instructions override release milestone inference |
| none | non-version milestone with nearest due date | use due-date fallback | no version-like release planning signal exists |

## Script Support

Add script support so the rule is auditable and repeatable.

Preferred implementation: extend `skills/github-issue-workflow/scripts/issue_pr_closeout.py` only if the milestone logic remains compact. If the command would make the closeout helper too broad, add a separate helper such as `skills/github-issue-workflow/scripts/select_release_milestone.py`.

The helper should support at least two behaviors:

1. **Selection dry run**

   Print the selected release milestone and explain why it was selected.

   Example:

   ```text
   Selected milestone: v1.3
   Reason: latest git tag is v1.2.0; v1.3 is the lowest open milestone greater than it.
   ```

2. **Validation**

   Validate that a supplied issue milestone matches the selected release milestone. If it does not match, fail with a concrete blocker.

   Example:

   ```text
   Blocked: issue milestone v1.2 does not match the selected release milestone.
   Latest released tag: v1.2.0
   Expected milestone: v1.3
   ```

For the bootstrap case where there are no git tags and no milestones, the helper may create `v1` or the style-preserving first milestone only when the caller explicitly asks for mutation. Selection and validation modes should not mutate GitHub state by default.

## GitHub CLI Behavior

Use `gh` for GitHub milestone discovery and mutation:

- list open milestones for the target repo
- inspect issue milestone when validating an existing issue
- create the first milestone only in explicit mutation mode
- edit an issue milestone only in explicit mutation mode

For long issue or PR body text, keep using temporary files instead of passing long inline strings to CLI commands.

## Skill Text Updates

Update `skills/github-issue-workflow/SKILL.md`:

- replace the due-date-first milestone rule with the release milestone rule
- document due-date selection as a fallback for repos that do not use release milestones
- replace `create 1.0` with the style-preserving first milestone rule defaulting to `v1`
- keep PR milestone inheritance from linked issues
- update the later "Use milestones as the default planning bucket" paragraph to reference release milestones

Update issue templates:

- `assets/issue-templates/feature.yml`
- `assets/issue-templates/bug.yml`
- `assets/issue-templates/infra.yml`
- `assets/issue-templates/research.yml`

Each template should say to default to the release milestone selected by the skill milestone rule. Each should replace `1.0` with the first-milestone rule defaulting to `v1` when no tags and no milestones exist.

Update references only if they describe milestone selection or validation. The current closeout reference can remain mostly unchanged because PR closeout should still inherit the issue milestone.

## Error Handling

The helper should fail clearly when:

- git tags cannot be fetched
- GitHub milestones or issue metadata cannot be fetched
- the repo has git tag versions but no greater open release milestone and no explicit non-version milestone instruction
- the supplied issue milestone does not match the selected release milestone
- GitHub mutation was requested but the caller lacks permission

When blocking, the helper should print the next user-visible action, such as:

```text
Next step: create or choose the next release milestone, then re-run milestone validation.
```

## Testing

Add focused tests for pure milestone selection logic without requiring live GitHub access:

- no tags and no milestones defaults to `v1`
- no tags with open release milestones selects the lowest open release milestone
- latest tag with multiple greater milestones selects the lowest greater version
- latest tag with only older or equal milestones blocks
- latest tag with no milestones blocks
- existing no-`v` style is preserved for first milestone selection
- version-equivalent milestones use style and updated-time tie-breaks
- non-version milestones fall back to due date when no version-like tags or milestones exist, or when repo-local instructions explicitly define GitHub milestones as non-version planning buckets

If the helper shells out to `gh`, isolate GitHub command execution so tests can use fixture JSON instead of making network calls.

## Approval Gate

After this spec is reviewed, implementation should proceed in this order:

1. add pure milestone parsing and selection logic
2. add helper command or standalone helper script
3. update skill milestone documentation
4. update issue template milestone descriptions
5. add tests for selection and validation behavior
6. run the repo's relevant validation

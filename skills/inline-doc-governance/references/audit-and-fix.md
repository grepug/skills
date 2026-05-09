# Audit And Fix Workflow

Use this workflow whenever a repo needs inline documentation cleanup.

## 1. Run The Deterministic Audit

Whole repo:

```bash
python3 path/to/inline-doc-governance/scripts/audit_inline_docs.py --type-doc-policy public .
```

Narrow scope:

```bash
python3 path/to/inline-doc-governance/scripts/audit_inline_docs.py \
  --type-doc-policy public \
  src clients/apple/Packages/App/Sources
```

Strict repos:

```bash
python3 path/to/inline-doc-governance/scripts/audit_inline_docs.py --type-doc-policy all .
```

The script enforces only what it can prove reliably:

- file header present and not just a tool directive
- selected type docs present
- generated and vendor files excluded

## 2. Fix Hard Failures First

For every reported file:

- add a file header at the top, before imports
- add a doc immediately above each missing selected type declaration
- keep docs above decorators or attributes
- rerun the audit before spending time on body comments

Use `--fix` only for mechanical cleanup, such as moving an existing doc above decorators or attributes. The script intentionally does not generate placeholder documentation because those comments tend to restate symbol names instead of explaining intent.

Do not edit generated files. If a generated file is flagged, update the script exclusion rules or the repo's generator.

## 3. Do The Semantic Pass

After deterministic failures are fixed, review the changed or flagged files for comment quality the script cannot judge.

Look for:

- public functions and methods missing contract docs
- cross-module services, stores, adapters, coordinators, resolvers, and remote sources with weak docs
- ambiguous parameters or return values
- side effects such as network I/O, file I/O, persistence, logging, caching, retries, or state mutation
- timeout, ordering, fallback, compatibility, normalization, provider-quirk, or boundary decisions without a local why-comment

Skip:

- obvious property assignments
- tiny helpers whose names fully explain behavior
- comments that paraphrase the code
- generated, vendored, build-output, or dependency files

## 4. Rerun The Audit

Run the same deterministic command again after patching.

The intended loop is:

1. audit
2. fix deterministic failures
3. semantic review
4. audit again

## 5. Report The Outcome

Summarize:

- deterministic issues fixed
- semantic comment gaps fixed
- deliberate skips
- remaining risks
- recommended next step

If the repo lacks durable rules and this cleanup should repeat, recommend adding a docs/rules policy from `comment-doc-policy-template.md`.

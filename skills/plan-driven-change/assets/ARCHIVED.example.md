# Archived Plans

Use this file as an index of archived plan metadata only.
Do not paste full archived plan contents here.
Recovery guidance should show both how to find the relevant commit and how to print the archived file from that commit.

| Original plan | Archived on | Summary | Recovery |
| --- | --- | --- | --- |
| `docs/plans/2026-03-10-01-auth-rework.md` | 2026-03-14 | Reworked session handling and split auth middleware from token storage. | `git log --follow -- docs/plans/2026-03-10-01-auth-rework.md` then `git show <commit>:docs/plans/2026-03-10-01-auth-rework.md` |
| `docs/plans/2026-03-11-02-billing-webhook-hardening.md` | 2026-03-15 | Tightened webhook signature checks, retry behavior, and failure logging. | `git log --follow -- docs/plans/2026-03-11-02-billing-webhook-hardening.md` then `git show <commit>:docs/plans/2026-03-11-02-billing-webhook-hardening.md` |
| `docs/plans/2026-03-12-01-dashboard-filter-refactor.md` | 2026-03-16 | Simplified filter state ownership and removed duplicate query parsing paths. | `git log --follow -- docs/plans/2026-03-12-01-dashboard-filter-refactor.md` then `git show <commit>:docs/plans/2026-03-12-01-dashboard-filter-refactor.md` |

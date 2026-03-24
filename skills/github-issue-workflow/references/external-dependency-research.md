# External Dependency Research

Use this when issue work depends on provider, platform, or human-owned setup outside the repo.

The goal is not just to say that setup is required. The goal is to record enough real-world detail that a human developer or maintainer can retrieve, create, verify, or configure the dependency without guessing.

## Research rule

Do not write a vague dependency note such as:

- "Need OAuth setup"
- "Need API key"
- "Need webhook config"

Instead, research the official docs and record the actual setup contract.

## What to research

For each external dependency, gather:

1. `Provider/platform`
   - The exact system involved, for example GitHub App, Stripe, Apple, Google OAuth, Clerk, Resend, Sentry, or Vercel.
2. `What must exist`
   - The concrete artifact or state required, for example an app registration, API key, webhook endpoint, redirect URI, sender identity, sandbox account, service account, org setting, or enabled capability.
3. `How to get or configure it`
   - The real-world action a human takes: create, copy, rotate, verify, enable, or register.
4. `Where to do that`
   - The admin console, dashboard area, API endpoint, CLI command, or settings screen where the step happens.
5. `Who needs access`
   - The role or permissions required, such as org owner, billing admin, app admin, or repo maintainer.
6. `Official docs`
   - The exact documentation page or section that confirms the requirement.
7. `Unlocks`
   - The validation step, acceptance criterion, or live verification that becomes possible once the dependency exists.

## Secret safety rule

Issue entries must never contain the actual contents of secrets.

Record this instead:

- the secret or credential name
- what system owns it
- whether it must be created, retrieved, rotated, or only verified
- where it is stored or configured
- who can access it
- how a human retrieves or sets it

Do not paste:

- API keys
- client secrets
- webhook signing secrets
- private keys
- service-account JSON contents
- passwords or tokens

## How to research

- Start with the provider's official setup docs, not a blog post or memory.
- Prefer setup, configuration, authentication, webhook, admin, or quickstart pages over API reference pages when the question is operational.
- Check whether the dependency is created, retrieved, or only verified. These are different tasks and the issue should say which one applies.
- Check whether the dependency is environment-specific, such as local, staging, production, sandbox, or preview.
- Check whether the provider requires a human to complete a dashboard step that code cannot satisfy.
- Check whether additional permissions, billing state, verified domains, redirect URLs, or callback endpoints are prerequisites.
- If the docs disagree or remain incomplete, say exactly what is still unknown and what source was inconclusive.

## Issue entry format

Write each dependency in a concrete block like this:

```md
- Provider/platform: GitHub App
  - What must exist: App installed in the target repo with Issues and Metadata permissions
  - How to get or configure it: Repo maintainer installs the app from the org settings page and confirms the permission set
  - Where to do that: GitHub org settings -> GitHub Apps -> Install App
  - Who needs access: Org owner or app admin
  - Official docs: https://docs.github.com/
  - Unlocks: Live verification that the issue automation can read and update issue state
```

If a secret is involved, write it like this instead:

```md
- Provider/platform: Resend
  - What must exist: API key for the staging account
  - How to get or configure it: Billing admin creates or retrieves the staging API key from the Resend dashboard
  - Where to do that: Resend dashboard -> API Keys
  - Who needs access: Billing admin
  - Official docs: https://resend.com/docs
  - Secret handling: Store the key in the team's secret manager; do not paste the key into this issue
  - Unlocks: Live email delivery verification in staging
```

## Review rule

Before treating the issue as ready:

- ask whether a human reading the issue could carry out the setup without guessing
- ask whether the issue says where the value comes from, not just its name
- ask whether the issue distinguishes between "someone must create this" and "someone must retrieve this existing value"
- ask whether the issue records secret handling safely without exposing the secret itself

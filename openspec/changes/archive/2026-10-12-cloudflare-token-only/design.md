# Design

## Context

See proposal.md for motivation. Current state that shapes the approach:

- `roles/cloudflare/tasks/main.yml` already has the token-mode path inline: select the token, decode the tunnel id from the token's `t` field, write `cloudflared.env`, write `state/cloudflare.yml`, enable the `ingress` compose profile. The API path is four imported task files guarded by `when: cloudflare_mode == 'api'` plus one run-token fetch.
- `roles/verify/tasks/tunnel.yml` already checks connector readiness and the Access redirect for both modes; the API block is a guarded `block`.
- `roles/common/tasks/main.yml` has one token-mode validation and five API-mode validations.
- The live server was deployed in token mode. `state/cloudflare.yml` holds the tunnel id and empty Access ids. The compose file and `cloudflared.env` on the server need no change.
- `docs/INPUTS.md` section 4 contains a five-step token guide that is correct but terse, followed by the API-mode recipe. Section 6 and the inputs table list API-mode values.
- Decisions D-04 (API-created ingress) and D-15 (token mode as second mode) are the entries this change supersedes.

## Goals / Non-Goals

**Goals:**

- One Cloudflare path with no mode variable, no API token, no API call anywhere in the repo.
- The deployed server is untouched: `make deploy` after the change reports no changed container and the tunnel id in `state/cloudflare.yml` is unchanged.
- The dashboard walkthrough is complete enough that an operator who has never used Zero Trust reaches a passing `make verify` without other sources.
- An operator with the old `cloudflare_mode: api` inputs gets a clear validation error, not a silent fallback.

**Non-Goals:**

- Any new Cloudflare feature (service tokens, IP bypass rules, WAF rules). Those are separate changes if ever wanted.
- Changing what the Access policy contains. Session duration is documented as a knob, not prescribed.
- Removing D-04 and D-15 from the decisions log. The log is append-only; they are superseded, not deleted.

## Decisions

### D1 (D-19): The repo consumes a connector token and verifies the outcome; it owns no Cloudflare resource

Alternatives considered: keep API mode dormant behind the flag (rejected: untested code is a liability and the operator will never fill its inputs); make API mode opt-in via a separate playbook (rejected: same maintenance cost, no user). The verify role is the enforcement point: connector ready plus the 302 to `cloudflareaccess.com` proves the operator did the dashboard steps. This keeps the security property of D-04 (Access in front of motionEye) without the repo creating it.

### D2: Fail loudly on the removed mode selector

`roles/common` asserts `cloudflare_mode is not defined` with a message naming this change and `docs/INPUTS.md` section 4. Alternative: ignore the variable (rejected: an operator who still has `api` set and API inputs filled would think they are managed). The assertion is one task and can be dropped in a later cleanup once no clone carries the variable.

### D3: `state/cloudflare.yml` keeps only `cloudflare_tunnel_id`

The file stays because snapshots copy `state/` (D-10) and because the id is the one fact the repo can cross-check against the token on every deploy (a token for a different tunnel changes the recorded id, which shows up in `git diff`). `cloudflare_mode_last_run`, `cloudflare_access_app_id`, `cloudflare_access_policy_id` are dropped. The playbooks that load the file as `vars_files` are unaffected.

### D4: Walkthrough structure in `docs/INPUTS.md`

Section 4 becomes "Cloudflare (done by you in the dashboard)" with numbered steps, each naming the page path, the button, and the exact field values. Order: Zero Trust account on first visit, Networks → Tunnels → Create a tunnel (Cloudflared), copy the `eyJ...` token from the install command and never run that command on the server, Public Hostname tab with type HTTP and URL `motioneye:8765` plus why `localhost` fails, Access → Applications → Self-hosted with Allow policy and Emails include rule and One-time PIN, Session Duration set to the maximum to reduce PIN prompts, Refresh token for a leak, and "how to tell it worked" mapped to the two verify assertions. The API-mode subsections are deleted. The inputs table and section 6 lose the API rows.

### D5: Role file layout after removal

`roles/cloudflare/tasks/main.yml` becomes the only task file. `preflight.yml`, `tunnel.yml`, `dns.yml`, `access.yml` are deleted. `defaults/main.yml` keeps nothing API-related; `cf_origin_service` stays only if the compose template or docs reference it, otherwise it goes too. The role comment header is rewritten to describe the token flow.

## Risks / Trade-offs

- [Operator deletes the tunnel in the dashboard] → Walkthrough has a "start over" paragraph: create a new tunnel, re-add hostname and Access, paste the new token, run `make deploy`. Accepted by the operator (see D-19 accepted cost).
- [A stale `cloudflare_access_app_id` in someone's `state/cloudflare.yml` is loaded as an unused variable] → Harmless; the deploy rewrites the file. The D2 assertion covers only `cloudflare_mode`.
- [Verify's Access check depends on Cloudflare returning a 302 to `cloudflareaccess.com`] → Already the case today in both modes; no new dependency. If Cloudflare changes the redirect host, the check fails loudly rather than passing.
- [Docs drift: dashboard UI labels change] → Walkthrough names the page path and field purpose, not only the button label, so an operator can still find the step.

## Migration Plan

1. Implement the removal and docs in the clone, run `make lint` and `make check`.
2. Run `make deploy` against the server; expect zero changed containers and `state/cloudflare.yml` rewritten to the single-field form with the same tunnel id.
3. Run `make verify`; expect the tunnel summary "connector ready; https://nvr.example.com/ redirects to Cloudflare Access".
4. Commit. Rollback is `git revert` of the commit; the server never changed.

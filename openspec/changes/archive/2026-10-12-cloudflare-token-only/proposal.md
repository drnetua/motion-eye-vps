# Proposal

## Why

The repo carries two ways to get the NVR behind Cloudflare: an `api` mode that creates the tunnel, DNS record and Access application from an API token, and a `token` mode that only runs a connector token the operator obtained in the Zero Trust dashboard. Only token mode has ever run against a real server; API mode was implemented against a mock, is not planned to be used, and the operator has decided that Cloudflare resources are their job in the dashboard, not the repo's. Keeping the API path means maintaining roughly 300 lines of untested tasks, six input validations, four non-secret inputs and one secret that the operator will never fill in.

## What Changes

- **BREAKING** Remove `cloudflare_mode`. The connector-token flow becomes the only flow. `cloudflare_mode: api` is no longer accepted; a repo with that value fails input validation with a message naming this change.
- **BREAKING** Remove the API-mode inputs: `cloudflare_account_id`, `cloudflare_zone_id`, `cloudflare_zone_name`, `cloudflare_allowed_emails` from `group_vars/all/vars.yml` and `vault_cloudflare_api_token` from the vault. `vault_cloudflare_tunnel_token` becomes required and `nvr_hostname` stays required.
- Remove the Cloudflare API tasks from `roles/cloudflare` (pre-flight, tunnel, DNS, Access, run-token fetch) and from `roles/verify` (tunnel status and DNS record via API). The role keeps: write the connector token to the server, decode the tunnel id from it, record it in `state/cloudflare.yml`, enable the ingress compose profile.
- Reduce `state/cloudflare.yml` to the tunnel id. The mode and Access ids fields are dropped.
- Verification keeps enforcing the outcome the operator is responsible for: the connector reports ready, and the public hostname answers with a redirect to Cloudflare Access. A hostname that answers 200 without Access, or is not served, fails verification with a message pointing at the dashboard step to fix.
- Replace the two-mode Cloudflare section of `docs/INPUTS.md` with one click-level walkthrough of the Zero Trust dashboard: first-time Zero Trust account, create the tunnel, where the connector token appears, add the public hostname with service `http://motioneye:8765`, create the Access application with an Allow policy on emails and one-time PIN, set the session duration, refresh the token if it leaks, and how to confirm it worked. The repo documents how to do it; it does not do it.
- Append decision D-19 to `docs/decisions.md` superseding D-04 and D-15.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cloudflare-ingress`: the requirements that the deployment creates the tunnel, the DNS record and the Access application, and reconciles them idempotently, are removed. The alternative-mode requirement becomes the only requirement: the deployment runs the operator's connector token and records the tunnel id. A new requirement states that verification refuses a hostname that is not behind Cloudflare Access. The purpose line changes from "created from operator credentials" to "configured by the operator in the dashboard".
- `operator-inputs`: the Cloudflare inputs requirement changes from Account ID, Zone ID, API token, hostname and allowed emails to connector token and hostname, with a dashboard walkthrough as the sourcing instruction. The secrets requirement names the connector token instead of the API token.
- `deployment-verification`: the tunnel requirement changes from "through the Cloudflare API, at least one active connection, hostname resolves to the tunnel" to "the connector reports ready and the public hostname redirects to Cloudflare Access".

## Impact

- Code removed: `roles/cloudflare/tasks/{preflight,tunnel,dns,access}.yml`, the API branch in `roles/cloudflare/tasks/main.yml`, the API block in `roles/verify/tasks/tunnel.yml`, six validations in `roles/common/tasks/main.yml`, `cf_api`/`cf_tunnel_name`/`cf_access_*` defaults.
- Inputs changed: `group_vars/all/vars.yml`, `group_vars/all/vault.yml.example`, `docs/INPUTS.md` sections 4 and 6 and the inputs table. `state/cloudflare.yml` loses three fields; the live server's committed state file is rewritten on the next deploy and must still carry the same tunnel id.
- No server-side change: the connector, compose file and `cloudflared.env` are already in the token-mode shape on the deployed server. `make deploy` after this change must report no change to containers.
- Decisions: D-04 and D-15 superseded by D-19. D-10 (snapshot includes `state/`) is unaffected in behaviour; snapshots simply carry a smaller file.
- Recovery posture: the repo can no longer recreate any Cloudflare resource. A deleted tunnel means repeating the dashboard walkthrough and pasting a new token into the vault. The operator has accepted this.

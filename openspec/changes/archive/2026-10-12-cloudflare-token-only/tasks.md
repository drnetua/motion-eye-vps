# Tasks

## 1. Remove the API path from the roles

- [x] 1.1 Delete `roles/cloudflare/tasks/{preflight,tunnel,dns,access}.yml`, remove their imports and the run-token fetch from `roles/cloudflare/tasks/main.yml`, make the token selection and tunnel-id decode unconditional, rewrite the role header comment for the token flow, and verify `ansible-playbook --syntax-check playbooks/deploy.yml` passes
- [x] 1.2 Reduce `roles/cloudflare/defaults/main.yml` to nothing API-related (drop `cf_api`, `cf_tunnel_name`, `cf_access_*`; drop `cf_origin_service` unless a template references it) and verify `grep -rn "cf_api\|cf_access\|cf_tunnel_name" roles playbooks` returns nothing
- [x] 1.3 Reduce the `state/cloudflare.yml` writer in `roles/cloudflare/tasks/main.yml` to `cloudflare_tunnel_id` only, rewrite the committed `state/cloudflare.yml` to the same shape with the current tunnel id, and verify the four playbooks that load it as `vars_files` still syntax-check
- [x] 1.4 Remove the API block and the mode ternary from `roles/verify/tasks/tunnel.yml`, keep connector readiness and the Access redirect assertion, and verify `grep -n cloudflare_mode roles/verify` returns nothing and the tunnel summary reads "connector ready; https://<host>/ redirects to Cloudflare Access"
- [x] 1.5 In `roles/common/tasks/main.yml` delete the five API-mode validations and the mode validation, make the connector-token validation unconditional, add an assertion that `cloudflare_mode` is not defined with a message naming this change and `docs/INPUTS.md` section 4, add an FQDN check on `nvr_hostname`, and verify `make check` fails with the named message when `cloudflare_mode: api` is set in a scratch vars file and passes with the real inputs

## 2. Inputs and documentation

- [x] 2.1 Remove `cloudflare_mode`, `cloudflare_account_id`, `cloudflare_zone_id`, `cloudflare_zone_name`, `cloudflare_allowed_emails` from `group_vars/all/vars.yml`, rewrite the `nvr_hostname` comment, remove `vault_cloudflare_api_token` from `group_vars/all/vault.yml.example` and make `vault_cloudflare_tunnel_token` the uncommented required line, and verify `make check` passes against the real vault
- [x] 2.2 Rewrite `docs/INPUTS.md` section 4 as the click-level dashboard walkthrough from design D4 (Zero Trust first visit, create tunnel, where the `eyJ...` token is and why not to run the install command, Public Hostname with HTTP `motioneye:8765`, Access self-hosted application with Allow policy on Emails and One-time PIN, Session Duration, Refresh token, start-over paragraph, "how to tell it worked" mapped to the two verify assertions), delete the API-mode subsections, update the inputs table and section 6, and verify every dashboard path named in the walkthrough matches the current Zero Trust UI by walking it once
- [x] 2.3 Update `README.md` (layout line for `state/`, the one-line description) and `docs/RUNBOOK.md` where they mention Cloudflare resources being created by the flow, and verify `grep -rn -i "api mode\|api token\|cloudflare_mode" README.md docs/RUNBOOK.md docs/INPUTS.md` returns nothing

## 3. Decisions and specs

- [x] 3.1 D-19 appended to `docs/decisions.md` and D-04 / D-15 headers marked superseded during the explore session that created this change; verified `grep -c '^## D-' docs/decisions.md` equals 19
- [x] 3.2 Run `openspec validate cloudflare-token-only --strict` and verify it reports the change valid after the implementation edits

## 4. Integration against the deployed server

- [x] 4.1 Run `make lint` and `make check` and verify both pass with the real inventory and vault
- [x] 4.2 Run `make deploy` against the server and verify the play reports no changed container, `cloudflared.env` is unchanged, and `git diff state/cloudflare.yml` shows only the three dropped fields with the same tunnel id
- [x] 4.3 Run `make verify ADMIN_PASSWORD=... VIEWER_PASSWORD=...` and verify all checks pass with the token-only tunnel summary

## Workflow follow-up

- Commit the implementation together with the D-19 entry and the updated specs.
- Archive the change with `/opsx:archive` once 4.3 has passed.

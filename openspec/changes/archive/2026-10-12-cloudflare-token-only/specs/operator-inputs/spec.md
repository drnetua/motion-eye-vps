# Spec Delta

## ADDED Requirements

### Requirement: Cloudflare connector token and hostname are provided with a dashboard walkthrough
The operator SHALL provide the connector token of a Cloudflare Tunnel they created in the Zero Trust dashboard and the public hostname they published on that tunnel. The repo SHALL document, click by click, where the token appears and how the hostname and its Access application are configured. No Cloudflare Account ID, Zone ID, zone name, API token or email list SHALL be required.

#### Scenario: Connector token malformed
- **WHEN** the connector token is absent or is not a connector token string
- **THEN** the flow fails validation before any server change and names the input and the documentation section

#### Scenario: Hostname malformed
- **WHEN** the hostname is not a fully qualified domain name
- **THEN** the flow fails validation and names the hostname

## MODIFIED Requirements

### Requirement: Secrets are stored encrypted in the repo
RTSP URLs containing credentials, bootstrap account passwords, and the Cloudflare connector token SHALL be stored encrypted in the repo. Plaintext secrets SHALL NOT be committed.

#### Scenario: Secrets at rest
- **WHEN** the repo is inspected without the vault key
- **THEN** no camera password, account password, or connector token is readable

#### Scenario: Running without the vault key
- **WHEN** a flow is run and the vault key is not available
- **THEN** the flow stops immediately and reports that the vault cannot be opened

## REMOVED Requirements

### Requirement: Cloudflare details are provided with sourcing instructions
**Reason**: The repo no longer uses the Cloudflare API, so Account ID, Zone ID, API token permissions and the hostname-in-zone check have no consumer. Replaced by the connector token and hostname requirement above.
**Migration**: Delete `cloudflare_account_id`, `cloudflare_zone_id`, `cloudflare_zone_name`, `cloudflare_allowed_emails` from `group_vars/all/vars.yml` and `vault_cloudflare_api_token` from the vault. Keep `nvr_hostname` and `vault_cloudflare_tunnel_token`.

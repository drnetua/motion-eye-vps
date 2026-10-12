# Spec Delta

## MODIFIED Requirements

### Requirement: Tunnel is connected
Verification SHALL confirm that the tunnel connector on the server reports itself ready, and that the public hostname answers over HTTPS with a redirect to Cloudflare Access. Verification SHALL NOT call the Cloudflare API.

#### Scenario: Connector offline
- **WHEN** the connector does not report ready within the retry window
- **THEN** verification fails and reports the connector's own status output

#### Scenario: Hostname reachable without Access
- **WHEN** the hostname answers 200 with no redirect to Cloudflare Access
- **THEN** verification fails and states that the NVR is reachable without a login wall

#### Scenario: Hostname not served
- **WHEN** the hostname does not resolve or the tunnel does not serve it
- **THEN** verification fails and states that the public hostname is not configured on the tunnel

# Spec Delta

## Purpose

Exposes the NVR web interface on a public hostname through a Cloudflare Tunnel with a Cloudflare Access login wall, so the server publishes no ports and TLS is handled by Cloudflare.

## ADDED Requirements

### Requirement: Tunnel is created from operator credentials
The deployment SHALL create a Cloudflare Tunnel in the operator's account using the provided API token, and SHALL record the tunnel identifier in the ops repo state so later runs reuse it.

#### Scenario: First deployment
- **WHEN** no tunnel identifier is recorded in repo state
- **THEN** a new tunnel is created and its identifier is written to repo state

#### Scenario: Subsequent run
- **WHEN** a tunnel identifier is recorded and the tunnel still exists
- **THEN** the existing tunnel is reused and no second tunnel is created

### Requirement: Public hostname routes to the NVR
The deployment SHALL create a proxied DNS record for the operator's hostname pointing at the tunnel, and SHALL configure the tunnel so that requests for that hostname reach the NVR web interface and all other requests receive a 404.

#### Scenario: Request for the hostname
- **WHEN** a browser requests the hostname over HTTPS
- **THEN** the request reaches the NVR web interface through the tunnel

#### Scenario: Request for another hostname
- **WHEN** a request arrives at the tunnel for a hostname that is not configured
- **THEN** the tunnel responds with 404

### Requirement: Access login wall protects the hostname
The deployment SHALL create a Cloudflare Access application for the hostname with a policy that allows only the operator-provided email addresses, authenticated by one-time PIN.

#### Scenario: Allowed email
- **WHEN** a visitor authenticates with an email in the allow-list
- **THEN** the visitor reaches the NVR login page

#### Scenario: Email not allowed
- **WHEN** a visitor authenticates with an email not in the allow-list
- **THEN** Cloudflare denies access and the NVR is never reached

### Requirement: Tunnel connector runs on the server
The server SHALL run a tunnel connector container that reaches the NVR over the private container network only. Neither the connector nor the NVR SHALL publish a port on the host.

#### Scenario: Connector restart
- **WHEN** the connector container restarts
- **THEN** the hostname becomes reachable again without operator action

#### Scenario: No host ports
- **WHEN** the host's listening ports are inspected after deployment
- **THEN** no port belonging to the connector or the NVR is listening on a host interface

### Requirement: Ingress is reconciled idempotently
Re-running the deployment with unchanged inputs SHALL leave the tunnel, DNS record, and Access application unchanged. Changing the allowed emails SHALL update the Access policy in place.

#### Scenario: Allow-list changed
- **WHEN** the operator adds an email to the allow-list and re-runs deployment
- **THEN** the existing Access policy is updated and the tunnel and DNS record are untouched

### Requirement: Dashboard-managed tunnel token is accepted as an alternative
When the operator supplies a connector token for a tunnel created in the Cloudflare dashboard instead of an API token, the deployment SHALL run the connector with that token, record the tunnel identifier decoded from it, and SHALL NOT require Account ID, Zone ID, zone name, allowed emails, or an API token. The repo SHALL document that hostname routing to the NVR and the Access policy must then be configured in the dashboard.

#### Scenario: Token mode deployment
- **WHEN** the operator sets the Cloudflare mode to token and provides a valid connector token
- **THEN** the connector starts, reports ready, and no Cloudflare API call is made

#### Scenario: Token mode without a token
- **WHEN** the Cloudflare mode is token and no connector token is present
- **THEN** validation fails before any remote change and names the missing input

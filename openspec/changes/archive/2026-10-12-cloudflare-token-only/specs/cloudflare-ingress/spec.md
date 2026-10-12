# Spec Delta

## ADDED Requirements

### Requirement: Public hostname is refused unless it is behind Cloudflare Access
Verification SHALL request the public hostname over HTTPS and SHALL pass only when the response is a redirect to a Cloudflare Access login. Any other outcome SHALL fail verification with a message that names the dashboard step the operator must complete.

#### Scenario: Hostname behind Access
- **WHEN** the operator has published the hostname on the tunnel and created an Access application for it
- **THEN** the request is redirected to Cloudflare Access and verification passes

#### Scenario: Hostname published without Access
- **WHEN** the hostname reaches the NVR and answers 200 with no Access redirect
- **THEN** verification fails and states that the NVR is reachable without a login wall and which dashboard page adds one

#### Scenario: Hostname not served
- **WHEN** the hostname is not routed to the tunnel or does not resolve
- **THEN** verification fails and states that the public hostname is not configured on the tunnel

### Requirement: Dashboard walkthrough is the sourcing instruction
The repo SHALL document, click by click, how the operator creates the tunnel, obtains the connector token, publishes the hostname to `http://motioneye:8765`, creates the Access application with an email allow-list and one-time PIN, sets the Access session duration, and refreshes a leaked token. The repo SHALL NOT perform any of these steps.

#### Scenario: Operator follows the walkthrough
- **WHEN** an operator with a Cloudflare account and a domain on Cloudflare nameservers follows only the documented steps
- **THEN** they obtain a connector token for the vault and a hostname that verification accepts

## MODIFIED Requirements

### Requirement: Dashboard-managed tunnel token is accepted as an alternative
The operator SHALL supply the connector token of a tunnel created in the Cloudflare dashboard. The deployment SHALL run the connector with that token, SHALL record the tunnel identifier decoded from the token in the ops repo state, and SHALL NOT make any Cloudflare API call. Account ID, Zone ID, zone name, allowed emails and an API token SHALL NOT be required or accepted.

#### Scenario: Token mode deployment
- **WHEN** the operator provides a valid connector token
- **THEN** the connector starts, reports ready, and no Cloudflare API call is made

#### Scenario: Token mode without a token
- **WHEN** no connector token is present
- **THEN** validation fails before any remote change and names the missing input

#### Scenario: Legacy mode selector present
- **WHEN** the inputs still contain the removed mode selector set to the API value
- **THEN** validation fails before any remote change and states that only the connector-token flow exists

## REMOVED Requirements

### Requirement: Tunnel is created from operator credentials
**Reason**: Cloudflare resources are owned by the operator in the Zero Trust dashboard; the repo consumes a connector token and never holds an API token. The API path was implemented against a mock only and is not planned to be used.
**Migration**: Create the tunnel in the dashboard following the walkthrough in `docs/INPUTS.md` and paste its connector token into the vault. An existing token-mode deployment needs no action.

### Requirement: Public hostname routes to the NVR
**Reason**: Hostname routing is configured by the operator on the tunnel's Public Hostname page, not by the repo. The outcome is still checked by verification (hostname behind Access).
**Migration**: Add the public hostname in the dashboard with service `http://motioneye:8765` as documented in the walkthrough.

### Requirement: Access login wall protects the hostname
**Reason**: The Access application is created by the operator in the dashboard. The repo keeps enforcing that it exists through the new verification requirement.
**Migration**: Create the Access application and Allow policy in the dashboard as documented in the walkthrough.

### Requirement: Ingress is reconciled idempotently
**Reason**: The repo no longer owns any Cloudflare resource, so there is nothing to reconcile. Changing allowed emails is done in the dashboard policy.
**Migration**: Edit the Access policy in the dashboard. Re-running deployment with the same token remains a no-op on the server.

# deployment-verification Specification

## Purpose

Automatically confirms that a deployed or updated system is healthy, reachable through its public hostname, accepts both accounts, streams every camera, and matches the inventory.

## Requirements

### Requirement: Containers are healthy
Verification SHALL confirm that every deployment container is running and, where a health check is defined, healthy.

#### Scenario: Container crash-looping
- **WHEN** a deployment container is restarting repeatedly
- **THEN** verification fails and names the container with its recent log lines

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

### Requirement: Both accounts can log in
Verification SHALL confirm that the admin account and the viewer account can authenticate to the NVR. Credentials for this check SHALL be supplied at run time by the operator when they differ from the bootstrap credentials. Run-time credentials SHALL be accepted from the operator's environment and SHALL NOT be printed by any flow in its command echo, task output, or summary.

#### Scenario: Bootstrap credentials still in effect
- **WHEN** the operator has not rotated passwords
- **THEN** verification authenticates both accounts with the bootstrap credentials and passes

#### Scenario: Rotated credentials supplied
- **WHEN** the operator supplies the current passwords at run time
- **THEN** verification authenticates both accounts with those passwords and passes

#### Scenario: Supplied credentials are not echoed
- **WHEN** the operator supplies the current passwords at run time to the verify or update flow
- **THEN** the flow's output contains neither password in plain text

#### Scenario: Viewer has no admin rights
- **WHEN** the viewer account is authenticated
- **THEN** it cannot change settings

### Requirement: Every camera is streaming
Verification SHALL confirm that every inventory camera is reported by the NVR as connected and producing frames.

#### Scenario: Camera stopped streaming
- **WHEN** a camera is configured but the NVR reports it as not connected
- **THEN** verification fails and names the camera

### Requirement: Configuration matches inventory
Verification SHALL confirm that the set of cameras in the NVR equals the inventory, that each camera records on motion only, and that the storage cap schedule is active.

#### Scenario: Configuration drift
- **WHEN** a camera on the server has been switched to continuous recording through the web interface
- **THEN** verification fails and names the camera and the differing setting

### Requirement: Verification is a distinct, repeatable step
Verification SHALL be runnable on its own at any time without changing the server.

#### Scenario: Ad-hoc run
- **WHEN** the operator runs verification on a healthy system
- **THEN** it reports all checks passed and makes no changes

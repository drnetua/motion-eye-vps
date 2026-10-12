# Spec Delta

## MODIFIED Requirements

### Requirement: Operator approval gate
After verification passes, the flow SHALL pause and ask the operator to confirm the system works as expected. The flow SHALL NOT commit anything until the operator approves. When no explicit approval decision is supplied and the flow is not attached to an interactive terminal, the flow SHALL stop before any server change and SHALL name the explicit approval option.

#### Scenario: Operator approves
- **WHEN** the operator confirms
- **THEN** the flow proceeds to record and commit the new state

#### Scenario: Operator rejects
- **WHEN** the operator declines
- **THEN** the flow rolls back to the snapshot, runs verification on the restored system, and commits nothing

#### Scenario: Explicit decision supplied
- **WHEN** the operator supplies an explicit approve or reject decision at launch
- **THEN** the flow does not prompt and applies that decision after verification

#### Scenario: No terminal and no explicit decision
- **WHEN** no explicit decision was supplied and the flow's standard input is not an interactive terminal
- **THEN** the flow stops before connecting to the server, changes nothing, and reports how to supply an explicit decision

### Requirement: Approved state is committed to the ops repo
On approval, the flow SHALL update the recorded image digests in the ops repo, harvest server-side configuration that the operator may have changed through the NVR interface, excluding plaintext secrets, and create a commit on the operator's local clone. The recorded digests file SHALL keep a stable image order and key order across approvals and SHALL carry a human-readable version for every image.

#### Scenario: Pin bump committed
- **WHEN** the operator approves an upgrade
- **THEN** the local clone has a new commit containing the new digests

#### Scenario: Only changed digests appear in the diff
- **WHEN** an approval bumps one image's digest
- **THEN** the commit diff of the recorded digests file touches that image's digest line and version comment and nothing else

#### Scenario: Image without a version label
- **WHEN** an approved image carries no version label in its metadata
- **THEN** the recorded version comment holds the version reported by the image itself, not a placeholder

#### Scenario: Operator changed a password since last run
- **WHEN** the operator rotated an account password through the NVR interface before the update
- **THEN** the commit contains the NVR's password hash for that account and no plaintext password

#### Scenario: Camera credentials never harvested
- **WHEN** configuration is harvested
- **THEN** no RTSP URL containing credentials appears in plaintext in the commit

## MODIFIED Requirements

### Requirement: Operator approval gate
After verification passes, the flow SHALL pause and ask the operator to confirm the system works as expected. The flow SHALL NOT record anything until the operator approves. When no explicit approval decision is supplied and the flow is not attached to an interactive terminal, the flow SHALL stop before any server change and SHALL name the explicit approval option.

#### Scenario: Operator approves
- **WHEN** the operator confirms
- **THEN** the flow proceeds to record the new state in the local clone

#### Scenario: Operator rejects
- **WHEN** the operator declines
- **THEN** the flow rolls back to the snapshot, runs verification on the restored system, and records nothing

#### Scenario: Explicit decision supplied
- **WHEN** the operator supplies an explicit approve or reject decision at launch
- **THEN** the flow does not prompt and applies that decision after verification

#### Scenario: No terminal and no explicit decision
- **WHEN** no explicit decision was supplied and the flow's standard input is not an interactive terminal
- **THEN** the flow stops before connecting to the server, changes nothing, and reports how to supply an explicit decision

## REMOVED Requirements

### Requirement: Approved state is committed to the ops repo
**Reason**: The published repo is a template. Live state (image digests for one deployment, harvested password hashes) must not enter version control, so the approval step can no longer commit.
**Migration**: Replaced by "Approved state is recorded in the local clone". The same files are written but stay git-ignored. The operator backs them up as the README's setup checklist describes.

## ADDED Requirements

### Requirement: Approved state is recorded in the local clone
On approval, the flow SHALL write the new image digests to the local pins file, and SHALL harvest server-side configuration the operator may have changed in the NVR interface, excluding plaintext secrets, into the local clone. It SHALL NOT run any git command. The pins file SHALL keep a stable image and key order and a human-readable version for every image.

#### Scenario: Pin bump recorded
- **WHEN** the operator approves an upgrade
- **THEN** the local pins file holds the new digests, no git commit is created, and the flow reports which files changed and that they should be backed up

#### Scenario: Only changed digests change in the file
- **WHEN** an approval bumps one image's digest
- **THEN** a textual diff of the pins file against its previous content touches that image's digest line and version comment and nothing else

#### Scenario: Image without a version label
- **WHEN** an approved image carries no version label in its metadata
- **THEN** the recorded version comment holds the version reported by the image itself, not a placeholder

#### Scenario: Operator changed a password since last run
- **WHEN** the operator rotated an account password through the NVR interface before the update
- **THEN** the harvested configuration contains the NVR's password hash for that account and no plaintext password

#### Scenario: Camera credentials never harvested
- **WHEN** configuration is harvested
- **THEN** no RTSP URL containing credentials appears in the harvested file, and the flow fails instead of writing one

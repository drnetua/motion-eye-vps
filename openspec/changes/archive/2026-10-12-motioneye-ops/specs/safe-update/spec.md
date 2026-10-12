# Spec Delta

## Purpose

Upgrades the operating system and the NVR images with a snapshot, verification, an explicit operator approval gate, rollback on rejection, and a commit of approved state back to the ops repo.

## ADDED Requirements

### Requirement: Update flow starts with inspection and OS upgrade
The update flow SHALL run server inspection, then upgrade all packages and reboot if required, before considering NVR updates.

#### Scenario: Server not deployed
- **WHEN** inspection finds no existing deployment from this repo
- **THEN** the update flow stops and directs the operator to the initial deployment flow

### Requirement: Image updates are detected by digest
The update flow SHALL resolve the current content digest of each pinned image tag in its registry and compare it to the digest recorded in the ops repo. It SHALL report, per image, whether an update is available.

#### Scenario: No updates
- **WHEN** every registry digest equals the recorded digest
- **THEN** the flow reports that the NVR is up to date and finishes after the OS upgrade

#### Scenario: Update available
- **WHEN** a registry digest differs from the recorded digest
- **THEN** the flow reports the image, the old digest, and the new digest, and proceeds to the upgrade

### Requirement: Snapshot before upgrade
Before replacing any container, the flow SHALL snapshot the NVR configuration, the compose definition, and the recorded digests to a timestamped location on the server. Recordings SHALL NOT be part of the snapshot and SHALL NOT be modified by the upgrade.

#### Scenario: Snapshot taken
- **WHEN** an upgrade is about to begin
- **THEN** a snapshot exists that is sufficient to restore the previous configuration and image versions

### Requirement: Upgrade then verify
The flow SHALL pull the new images, replace the containers, and run deployment verification.

#### Scenario: Verification fails after upgrade
- **WHEN** verification fails after the new containers start
- **THEN** the flow rolls back automatically to the snapshot and reports the failure

### Requirement: Operator approval gate
After verification passes, the flow SHALL pause and ask the operator to confirm the system works as expected. The flow SHALL NOT commit anything until the operator approves.

#### Scenario: Operator approves
- **WHEN** the operator confirms
- **THEN** the flow proceeds to record and commit the new state

#### Scenario: Operator rejects
- **WHEN** the operator declines
- **THEN** the flow rolls back to the snapshot, runs verification on the restored system, and commits nothing

### Requirement: Rollback restores the previous state
Rollback SHALL restore the snapshotted configuration and start the previously recorded image digests, leaving recordings untouched.

#### Scenario: Rollback completes
- **WHEN** rollback runs
- **THEN** the previously running digests are running again, configuration matches the snapshot, and verification passes

### Requirement: Approved state is committed to the ops repo
On approval, the flow SHALL update the recorded image digests in the ops repo, harvest server-side configuration that the operator may have changed through the NVR interface, excluding plaintext secrets, and create a commit on the operator's local clone.

#### Scenario: Pin bump committed
- **WHEN** the operator approves an upgrade
- **THEN** the local clone has a new commit containing the new digests

#### Scenario: Operator changed a password since last run
- **WHEN** the operator rotated an account password through the NVR interface before the update
- **THEN** the commit contains the NVR's password hash for that account and no plaintext password

#### Scenario: Camera credentials never harvested
- **WHEN** configuration is harvested
- **THEN** no RTSP URL containing credentials appears in plaintext in the commit

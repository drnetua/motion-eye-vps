# nvr-deployment Specification

## Purpose

Runs the NVR as containers with cameras defined from inventory, motion-triggered recording only, and two seeded accounts, from images pinned so that every deployment is reproducible.

## Requirements

### Requirement: NVR runs from digest-pinned images
The deployment SHALL run the NVR and the tunnel connector from container images referenced by tag and content digest. The digests SHALL come from the local pins file, or from the repo's tracked default pins when no local pins file exists yet. The deployment SHALL NOT use floating tags at run time.

#### Scenario: Deployment reproduces repo state
- **WHEN** the deployment runs twice with the same local pins file
- **THEN** the same image digests are running both times, regardless of what the registry tag currently points to

#### Scenario: First deployment from a fresh clone
- **WHEN** no local pins file exists
- **THEN** the deployment runs the digests in the tracked default pins, without the operator copying any file

### Requirement: Cameras are configured from inventory
The NVR SHALL have one camera per inventory entry, named as in the inventory, pulling from the entry's RTSP URLs. Cameras SHALL NOT be created by hand.

#### Scenario: Camera added to inventory
- **WHEN** an entry is added to the inventory and deployment re-runs
- **THEN** the NVR shows the new camera alongside the existing ones

#### Scenario: Camera removed from inventory
- **WHEN** an entry is removed from the inventory and deployment re-runs
- **THEN** the NVR no longer shows that camera, and its existing recordings are left on disk

### Requirement: Recording is motion-triggered only
Each camera SHALL record video only while motion is detected, plus a short configurable pre- and post-motion margin. Continuous recording SHALL be disabled.

#### Scenario: Idle scene
- **WHEN** no motion occurs in a camera's view for an hour
- **THEN** no recording is produced for that hour

#### Scenario: Motion occurs
- **WHEN** motion is detected
- **THEN** a recording is produced that covers the motion and the configured margins

### Requirement: Recordings use the camera stream without re-encoding
Recordings SHALL store the camera's native video stream without re-encoding.

#### Scenario: Recorded file codec
- **WHEN** a recording is inspected
- **THEN** its video codec matches the camera's RTSP stream codec

### Requirement: Accounts are seeded on first start only
On the NVR's first start the deployment SHALL set the admin and viewer accounts from the bootstrap credentials. On later runs the deployment SHALL NOT modify account passwords.

#### Scenario: First start
- **WHEN** the NVR has no accounts configured
- **THEN** the admin and viewer accounts are created with the bootstrap credentials

#### Scenario: Operator rotated passwords
- **WHEN** the operator changed a password through the NVR interface and deployment re-runs
- **THEN** the changed password remains in effect

### Requirement: Recordings and configuration persist outside containers
NVR configuration and recordings SHALL be stored on host paths that survive container replacement.

#### Scenario: Image upgrade
- **WHEN** the NVR container is replaced with a different image
- **THEN** existing recordings and camera configuration are still present

### Requirement: Containers restart automatically
NVR and connector containers SHALL restart automatically after a crash or host reboot.

#### Scenario: Host reboot
- **WHEN** the host reboots
- **THEN** all deployment containers are running within two minutes of boot without operator action

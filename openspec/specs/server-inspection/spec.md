# server-inspection Specification

## Purpose

Examines the target server and pre-flights prerequisites so that deploy and update flows fail early, before changing the server, when something is wrong.

## Requirements

### Requirement: Server facts are reported
The inspection SHALL report the operating system and version, CPU count, memory, the size and free space of the recordings volume, listening TCP ports, and whether Docker is installed, in a human-readable summary.

#### Scenario: Inspection of a fresh server
- **WHEN** inspection runs against a server with nothing installed
- **THEN** the summary shows OS, CPU, memory, disk, listening ports, and states that Docker is absent

### Requirement: Unsupported operating system stops the flow
The inspection SHALL fail when the server is not Ubuntu 24.04 LTS, before any change is made.

#### Scenario: Wrong distribution
- **WHEN** the server runs a distribution or version other than Ubuntu 24.04 LTS
- **THEN** the flow stops and reports the detected OS

### Requirement: Existing installation is detected
The inspection SHALL determine whether this repo's NVR deployment already exists on the server and report its state, including the currently running image digests when present. Each container SHALL be listed once, with its name and the image reference it runs, including the digest.

#### Scenario: Fresh server
- **WHEN** no deployment from this repo exists
- **THEN** the summary states the server is uninitialized

#### Scenario: Existing deployment
- **WHEN** a deployment from this repo exists
- **THEN** the summary lists each container once with its image reference and digest, and whether its containers are healthy

### Requirement: RTSP reachability is pre-flighted from the server
The inspection SHALL attempt to open every camera RTSP URL in the inventory from the server and report, per camera, whether a video stream was obtained and its resolution and codec.

#### Scenario: All cameras reachable
- **WHEN** every URL yields a video stream within the timeout
- **THEN** the summary lists each camera with its resolution and codec and the flow continues

#### Scenario: A camera is unreachable
- **WHEN** a URL fails to yield a stream within the timeout
- **THEN** the flow stops before deploying and names the failing camera and the error

### Requirement: Capacity warning
The inspection SHALL warn, without stopping, when the number of cameras is high relative to available CPU cores.

#### Scenario: Many cameras on few cores
- **WHEN** the number of cameras exceeds twice the CPU core count
- **THEN** the summary includes a warning that motion detection may exceed CPU capacity, and the flow continues

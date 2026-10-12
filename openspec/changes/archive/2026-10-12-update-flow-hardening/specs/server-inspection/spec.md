# Spec Delta

## MODIFIED Requirements

### Requirement: Existing installation is detected
The inspection SHALL determine whether this repo's NVR deployment already exists on the server and report its state, including the currently running image digests when present. Each container SHALL be listed once, with its name and the image reference it runs, including the digest.

#### Scenario: Fresh server
- **WHEN** no deployment from this repo exists
- **THEN** the summary states the server is uninitialized

#### Scenario: Existing deployment
- **WHEN** a deployment from this repo exists
- **THEN** the summary lists each container once with its image reference and digest, and whether its containers are healthy

## MODIFIED Requirements

### Requirement: NVR runs from digest-pinned images
The deployment SHALL run the NVR and the tunnel connector from container images referenced by tag and content digest. The digests SHALL come from the local pins file, or from the repo's tracked default pins when no local pins file exists yet. The deployment SHALL NOT use floating tags at run time.

#### Scenario: Deployment reproduces repo state
- **WHEN** the deployment runs twice with the same local pins file
- **THEN** the same image digests are running both times, regardless of what the registry tag currently points to

#### Scenario: First deployment from a fresh clone
- **WHEN** no local pins file exists
- **THEN** the deployment runs the digests in the tracked default pins, without the operator copying any file

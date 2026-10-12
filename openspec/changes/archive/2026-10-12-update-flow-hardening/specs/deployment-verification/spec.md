# Spec Delta

## MODIFIED Requirements

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

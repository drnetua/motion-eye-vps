# Spec Delta

## Purpose

Defines the inputs an operator supplies to run the deployment or update flow from a fresh clone of the ops repo, how they are validated, and where secrets live.

## ADDED Requirements

### Requirement: Operator runs flows from a local clone
The ops repo SHALL be runnable from a fresh clone on an operator machine with only SSH, git, and the documented tool installer present. The repo SHALL document a single command to install the remaining local dependencies.

#### Scenario: Fresh clone bootstrap
- **WHEN** an operator clones the repo on a machine that has SSH and git but no Ansible
- **THEN** running the documented bootstrap command installs everything needed to run the flows, and the flows run without further manual setup

### Requirement: Target server is addressed by SSH key as root
The flows SHALL connect to the target server as root using an SSH key with no password prompt. The flows SHALL NOT require or accept a password for SSH.

#### Scenario: Key-based root access works
- **WHEN** the operator's SSH key is authorized for root on the target server and the server address is set in the inventory
- **THEN** every flow connects without prompting for a password

#### Scenario: Key-based root access is missing
- **WHEN** root login with the operator's key fails
- **THEN** the flow stops before changing anything on the server and reports the SSH failure

### Requirement: Camera list is provided as inventory
The operator SHALL provide a list of cameras, each with a unique name and a main RTSP URL, and optionally a lower-resolution RTSP substream URL. The flows SHALL treat the inventory as the source of truth for which cameras exist.

#### Scenario: Camera with main and substream
- **WHEN** a camera entry includes both a main URL and a substream URL
- **THEN** the deployed NVR records from the main URL and detects motion on the substream

#### Scenario: Camera with main stream only
- **WHEN** a camera entry includes only a main URL
- **THEN** the deployed NVR records and detects motion from the main URL

#### Scenario: Duplicate camera name
- **WHEN** two camera entries share a name
- **THEN** the flow fails validation before touching the server and names the duplicate

### Requirement: Bootstrap credentials are provided for two accounts
The operator SHALL provide a username and password for an admin account and for a viewer account. These credentials SHALL be used only to seed the NVR on its first start.

#### Scenario: Bootstrap credentials present
- **WHEN** both account credentials are set and the NVR has never been started
- **THEN** the NVR starts with those two accounts

#### Scenario: Bootstrap credentials missing
- **WHEN** either account's credentials are absent during initial deployment
- **THEN** the flow fails validation before touching the server

### Requirement: Cloudflare details are provided with sourcing instructions
The operator SHALL provide a Cloudflare Account ID, Zone ID, an API token, a public hostname inside that zone, and a list of allowed login emails. The repo SHALL document, for each value, where in the Cloudflare dashboard it is obtained and which permissions the token needs.

#### Scenario: Token lacks a required permission
- **WHEN** the API token cannot perform one of the required operations
- **THEN** the flow fails during pre-flight with a message naming the missing permission, before any server change

#### Scenario: Hostname not inside the zone
- **WHEN** the hostname does not belong to the zone identified by the Zone ID
- **THEN** the flow fails validation and names the mismatch

### Requirement: Secrets are stored encrypted in the repo
RTSP URLs containing credentials, bootstrap account passwords, and the Cloudflare API token SHALL be stored encrypted in the repo. Plaintext secrets SHALL NOT be committed.

#### Scenario: Secrets at rest
- **WHEN** the repo is inspected without the vault key
- **THEN** no camera password, account password, or API token is readable

#### Scenario: Running without the vault key
- **WHEN** a flow is run and the vault key is not available
- **THEN** the flow stops immediately and reports that the vault cannot be opened

### Requirement: Inputs are validated before any remote change
All operator inputs SHALL be validated for presence and shape before the first change is made to the server.

#### Scenario: Malformed RTSP URL
- **WHEN** a camera URL does not start with `rtsp://` or `rtsps://`
- **THEN** validation fails and names the camera

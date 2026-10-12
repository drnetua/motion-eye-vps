# operator-inputs Specification

## Purpose

Defines the inputs an operator supplies to run the deployment or update flow from a fresh clone of the ops repo, how they are validated, and where secrets live.

## Requirements

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

### Requirement: Secrets are stored encrypted in the repo
RTSP URLs containing credentials, bootstrap account passwords, and the Cloudflare connector token SHALL be stored encrypted in the operator's clone. The encrypted file SHALL be git-ignored and SHALL NOT be committed, encrypted or not. Plaintext secrets SHALL NOT be committed.

#### Scenario: Secrets at rest
- **WHEN** the operator's clone is inspected without the vault key
- **THEN** no camera password, account password, or connector token is readable

#### Scenario: Secrets never in version control
- **WHEN** the tracked files and the full history of the published repo are inspected
- **THEN** no vault file, encrypted or plaintext, is present

#### Scenario: Running without the vault key
- **WHEN** a flow is run and the vault key is not available
- **THEN** the flow stops immediately and reports that the vault cannot be opened

### Requirement: Inputs are validated before any remote change
All operator inputs SHALL be validated for presence and shape before the first change is made to the server.

#### Scenario: Malformed RTSP URL
- **WHEN** a camera URL does not start with `rtsp://` or `rtsps://`
- **THEN** validation fails and names the camera

### Requirement: Cloudflare connector token and hostname are provided with a dashboard walkthrough
The operator SHALL provide the connector token of a Cloudflare Tunnel they created in the Zero Trust dashboard and the public hostname they published on that tunnel. The repo SHALL document, click by click, where the token appears and how the hostname and its Access application are configured. No Cloudflare Account ID, Zone ID, zone name, API token or email list SHALL be required.

#### Scenario: Connector token malformed
- **WHEN** the connector token is absent or is not a connector token string
- **THEN** the flow fails validation before any server change and names the input and the documentation section

#### Scenario: Hostname malformed
- **WHEN** the hostname is not a fully qualified domain name
- **THEN** the flow fails validation and names the hostname

### Requirement: Per-deployment inputs live in git-ignored files created from templates
Every file holding a value specific to one deployment SHALL be git-ignored: the server address, the public hostname, the vault, recorded image digests, the tunnel id, and harvested NVR configuration. For each one the operator creates by hand, the repo SHALL track a template with placeholder values. Placeholders SHALL use documentation-reserved addresses and domains.

#### Scenario: Fresh clone
- **WHEN** an operator clones the published repo
- **THEN** the clone contains templates with placeholder values and no file holding a real server address, hostname, tunnel id, camera address, or password hash

#### Scenario: Existing clone after upgrade
- **WHEN** an operator with working live files pulls this change
- **THEN** their live files remain on disk with the same content and are reported by git as ignored, not as deleted

### Requirement: Missing live inputs are reported with their template
A flow SHALL NOT start when a required live input file is missing. The error SHALL name the missing file and the template to copy it from.

#### Scenario: Inventory not created
- **WHEN** the operator runs any flow before creating the inventory file
- **THEN** the flow stops before connecting anywhere and names the inventory file and its template

#### Scenario: Vault not created
- **WHEN** the operator runs any flow before creating the vault
- **THEN** the flow stops before connecting anywhere and names the vault file and its template

### Requirement: Tracked live files are refused by lint
The repo's lint command SHALL fail when any per-deployment file is tracked by git, and SHALL name the file.

#### Scenario: Live file added by mistake
- **WHEN** the inventory or vault file has been force-added to the git index
- **THEN** lint fails and names the file

### Requirement: Setup and backup are documented as a checklist
The README SHALL list, before the first deployment step, every file the operator creates, its template, whether it holds secrets, and which files and keys to back up off the operator machine. Losing them means re-entering every input.

#### Scenario: Operator prepares a fresh VPS deployment
- **WHEN** an operator reads the README's setup section on a fresh clone
- **THEN** they can create every required file from its template without other sources, and they know which files to back up

### Requirement: Agent-guided setup keeps secrets out of the conversation
The repo SHALL ship an agent-neutral guide for walking an operator through first deployment and update with an AI coding agent. It SHALL forbid the agent to request, read, print or write any secret, SHALL assign secret entry to the operator, and SHALL require operator confirmation before any command that changes the server.

#### Scenario: Agent reaches the vault step
- **WHEN** the guided setup reaches the vault
- **THEN** the agent explains the fields from the template and the operator enters the values in their own editor, without pasting them into the conversation

#### Scenario: Agent reaches a server-changing step
- **WHEN** the next step is initial deployment, update, or rollback
- **THEN** the agent asks the operator before the command runs and never answers the update approval prompt itself

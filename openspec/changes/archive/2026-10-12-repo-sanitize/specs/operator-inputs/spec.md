## MODIFIED Requirements

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

## ADDED Requirements

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

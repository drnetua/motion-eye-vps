# Spec Delta

## Purpose

Brings a fresh Ubuntu server to a patched, firewalled, SSH-key-only baseline with intrusion protection and a container runtime, and keeps it there across runs.

## ADDED Requirements

### Requirement: Packages are fully upgraded
The hardening SHALL upgrade all installed packages to the latest available versions and SHALL reboot the server when a reboot is required to apply them.

#### Scenario: Kernel upgrade pending
- **WHEN** the upgrade installs a package that requires a reboot
- **THEN** the server is rebooted and the flow waits for it to return before continuing

### Requirement: Security updates install automatically
The server SHALL install security updates automatically without operator action.

#### Scenario: Unattended security update
- **WHEN** a security update becomes available after deployment
- **THEN** it is installed automatically within the distribution's default schedule

### Requirement: SSH accepts keys only
The SSH service SHALL reject password authentication and SHALL permit root login only with a key.

#### Scenario: Password login attempt
- **WHEN** a client attempts SSH password authentication for any user
- **THEN** the attempt is rejected

#### Scenario: Root key login
- **WHEN** a client presents the operator's authorized key for root
- **THEN** login succeeds

### Requirement: Firewall allows only SSH inbound
The host firewall SHALL deny all inbound connections except TCP port 22. Containers SHALL NOT bypass this policy by publishing ports on the host.

#### Scenario: Port scan from the internet
- **WHEN** the server's public address is scanned
- **THEN** only TCP port 22 is open

#### Scenario: Container publishing a port
- **WHEN** a container in the deployment is configured to publish a port on the host
- **THEN** deployment verification fails and names the container

### Requirement: Repeated SSH failures are banned
The server SHALL temporarily ban source addresses that repeatedly fail SSH authentication.

#### Scenario: Brute force attempt
- **WHEN** a source address fails SSH authentication more than the configured threshold within the configured window
- **THEN** that address is blocked for the configured ban time

### Requirement: Container runtime is installed
The server SHALL have Docker Engine with the Compose plugin installed from the Docker upstream repository, enabled at boot.

#### Scenario: Reboot
- **WHEN** the server reboots
- **THEN** Docker starts automatically and restarts the deployment's containers

### Requirement: Hardening is idempotent
Running the hardening again on an already hardened server SHALL make no changes and SHALL NOT disrupt running containers.

#### Scenario: Second run
- **WHEN** hardening runs on a server where it has already completed
- **THEN** no configuration changes are reported and containers keep running

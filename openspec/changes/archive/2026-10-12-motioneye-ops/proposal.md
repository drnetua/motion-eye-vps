# Proposal

## Why

There is no reproducible way to stand up or maintain a self-hosted camera NVR for a set of RTSP IP cameras. Today it would be manual work on a fresh server, with no record of what was configured, no safe upgrade path, and no rollback. This repo becomes the ops repo: clone it on any machine, provide a handful of inputs, and deploy or update a hardened, internet-accessible motionEye instance behind a Cloudflare Tunnel.

## What Changes

- Add an Ansible-based ops repo with two operator entry points: an initial deployment flow and an update flow, both run from a local clone against a root-accessible Ubuntu server over SSH keys.
- Add an operator input contract: camera RTSP URLs, bootstrap admin and user credentials, and Cloudflare account details (Account ID, Zone ID, scoped API token, hostname, allowed emails), with documented instructions on where each value is obtained. Secrets live in Ansible Vault.
- Add a server inspection step that reports OS, CPU, RAM, disk, open ports and existing installation state, and that pre-flights every RTSP URL from the server before anything is deployed.
- Add server hardening: full package upgrade, unattended security updates, key-only SSH, firewall allowing only port 22, fail2ban, and Docker Engine with the compose plugin.
- Add a Cloudflare ingress created entirely by the playbook from the API token: tunnel, ingress rules, proxied DNS CNAME, Access application with an email allow-list, and a cloudflared container. The server publishes no ports; TLS and public hostname are handled by Cloudflare. The user-provided domain only needs to be on Cloudflare nameservers; no prior DNS pointing to the server is required.
- Add motionEye deployed with Docker Compose from digest-pinned images, with cameras pre-defined from inventory, motion-triggered recording only, passthrough recording, and admin plus viewer accounts seeded on first boot only.
- Add recording retention: per-camera retention in motionEye plus a host-level pruner that keeps storage usage at or below 90% by deleting the oldest recordings first.
- Add post-deploy verification: container health, tunnel health, admin and user login, every camera streaming, and configuration assertions.
- Add a safe update flow: OS upgrade, registry digest comparison against pinned digests, snapshot of config and pins, upgrade, verification, explicit operator approval gate, rollback to the snapshot on rejection, and on approval harvesting of server-side config changes plus a commit of the new pins to the ops repo.
- ZoneMinder is not used. motionEye was chosen as the lighter alternative that meets the requirements (free, RTSP, multi-camera, password protected, motion-triggered recording).

## Capabilities

### New Capabilities

- `operator-inputs`: the inputs an operator provides to run either flow, how they are supplied and validated, where secrets live, and where each Cloudflare value is obtained.
- `server-inspection`: examining a target server and pre-flighting prerequisites (OS, resources, ports, existing install, RTSP reachability) before deploy or update.
- `server-hardening`: bringing a fresh Ubuntu server to a patched, firewalled, SSH-key-only, fail2ban-protected baseline with Docker installed.
- `cloudflare-ingress`: exposing the NVR via a Cloudflare Tunnel with an Access login wall, created and reconciled from the operator's Cloudflare credentials, with no host ports published.
- `nvr-deployment`: running motionEye with pre-defined cameras, motion-only recording, and seeded admin and viewer accounts from digest-pinned images.
- `recording-retention`: bounding recording storage at 90% of the volume by pruning oldest recordings, in addition to per-camera time-based retention.
- `deployment-verification`: automated checks that the deployed system is healthy, reachable, logins work, cameras stream, and configuration matches inventory.
- `safe-update`: upgrading OS and NVR images with snapshot, verification, operator approval, rollback, and committing approved state back to the ops repo.

### Modified Capabilities

None. The project has no existing specs.

## Impact

- New repository content: Ansible inventory, group variables, vault, playbooks, roles, templates for Docker Compose and motionEye configuration, a pruner script and systemd timer, a committed state file for tunnel ID and image digests, and operator documentation.
- Local dependencies: Ansible (installed via `uv tool install ansible`), `ansible-vault`, SSH. No Terraform.
- Remote dependencies: Ubuntu 24.04 LTS server with root SSH key access, Docker Engine, `ghcr.io/motioneye-project/motioneye` image, `cloudflare/cloudflared` image, `ffprobe` for RTSP pre-flight.
- External services: Cloudflare account with the domain on Cloudflare nameservers; Cloudflare Zero Trust free tier for Tunnel and Access.
- Security posture: cameras are reachable by public IP, which the operator has accepted; RTSP credentials travel in the clear between camera and server. The server itself exposes only SSH.

# Tasks

## 1. Repo skeleton and operator inputs

- [x] 1.1 Create the Ansible layout from design D9 (`ansible.cfg`, `inventory/hosts.yml`, `group_vars/all/vars.yml`, `group_vars/all/vault.yml.example`, `state/`, `harvest/`, `playbooks/`, `roles/`, `docs/`, `requirements.yml`, `.gitignore` excluding the vault password file) and verify `ansible-inventory --list` renders without errors
- [x] 1.2 Write `docs/INPUTS.md` covering every operator value: server address, SSH key expectation, camera list format with main and optional substream URL, bootstrap admin and viewer credentials, Cloudflare Account ID, Zone ID, API token with the exact three permissions and dashboard paths, hostname, allowed emails, and verify a reader can locate each value in the Cloudflare dashboard following only the doc
- [x] 1.3 Write a `Makefile` or `bin/bootstrap` that installs Ansible via `uv tool install ansible` and the collections from `requirements.yml`, and verify it succeeds on a machine without Ansible
- [x] 1.4 Implement the `common` role input validation: vault openable, both bootstrap credentials present on init, camera names unique, every URL starts with `rtsp://` or `rtsps://`, hostname ends with the zone name, and verify each failure case with a deliberately broken `vars.yml` produces a named error before any remote task runs

## 2. Server inspection

- [x] 2.1 Implement `playbooks/examine.yml` reporting OS, CPU, memory, recordings volume size and free space, listening ports, Docker presence, and existing deployment state including running image digests, and verify the summary prints correctly against a fresh server and against a deployed one
- [x] 2.2 Add the Ubuntu 24.04 LTS assertion and verify the playbook fails with the detected OS named on any other release (test with a 22.04 container or VM)
- [x] 2.3 Implement RTSP pre-flight using `ffprobe` in a throwaway container on the server for every inventory camera, reporting resolution and codec, and verify an unreachable URL stops the flow naming the camera
- [x] 2.4 Add the camera-to-core capacity warning and verify it prints when cameras exceed twice the core count and is silent otherwise

## 3. Server hardening

- [x] 3.1 Implement the `hardening` role: full apt upgrade with conditional reboot and wait, `unattended-upgrades` enabled for security, and verify a second run reports zero changes
- [x] 3.2 Harden sshd (`PasswordAuthentication no`, `PermitRootLogin prohibit-password`) with a validated config reload and verify a password login attempt is rejected while key login still works
- [x] 3.3 Configure ufw default deny inbound, allow 22/tcp, enable, and verify an external port scan shows only 22
- [x] 3.4 Install and enable fail2ban with the sshd jail and verify `fail2ban-client status sshd` shows the jail active
- [x] 3.5 Implement the `docker` role installing Docker Engine and the Compose plugin from the Docker apt repository, enabled at boot, and verify `docker compose version` works after a reboot

## 4. Cloudflare ingress

- [ ] 4.1 Implement the `cloudflare` role pre-flight: verify the token against the token verify endpoint and probe each required permission with a read call, failing with the missing permission named, and verify with a token lacking Access permissions
- [ ] 4.2 Create or reuse the tunnel from `state/cloudflare.yml`, write the tunnel ID back to the state file, and verify two consecutive runs produce exactly one tunnel in the account
- [ ] 4.3 Push tunnel ingress configuration routing the hostname to `http://motioneye:8765` with a 404 catch-all, and verify a request for an unconfigured hostname returns 404
- [ ] 4.4 Create or update the proxied CNAME for the hostname to `<tunnel-id>.cfargotunnel.com` and verify DNS resolves to the tunnel
- [ ] 4.5 Create or update the Access application and email allow-list policy with one-time PIN, record the app ID in state, and verify an allowed email reaches motionEye while a non-listed email is denied
- [x] 4.6 Fetch the tunnel run token by API and write it to the server as a secret file readable only by root, never to the repo, and verify `git grep` of the repo finds no tunnel token

## 5. motionEye deployment

- [x] 5.1 Create `state/images.yml` with tag plus digest for `ghcr.io/motioneye-project/motioneye:0.44.0` and `cloudflare/cloudflared` and verify the compose template renders `image: <repo>:<tag>@sha256:<digest>` for both
- [x] 5.2 Write the compose template: motioneye and cloudflared on a private network, no `ports:`, restart `unless-stopped`, volumes at `/srv/motioneye/etc` and `/srv/motioneye/media`, HTTP healthcheck on motioneye, and verify `ss -ltn` on the host shows no new listeners after `compose up`
- [x] 5.3 Write the `camera-N.conf` template from inventory (name, `netcam_url` substream or main, `netcam_high_url` main, `movie_passthrough on`, `emulate_motion off`, `movie_output on`, `picture_output off`, pre/post capture, `preserve_movies` days) with stable numbering from inventory order, and verify adding and removing an inventory entry adds and removes the file and the camera in the UI
- [x] 5.4 Render `motion.conf` and `motioneye.conf` on first deploy only, guarded by a marker file, and verify a second deploy leaves `motion.conf` untouched
- [x] 5.5 Implement first-boot account seeding by running a Python one-liner inside the container that calls `config.set_admin_password` and `config.set_normal_password`, then restarting motioneye, gated on the marker file, and verify both accounts log in once and that a UI password change survives a re-deploy
- [x] 5.6 Verify a recorded file's codec matches the camera stream (`ffprobe` on a recording) and that an idle camera produces no files over a test window

## 6. Recording retention

- [x] 6.1 Write the pruner script (threshold and path from a config file, delete oldest `*.mp4` and matching thumbnails until usage is at or below threshold, journal logging of before/after usage and count, `--dry-run` flag) and verify with a filled test directory that it stops at the threshold and touches nothing outside the path
- [x] 6.2 Install the script plus an hourly systemd timer via the `retention` role, set threshold 90 and the recordings path, and verify `systemctl list-timers` shows it active and a manual run logs to the journal
- [x] 6.3 Document retention behavior and the `preserve_movies` default in `docs/RUNBOOK.md` and verify the documented override variable changes the rendered camera config

## 7. Deployment verification

- [x] 7.1 Implement `playbooks/verify.yml` container checks from `docker compose ps --format json` asserting running and healthy, and verify it fails naming a container when one is stopped
- [x] 7.2 Add tunnel checks: Cloudflare API tunnel status healthy and hostname CNAME to the tunnel, and verify it fails when cloudflared is stopped
- [x] 7.3 Write the motionEye signed-request helper (`_username`, `_signature`) and use it to log in as admin and viewer against `/config/list`, with run-time credential override via extra vars, and verify success with bootstrap credentials, success with rotated credentials passed at run time, and a 403 for the viewer on an admin-only endpoint
- [x] 7.4 Add camera checks: every inventory camera present in `/config/list` and reported connected via motion's webcontrol, and verify it fails naming a camera whose URL is broken
- [x] 7.5 Add configuration drift checks (camera set equals inventory, `emulate_motion off` and `movie_output on` per camera, pruner timer active, no non-loopback listeners except 22) and verify each check fails when its condition is broken by hand
- [x] 7.6 Assemble `site.yml` as examine, harden, deploy, verify and run it end to end on a fresh server, verifying the operator can log in through the hostname with both accounts and sees every camera streaming

## 8. Safe update flow

- [x] 8.1 Implement `playbooks/update.yml` entry: examine, stop with a pointer to `site.yml` if no deployment exists, then apt upgrade with reboot, and verify both the undeployed and deployed paths
- [x] 8.2 Implement digest resolution with `skopeo inspect` in a throwaway container for each image in `state/images.yml`, report per image old and new digest, and end early with "up to date" when nothing differs, verifying both outcomes by editing the state file
- [x] 8.3 Implement snapshot to `/srv/motioneye/snapshots/<timestamp>/` containing `/srv/motioneye/etc`, the rendered compose file, and `state/`, excluding media, and verify the snapshot can be listed and is complete
- [x] 8.4 Implement pull, `compose up -d`, and verify; on verification failure run rollback automatically, and verify by pinning a deliberately broken image digest
- [x] 8.5 Implement `playbooks/rollback.yml` taking a snapshot timestamp, restoring config, re-rendering compose from the snapshot's state file, starting, and verifying, and verify the previous digests are running afterwards
- [x] 8.6 Add the operator approval `pause`; on rejection run rollback and re-verify, committing nothing, and verify the clone has no new commit after a rejection
- [x] 8.7 On approval, rewrite `state/images.yml`, fetch `motion.conf` into `harvest/motion.conf`, assert the harvested file contains no `rtsp://` string, and create a local git commit with a generated message, verifying the commit contains the new digests and the argon2 hash of a password rotated before the update
- [x] 8.8 Assemble `update.yml` and document the update and rollback-by-hand walkthroughs in `docs/RUNBOOK.md`, verifying a full update cycle on a server pinned to an older motionEye digest

## 9. Integration

- [x] 9.1 Run `site.yml` on a fresh server, then `update.yml` with no updates available, then `update.yml` with a forced older pin, approving once and rejecting once, and verify every spec scenario that is machine-checkable passes and the repo ends with exactly one new commit

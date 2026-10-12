# Design

## Context

See proposal.md for motivation. The repo is empty. The operator machine has Docker and `uv` but no Ansible. The target is a fresh Ubuntu server reachable as root over SSH key. Cameras are reachable from the server by public IP (operator decision). The operator's domain is on Cloudflare nameservers. Requirements are in `specs/*/spec.md`.

Facts verified during exploration that shape the design:

- SSH key bootstrap for root is `scripts/setup-ssh-access.sh` (D-01), outside Ansible.
- motionEye 0.44.0 (released 2026-06-20) is published at `ghcr.io/motioneye-project/motioneye` with tags `0.44.0`, `0.44`, `latest`, `edge`.
- motionEye stores account passwords as argon2 hashes in `motion.conf`, written by `config.set_admin_password` and `config.set_normal_password` in its Python package. There is no CLI subcommand for this.
- motionEye configuration is plain files under `/etc/motioneye`: `motioneye.conf`, `motion.conf`, and one `camera-N.conf` per camera. motionEye rewrites these when settings change in the web UI.
- motionEye retention is per-camera and days-based. It has no percentage-of-disk cap.
- Cloudflare's remote tunnel API needs a token with Account: Cloudflare Tunnel Edit, Zone: DNS Edit, and Account: Access: Apps and Policies Edit.

## Goals / Non-Goals

**Goals:**

- Two operator entry points, `site.yml` (initial) and `update.yml`, each runnable end to end from a fresh clone.
- The repo is the source of truth for cameras, image digests, tunnel identity, and hardening. The server can be rebuilt from the repo plus the vault key.
- Every destructive or irreversible step is preceded by a check that would catch the common failure.

**Non-Goals:**

- Object detection, notifications, or mobile apps.
- VPN between camera site and server.
- Provisioning the VPS itself. It exists before the flow runs.
- Multi-server inventories. One server, one NVR.
- Backup of recordings. Recordings are expendable by design.

## Decisions

Each decision is logged in `docs/decisions.md` per CLAUDE.md; the `D-NN` in each heading is its entry. The NVR choice itself is D-03, RTSP pre-flight placement is D-11, and the SSH key bootstrap script is D-01.

### D1 (D-02): Ansible over shell scripts, pyinfra, or Terraform

Ansible is SSH-native, idempotent by convention, has first-class Vault for secrets, and maps the examine/harden/deploy/verify/update split onto playbooks directly. Terraform was rejected because nothing is provisioned; the Cloudflare resources are few and are handled with Ansible's `uri` module against the Cloudflare API, keeping one tool. Shell scripts were rejected for lack of idempotency. Installed locally with `uv tool install ansible`, since `uv` is already present. Required collections (`community.docker`, `community.general`) are declared in `requirements.yml`.

### D2 (D-04): Cloudflare Tunnel with Access, created by API, instead of direct TLS

Chosen over Caddy with Let's Encrypt. It removes ports 80 and 443 from the firewall, hides the server IP, and puts an email one-time-PIN wall in front of a camera UI whose own auth is the only other line of defense. Trade-off: WebRTC cannot traverse the tunnel, which does not matter for motionEye's MJPEG live view, and all video bytes pass through Cloudflare.

The playbook creates the tunnel (`POST /accounts/{id}/cfd_tunnel`), pushes ingress configuration (`PUT .../cfd_tunnel/{tunnel}/configurations`) with the hostname routed to `http://motioneye:8765` and a 404 catch-all, creates a proxied CNAME to `<tunnel-id>.cfargotunnel.com`, and creates an Access application and allow-list policy. The tunnel ID and the Access application ID are written to `state/cloudflare.yml` and committed, which is what makes later runs reconcile instead of duplicate. The tunnel run token is fetched by API at deploy time and written only to the server as a Docker secret file, never to the repo.

Alternative rejected: dashboard-managed tunnel where the operator pastes a token. It needs more manual steps and leaves the hostname and Access config outside the repo.

### D3 (D-05): motionEye configuration is templated from inventory, except account hashes

`camera-N.conf` files are fully rendered from `group_vars` camera entries on every deploy. Camera numbering is stable: the inventory order defines N, and removing a camera removes its file. Each camera is rendered with `netcam_url` set to the substream when present and `netcam_high_url` set to the main stream, `movie_passthrough on`, `emulate_motion off`, `movie_output on`, `picture_output off`, and pre/post capture margins from a shared default.

`motion.conf` is rendered on first deploy only (guarded by a marker file under the config path). After that it is owned by motionEye, because the UI writes to it and it holds the account password hashes.

Alternative rejected: render `motion.conf` every run. It would revert UI-side changes including password rotations.

### D4 (D-06): First-boot account seeding via in-container Python

After the first `compose up`, the playbook runs, inside the motionEye container, a one-liner that imports `motioneye.config` and calls `set_admin_password` and `set_normal_password` with the vault values, then restarts motionEye. The seed runs only when the marker file from D3 is absent. This uses motionEye's own argon2 hashing and avoids depending on the signed HTTP API for a write.

Alternative rejected: pre-computing argon2 hashes in Ansible. Possible with passlib plus argon2-cffi on the operator machine, but adds a local dependency and couples the repo to motionEye's hash parameters.

### D5 (D-07): Digest pinning with a committed state file

`state/images.yml` records, per image, `tag` and `digest`. Compose templates reference `image: <repo>:<tag>@sha256:<digest>`. Update detection resolves the tag's current digest from the registry with `skopeo inspect` run inside a throwaway container on the server (no extra local dependency) and diffs it against the state file. Approval rewrites the state file and commits. Rollback re-renders compose from the snapshot's copy of the state file.

### D6 (D-08): Storage cap as a host systemd timer

A small shell script, installed by the deploy playbook, runs hourly from a systemd timer. It reads the recordings path and the threshold (90) from a config file, and while `df` usage exceeds the threshold it deletes the oldest `*.mp4` and matching thumbnails by modification time, then logs before/after usage and the count to the journal. It runs on the host rather than as a sidecar because it needs only `df`, `find`, and `rm`, and the host timer survives container replacement. motionEye's own per-camera `preserve_movies` days setting stays enabled as the first line of cleanup.

Alternative considered: the community `motioneye-pruner` project. It does the same thing; a 30-line script avoids a third-party dependency on a deletion path.

### D7 (D-09): Verification strategy

- Containers: `docker compose ps` JSON, assert `running` and `healthy` where a healthcheck exists. motionEye gets an HTTP healthcheck on `/`.
- Tunnel: `GET /accounts/{id}/cfd_tunnel/{tunnel}` and assert `status == healthy`; DNS: resolve hostname and assert a CNAME to the tunnel.
- Logins: motionEye's HTTP API uses a signature scheme (`_username` plus `_signature` computed from method, URI, body and the password). A small Python helper in the repo computes it and calls `GET /config/list` as each account, asserting 200. The viewer is additionally asserted to receive 403 on an admin-only endpoint.
- Cameras: `GET /config/list` returns per-camera settings; combined with motion's webcontrol `detection/status`, assert every inventory camera exists and is connected.
- Config drift: compare each camera's effective `emulate_motion` and `movie_output` to expectations.
- Pruner: `systemctl is-active` on the timer.
- No host ports: `ss -ltn` on the server and assert nothing but 22 listens on a non-loopback address.

Rotated credentials are passed at run time with `-e` or a prompt, never written back to the vault by the flow.

### D8 (D-10): Update flow control and rollback

Order: inspect, apt upgrade with reboot, resolve digests, stop if none differ, snapshot `/srv/motioneye/etc` plus rendered compose plus `state/` to `/srv/motioneye/snapshots/<timestamp>/`, pull, `compose up -d`, verify. On verification failure: automatic rollback. On success: `pause` for operator approval. On rejection: rollback and re-verify. Rollback is a playbook of its own (`rollback.yml`) that takes a snapshot timestamp, so it is also usable by hand.

On approval: fetch `motion.conf` from the server into `harvest/motion.conf` (argon2 hashes only, no camera URLs since those live in `camera-N.conf`), rewrite `state/images.yml`, and `git commit` on the operator's clone with a generated message. Push is left to the operator.

### D9 (D-12): Layout

```
inventory/hosts.yml                 server address
group_vars/all/vars.yml             cameras, hostname, allowed emails, retention days, paths
group_vars/all/vault.yml            encrypted: cf token, bootstrap passwords, camera URLs
state/cloudflare.yml                tunnel id, access app id (committed)
state/images.yml                    tag + digest per image (committed)
harvest/motion.conf                 harvested from server on approved updates (committed)
playbooks/{examine,harden,deploy,verify,update,rollback}.yml
site.yml                            examine -> harden -> deploy -> verify
update.yml                          examine -> harden(upgrade only) -> update
roles/{common,hardening,docker,cloudflare,motioneye,retention,verify}/
docs/INPUTS.md                      where every operator value comes from
docs/RUNBOOK.md                     init and update walkthroughs, rollback by hand
```

## Risks / Trade-offs

- [motionEye API signature scheme is undocumented and may change between releases] → Pin the helper to the tested motionEye version; the login check is a verification step, so a scheme change fails loudly rather than silently.
- [Decoding streams for motion detection may exceed VPS CPU] → Inspection warns on camera-to-core ratio; substream detection is supported in inventory; `framerate` defaults low.
- [Cameras on public IPs expose camera firmware and RTSP credentials to the internet] → Operator-accepted. Documented in RUNBOOK with the router-side mitigation of restricting forwards to the server IP.
- [motionEye rewrites config files; inventory and server can drift] → Camera files are re-rendered every deploy; verification detects drift in recording mode; harvesting only covers `motion.conf`.
- [Docker bypasses ufw for published ports] → Nothing is published; verification asserts no non-loopback listeners except 22.
- [Cloudflare proxies all video traffic] → Acceptable for event playback and MJPEG; Cloudflare removed its streaming prohibition in 2023.
- [Pruner deletes the wrong files] → Scoped to the recordings path and media extensions only; dry-run flag; logged.
- [API token stored in vault has broad zone DNS rights] → Token scoped to one zone; documented rotation.

## Migration Plan

Initial deployment is itself the migration: `site.yml` on a fresh server. Rollback of a failed initial deployment is to rebuild the server. For updates, see D8.

## Open Questions

- Default retention days per camera and pre/post motion margins. Defaults of 14 days and 2/5 seconds are proposed and are plain variables.
- Whether MJPEG live view through Cloudflare is smooth enough at the operator's bandwidth. If not, the fallback is to lower `stream_maxrate` and `stream_quality` in the camera template; no architectural change.

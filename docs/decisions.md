# Decisions log

Append-only. See CLAUDE.md for the rules.

## D-01 — Initial SSH key bootstrap is a standalone bash script, not an Ansible play
Date: 2026-10-12 · Scope: scripts/setup-ssh-access.sh, operator-inputs spec · Supersedes: —
Decision: Installing the operator's public key for a user on a fresh server is done by `scripts/setup-ssh-access.sh`, which takes the server address, the target user (default `root`), and the root password interactively, uses the password once over SSH, and verifies key login. It only touches `~<user>/.ssh/authorized_keys` (and creates the user if asked); it never edits `sshd_config`. The root password is passed to `ssh` through `SSH_ASKPASS_REQUIRE=force` on OpenSSH 8.4+, through `sshpass` if present on older OpenSSH, and interactively otherwise.
Why: The `operator-inputs` spec requires every Ansible flow to connect by key and forbids SSH passwords, so the step that installs the key cannot itself be a play. A dependency-free script keeps the fresh-clone bootstrap limited to SSH and git, as the same spec requires. Not touching `sshd_config` keeps hardening (key-only SSH, PermitRootLogin) in one place, the `server-hardening` play.
Accepted cost: One shell script lives outside the idempotent Ansible model the design otherwise mandates. It is safe to re-run (the key is appended only if absent), but it is not managed by a play.

## D-02 — Ops tooling is Ansible, installed locally with uv
Date: 2026-10-12 · Scope: bin/bootstrap, Makefile, ansible.cfg, requirements.yml · Supersedes: —
Decision: All server work is Ansible playbooks run from the clone. `bin/bootstrap` installs `ansible-core` plus the `ansible` collection bundle with `uv tool install`, and the collections `community.docker >=4`, `community.general >=10`, `ansible.posix >=2` from `requirements.yml`. Cloudflare resources are created with `ansible.builtin.uri` against the Cloudflare v4 API. No Terraform, no pyinfra.
Why: The target already exists, so nothing is provisioned; Ansible gives SSH-native idempotent runs and Vault for secrets, and one tool covers OS, Docker and the Cloudflare API. `uv` is the only local prerequisite beyond git and ssh.
Accepted cost: Cloudflare API calls are hand-written `uri` tasks rather than a provider with drift detection.

## D-03 — motionEye is the NVR, not ZoneMinder or Frigate
Date: 2026-10-12 · Scope: nvr-deployment spec, roles/motioneye · Supersedes: —
Decision: The NVR is motionEye from `ghcr.io/motioneye-project/motioneye`, starting at tag `0.44.0`, in Docker. ZoneMinder and Frigate are not used.
Why: motionEye meets every requirement natively (free, RTSP, several cameras, admin plus viewer accounts, motion-triggered recording), has no database so upgrades and rollbacks are file copies, and is the lightest on a small VPS where every stream is decoded on CPU. ZoneMinder keeps camera state in MariaDB and needs API seeding; Frigate's value is object detection, which is CPU-expensive here.
Accepted cost: No object detection, so outdoor cameras produce motion events from weather and shadows. Percentage-of-disk cleanup is not built in (see D-08).

## D-04 — Ingress is a Cloudflare Tunnel plus Access, created by the deploy play from an API token · Superseded by: D-19
Date: 2026-10-12 · Scope: roles/cloudflare, state/cloudflare.yml, server-hardening spec · Supersedes: —
Decision: The deploy play creates a tunnel (`POST /accounts/{id}/cfd_tunnel`), sets ingress `nvr_hostname -> http://motioneye:8765` with a 404 catch-all, a proxied CNAME to `<tunnel-id>.cfargotunnel.com`, and an Access application with one allow policy for `cloudflare_allowed_emails` by one-time PIN. The token needs Account:Cloudflare Tunnel:Edit, Account:Access Apps and Policies:Edit, Zone:DNS:Edit. Tunnel, app and policy IDs are committed in `state/cloudflare.yml`. The tunnel run token is fetched at deploy time and written only to the server. The host firewall allows inbound TCP 22 only; no container publishes a host port.
Why: Removes 80/443, TLS handling and the server IP from DNS, and adds an authentication wall in front of a camera UI whose own login is otherwise the only defense. Doing it by API keeps hostname and Access policy in the repo.
Accepted cost: The domain must be on Cloudflare nameservers. All video bytes transit Cloudflare; WebRTC would not work, which motionEye (MJPEG) does not need.

## D-05 — Camera config files are rendered every deploy; motion.conf is rendered once
Date: 2026-10-12 · Scope: roles/motioneye templates, `/srv/motioneye/etc` · Supersedes: —
Decision: `camera-N.conf` is rendered from the `cameras` list on every deploy, N being the 1-based inventory position; a camera removed from inventory has its file removed. `motion.conf` and `motioneye.conf` are rendered only when `/srv/motioneye/etc/.seeded` is absent; afterwards motionEye owns them.
Why: Camera files hold declarative inventory and must track it. `motion.conf` holds the argon2 password hashes that the operator rotates through the UI; re-rendering it would revert rotations.
Accepted cost: Global motionEye settings changed in the UI are not reproducible from the repo except through the harvested copy (D-10). Reordering cameras in inventory renumbers them and moves their media directories.

## D-06 — Bootstrap accounts are seeded by calling motionEye's own password functions inside the container
Date: 2026-10-12 · Scope: roles/motioneye seed task · Supersedes: —
Decision: On first start, when `.seeded` is absent, the play runs `python3 -c` inside the motioneye container calling `motioneye.config.set_admin_password()` and `set_normal_password()` with the vault values, writes the usernames to `motion.conf`, restarts the container, then creates `.seeded`. Later runs never touch passwords.
Why: motionEye 0.44 stores argon2 hashes and has no CLI for setting them; using its own functions avoids coupling to hash parameters and avoids a local argon2 dependency.
Accepted cost: Depends on an internal Python API; the login check in verification fails loudly if a release changes it.

## D-07 — Images are pinned by tag plus digest in state/images.yml; updates are detected with skopeo in a throwaway container · Superseded by: D-17
Date: 2026-10-12 · Scope: state/images.yml, compose template, roles/update · Supersedes: —
Decision: `state/images.yml` records `repository`, `tag` and the multi-arch index `digest` per image. Compose references `repository:tag@digest`. The update play runs `quay.io/skopeo/stable` on the server to resolve each tag's current index digest and compares it to the recorded one. Approval rewrites the file and commits.
Why: A digest makes two deploys from the same commit run identical bytes regardless of what the tag now points to, and makes rollback a re-render. Index digests are architecture-independent. Running skopeo in a container avoids a local dependency.
Accepted cost: Operators bump versions by changing the tag and letting the update play resolve the digest; a hand-edited digest is not validated until pull.

## D-08 — Storage cap is a host systemd timer deleting oldest media until usage is at or below 90 percent
Date: 2026-10-12 · Scope: roles/retention, `/usr/local/sbin/nvr-prune`, `nvr-prune.timer` · Supersedes: —
Decision: An hourly systemd timer runs a shell script that reads threshold (default 90, from `retention_max_usage_pct` in `group_vars/all/vars.yml`) and the media path from `/etc/nvr-prune.conf`, and while `df` usage of the media filesystem exceeds the threshold deletes the oldest `*.mp4`, `*.mkv`, `*.jpg` under the media path by modification time. It logs usage before and after and the number of files deleted to the journal, and supports `--dry-run`. motionEye's per-camera `preserve_movies` (default 14 days, `retention_days`) stays on.
Why: motionEye has only days-based retention; the requirement is a percentage cap. A host timer survives container replacement and needs only coreutils.
Accepted cost: Deletion is by file age across all cameras, not per camera. Thumbnails are deleted by the same rule, not by association with their movie.

## D-09 — Verification logs in through motionEye's signed-request API with run-time credentials · Superseded by: D-14
Date: 2026-10-12 · Scope: roles/verify, `roles/verify/files/meye_client.py` · Supersedes: —
Decision: A repo-owned Python helper computes motionEye's `_signature` (SHA1 over method, URI, body and the password hash) and calls `GET /config/list` as the admin and the viewer, asserting 200, and asserts the viewer gets 403 on an admin-only endpoint. Passwords come from `nvr_admin_password` and `nvr_viewer_password` extra vars when given, else from the bootstrap vault values. Verification also asserts container health, tunnel status `healthy` via the API, CNAME to the tunnel, every inventory camera present and connected, `emulate_motion off` and `movie_output on` per camera, the prune timer active, and no non-loopback listener except TCP 22.
Why: motionEye has no cookie login; the signature scheme is the only scripted path. Run-time credentials keep rotated passwords out of the repo.
Accepted cost: The helper tracks an undocumented scheme and is pinned to the tested motionEye version.

## D-10 — Update order is inspect, OS upgrade, digest diff, snapshot, upgrade, verify, approve; rollback is its own play; approval commits locally without pushing · Superseded by: D-27
Date: 2026-10-12 · Scope: update.yml, playbooks/update.yml, playbooks/rollback.yml, harvest/motion.conf · Supersedes: —
Decision: Snapshots go to `/srv/motioneye/snapshots/<UTC timestamp>/` holding `etc/`, the rendered `docker-compose.yml` and a copy of `state/`; media is excluded and never touched. Verification failure after upgrade triggers automatic rollback. On operator rejection the play rolls back and re-verifies. On approval it fetches `motion.conf` to `harvest/motion.conf` (asserting no `rtsp://` substring), rewrites `state/images.yml`, and runs `git commit` in the clone. No push.
Why: The approval gate is the only point where the repo state changes, so repo and server never disagree silently. `motion.conf` contains argon2 hashes only, so it is safe to commit; camera files contain plaintext RTSP credentials and are never harvested.
Accepted cost: Snapshots accumulate on the server; pruning them is manual. The operator pushes by hand.

## D-11 — RTSP pre-flight uses ffprobe in a throwaway container and runs as soon as Docker exists
Date: 2026-10-12 · Scope: roles/examine, site.yml, update.yml · Supersedes: —
Decision: Each camera URL is probed from the server with `ffprobe` in a container (`linuxserver/ffmpeg`), 15 s timeout, reporting codec and resolution. In `site.yml` on a fresh server it runs after the Docker role and before deploy; `examine.yml` on its own runs it when Docker is already present and reports "deferred" otherwise. In `update.yml` it runs in the examine step.
Why: Installing `ffmpeg` on the host only for a probe adds ~100 MB of packages; Docker is installed by hardening anyway. Probing still happens before any NVR container starts.
Accepted cost: On a fresh server the camera check comes after hardening, so a wrong URL is found ten minutes in rather than immediately.

## D-12 — Playbooks live in playbooks/ with a group_vars symlink
Date: 2026-10-12 · Scope: playbooks/group_vars -> ../group_vars · Supersedes: —
Decision: Entry points `site.yml`, `update.yml` are at the repo root; step playbooks are in `playbooks/`. `playbooks/group_vars` is a symlink to `../group_vars` so both locations resolve the same variables.
Why: Ansible loads `group_vars` relative to each playbook's directory, not the repo root; without the link `playbooks/*.yml` run alone would see no operator inputs.
Accepted cost: One symlink in git.

## D-13 — The camera list inside motion.conf is reconciled on every deploy, inside a marked block
Date: 2026-10-12 · Scope: roles/motioneye tasks "Reconcile camera list", "Strip camera lines" · Supersedes: —
Decision: motion.conf must list `camera camera-N.conf` for every camera file or motion ignores it. The deploy play owns those lines between `# BEGIN/END ANSIBLE MANAGED CAMERA LIST` markers and deletes any `camera camera-N.conf` line outside the block. All other lines of motion.conf stay untouched after the first render (D-05).
Why: Adding or removing a camera in inventory must take effect without re-rendering motion.conf, which would revert the operator's password hashes and UI settings.
Accepted cost: A camera added through the web UI is removed from motion.conf on the next deploy, so cameras are inventory-only.

## D-14 — Verification logs in with motionEye's session API, not a signed request
Date: 2026-10-12 · Scope: roles/verify, roles/motioneye seeding · Supersedes: D-09
Decision: motionEye 0.44 authenticates with `POST /login/` (JSON `username`, `password`) returning a `user` cookie; HMAC headers exist only for peer servers. Verification posts to `/login/` as admin and viewer from inside the motioneye container (the port is not published), asserts 200, asserts `GET /config/list/` is 200 for both and `GET /config/main/get/` is 403 for the viewer, and reads camera state from `/config/list/` plus motion's webcontrol `http://127.0.0.1:7999/<id>/detection/connection` ("Connection OK"). Everything else in D-09 (run-time credentials via `nvr_admin_password`/`nvr_viewer_password`, the other checks) stands.
Why: The signature scheme assumed in D-09 was removed in 0.44 (verified in `handlers/login.py` and `handlers/base.py` of tag 0.44.0); the session API is simpler and documented by the handler itself.
Accepted cost: A session cookie lives inside the container for the duration of the check.

## D-15 — A second Cloudflare mode accepts a dashboard-created tunnel's connector token · Superseded by: D-19
Date: 2026-10-12 · Scope: group_vars `cloudflare_mode`, vault `vault_cloudflare_tunnel_token`, roles/cloudflare, roles/verify, cloudflare-ingress spec · Supersedes: — (narrows D-04's "only" to the default)
Decision: `cloudflare_mode: api` (default) is D-04 unchanged. `cloudflare_mode: token` skips every Cloudflare API call: the operator creates the tunnel in the Zero Trust dashboard, sets its public hostname to service `http://motioneye:8765`, protects it with an Access application there, and pastes the connector token (the `eyJ...` string from `cloudflared service install <token>`) into the vault. The play writes it to `/srv/motioneye/cloudflared.env`, records the tunnel id decoded from the token's `t` field in `state/cloudflare.yml`, and verification checks the connector's own readiness instead of the API tunnel status. Account ID, Zone ID, zone name, API token and allowed emails are not required in token mode.
Why: The operator supplied a dashboard-created tunnel token for testing and no API token. Supporting the paste flow lets a first deployment proceed with the minimum of Cloudflare setup; the API mode remains for operators who want hostname and Access policy in the repo.
Accepted cost: In token mode the hostname, ingress and Access policy live only in the dashboard and cannot be verified or restored from the repo. The connector token grants the right to serve the tunnel and must be treated like a password.

## D-16 — SSH is allowed by ufw without rate limiting; fail2ban alone handles brute force
Date: 2026-10-12 · Scope: roles/hardening "Firewall allow SSH" · Supersedes: —
Decision: The ufw rule for TCP 22 is `allow`, not `limit`. Brute-force protection is fail2ban's sshd jail (5 failures in 10 min, 1 h ban, `banaction = ufw`).
Why: `ufw limit` rejects a source after 6 new connections in 30 s. Running `make verify` and `make update` back to back, or Ansible without a persistent control socket, exceeded that during testing and locked the operator out with "connection refused" for the burst. fail2ban only reacts to failed logins, so legitimate key-based automation is never blocked.
Accepted cost: Unauthenticated connection attempts are only throttled after they fail authentication, not at the packet level.

## D-17 — Pins follow a tracking tag: state/images.yml records `track` plus `digest`, and compose references `repository:track@digest`
Date: 2026-10-12 · Scope: state/images.yml, roles/motioneye compose template, roles/update · Supersedes: D-07 (schema and update-detection detail)
Decision: Each image entry has `repository`, `track` (default `latest` for both motioneye and cloudflared) and `digest` (the multi-arch index digest, which is what runs). Update detection runs `skopeo inspect --raw docker://repository:track` in a throwaway container on the server and compares `sha256(raw manifest)` with the recorded digest; the hash of the raw index equals the registry's index digest (verified against `docker buildx imagetools inspect`). On approval the new digest is written back with a human-readable version comment when the image carries `org.opencontainers.image.version`. To pin a specific release instead of following releases, set `track` to that version tag.
Why: A fixed version tag's digest never changes, so following it would never report an update; the spec requires detecting new NVR releases. With the digest in the compose reference, `latest` is informational and deployments stay byte-identical across runs.
Accepted cost: Following `latest` means an update may jump across a major release; the approval gate and rollback are the guard. motioneye images carry no version label, so the comment may read "version unknown".

## D-18 — Harvested motion.conf is committed without motionEye's internal secrets · Superseded by: D-28
Date: 2026-10-12 · Scope: roles/update "Strip motionEye's internal secrets", harvest/motion.conf · Supersedes: — (refines D-10)
Decision: Before `harvest/motion.conf` is committed, the lines `# @relay_secret` and `# @client_secret` are removed. Account password lines (argon2 hashes) and UI settings are kept. The commit is refused if any `rtsp://` string is present.
Why: motionEye regenerates both secrets on start when absent, so nothing is lost, and the client secret authenticates peer motionEye servers via HMAC, which must not live in git.
Accepted cost: A restore from the harvested file causes motionEye to mint new secrets, which only matters for peer-server setups this repo does not use.

## D-19 — Cloudflare ingress is operator-configured in the dashboard; the repo consumes one connector token and verifies the result
Date: 2026-10-12 · Scope: roles/cloudflare, roles/verify tunnel check, roles/common validation, group_vars, state/cloudflare.yml, docs/INPUTS.md §4, cloudflare-ingress / operator-inputs / deployment-verification specs · Supersedes: D-04, D-15
Decision: The `api` mode and the `cloudflare_mode` selector are removed. The operator creates the tunnel, publishes `nvr_hostname` to `http://motioneye:8765` and creates the Access application (Allow policy on emails, one-time PIN) in the Zero Trust dashboard, following a click-level walkthrough in `docs/INPUTS.md` §4. The repo takes exactly two Cloudflare inputs: `vault_cloudflare_tunnel_token` (connector token) and `nvr_hostname`. The deploy play writes the token to `/srv/motioneye/cloudflared.env`, decodes the tunnel id from the token's `t` field into `state/cloudflare.yml` (that file's only field), and makes no Cloudflare API call. Verification enforces the outcome: `cloudflared tunnel ready` succeeds and `https://nvr_hostname/` answers 302 to a `cloudflareaccess.com` login; a 200 fails as "reachable without a login wall". `cloudflare_account_id`, `cloudflare_zone_id`, `cloudflare_zone_name`, `cloudflare_allowed_emails` and `vault_cloudflare_api_token` are no longer accepted, and a leftover `cloudflare_mode` fails input validation.
Why: Only token mode has ever run against a real server; the API path was tested against a mock, the operator has no API token and does not plan one, and considers Cloudflare resources their job in the dashboard. Removing ~300 lines of untested tasks, six validations and five inputs leaves one path that is exercised on every deploy. The Access requirement of D-04 is kept as a verified outcome rather than a created resource.
Accepted cost: The repo cannot recreate any Cloudflare resource. A deleted tunnel or Access application means repeating the walkthrough and pasting a new token into the vault; nothing in `state/` restores it. Hostname, ingress and policy exist only in the dashboard and cannot be diffed from git.

## D-20 — Deploy keeps re-rendering camera files and restarting motionEye; camera settings edited in the UI are not preserved
Date: 2026-10-12 · Scope: roles/motioneye templates and handlers, `/srv/motioneye/etc/camera-N.conf` · Supersedes: — (confirms D-05)
Decision: `make deploy` renders `camera-N.conf` from the `cameras` inventory list on every run and the `Restart motioneye` handler fires whenever the rendered file differs from the one on the server, including when motionEye's UI rewrote it. No pre-render harvest, checksum store, "skip if modified on the server" gate or conflict prompt is added. A camera setting changed in the UI that must survive is moved into the inventory entry; everything else is reverted on the next deploy.
Why: Inventory is the declared source of truth for cameras (D-05). Detecting UI edits needs a second copy of each rendered file or a stored checksum plus a merge policy, which is more machinery than one camera and an occasional restart justify. The restart affects only the NVR container, not recordings on disk.
Accepted cost: Every deploy after a UI-side camera edit restarts motionEye and silently discards that edit.

## D-21 — Admin and viewer may share one password while the deployment is under test; the repo does not enforce distinct passwords
Date: 2026-10-12 · Scope: roles/common input validation, roles/verify login checks, the deployed server · Supersedes: —
Decision: Input validation keeps requiring distinct usernames and passwords of at least 8 characters and gains no distinct-password assertion. On the deployed server the admin and viewer accounts currently share one password; the operator accepts this for the testing phase and splits them in the motionEye UI before regular use. The split needs no repo change: hashes live in the server's `motion.conf` (D-05) and run-time passwords are passed as `ADMIN_PASSWORD` and `VIEWER_PASSWORD` to `make verify` and `make update`.
Why: motionEye distinguishes the accounts by username and role, and verification logs into each by username (D-14), so a shared secret cannot hide a broken viewer account. A distinctness check would only ever see bootstrap credentials, which stop mattering after the first rotation in the UI.
Accepted cost: Until the split, anyone holding the viewer password has admin rights.

## D-22 — Terminal detection for the update approval prompt lives in the Makefile; the play requires an explicit `approval`
Date: 2026-10-12 · Scope: Makefile `update` target, update.yml first play, roles/update defaults and first task, docs/RUNBOOK.md §Update · Supersedes: — (refines D-10)
Decision: `make update` sets `APPROVAL ?= $(shell [ -t 0 ] && echo prompt)` and always passes `-e approval=$(APPROVAL)`. `update.yml` asserts, in a first play before validation, examine or harden, that `approval` is one of `prompt`, `approve`, `reject`, and otherwise fails naming `make update APPROVAL=approve|reject` and `-e approval=...`. The role default `approval: prompt` is removed; the role repeats the assertion before the digest check. Direct `ansible-playbook update.yml` calls must always pass `-e approval=...`.
Why: On 2026-10-12 a run under a non-terminal stdin skipped the `pause` with only a warning, treated the empty answer as a rejection, and snapshotted, upgraded, verified and rolled back the whole stack for nothing; unattended runs would repeat this every time. The check cannot live in a task: every Ansible worker replaces its stdin with `/dev/null` (ansible-core 2.21 `executor/process/worker.py`), verified with a lookup plugin under a pseudo-terminal. GNU make's `$(shell)` sees the operator's real stdin.
Accepted cost: Running the playbook without make needs one more flag. A launcher where `[ -t 0 ]` is false but a human is present gets the fail-fast message and must pass `APPROVAL=` by hand.

## D-23 — Run-time NVR passwords are read from `ADMIN_PASSWORD` and `VIEWER_PASSWORD` in the controller environment, and make never echoes them
Date: 2026-10-12 · Scope: roles/verify/defaults/main.yml, Makefile `verify` and `update` targets, docs/INPUTS.md §3, docs/RUNBOOK.md · Supersedes: — (refines D-14)
Decision: `nvr_admin_password` defaults to `lookup('env', 'ADMIN_PASSWORD') | default(bootstrap_admin_password, true)`, and `nvr_viewer_password` likewise from `VIEWER_PASSWORD`; `-e` overrides remain. The `verify` and `update` recipes pass no `-e` password arguments, start with `@`, and echo a fixed line without values. The operator command stays `make verify|update ADMIN_PASSWORD=... VIEWER_PASSWORD=...`, which make exports into the recipe environment.
Why: Make prints each recipe line, so every run on 2026-10-12 showed both passwords in clear in the terminal and in pasted logs, and `-e` values also appear in `ps` and in Ansible's verbose output. The environment path keeps the run-time UX the operator chose (no stored passwords, D-14) at zero extra typing.
Accepted cost: The values remain visible in the operator's shell history and process environment on their own machine. Direct `ansible-playbook` callers export the variables or pass `-e`.

## D-24 — `state/images.yml` is written in file order with `sort_keys=False`, and an image without an OCI version label gets its version from running the image · Superseded by: D-25
Date: 2026-10-12 · Scope: roles/update "Write new image pins" and the snapshot's embedded pins copy, roles/update/defaults `image_version_args` · Supersedes: — (refines D-17)
Decision: Both writers use `to_nice_yaml(indent=2, sort_keys=False)`, keeping image order `motioneye`, `cloudflared` and key order `repository`, `track`, `digest`; the header comment is fixed text. Version per image: the `org.opencontainers.image.version` label; else, when the image is listed in `image_version_args` (default `{cloudflared: "version"}`), the first `version (\S+)` match from `docker run --rm <repository>:<track>@<digest> <args>` on the server, 30 second timeout, never failing the play; else `version unknown`.
Why: The approval commit `d87e04f` reordered every line of the file and wrote `cloudflared: version unknown`, because the YAML dumper sorts keys and the cloudflared image has no version label (checked with `docker buildx imagetools inspect` on 2026-10-12); its default command prints `cloudflared version 2026.10.0 (...)`. A diff that touches only the changed digest is what makes the commit reviewable.
Accepted cost: One extra container start per listed image on approval. The first approval after this change still shows a one-time reorder diff.

## D-25 — `state/images.yml` is written in file order with `sort_keys=False`, the committed file is reordered once by hand in the same change, and an image without an OCI version label gets its version from running the image
Date: 2026-10-12 · Scope: roles/update "Write new image pins" and the snapshot's embedded pins copy, roles/update/defaults `image_version_args`, state/images.yml · Supersedes: D-24
Decision: As D-24: both writers use `to_nice_yaml(indent=2, sort_keys=False)` and the header comment is fixed text; version per image is the `org.opencontainers.image.version` label, else for images listed in `image_version_args` (default `{cloudflared: "version"}`) the first `version (\S+)` match from `timeout 30 docker run --rm --network none <repository>:<track>@<digest> <args>` on the server (`failed_when: false`), else `version unknown`. Changed: the update-flow-hardening change rewrites the committed `state/images.yml` by hand to image order `motioneye`, `cloudflared` and key order `repository`, `track`, `digest`, values unchanged. The writer keeps insertion order, which is the order the file is loaded in, so the file has to start in the intended order.
Why: Under D-24 alone the file committed by `d87e04f` (alphabetical: `cloudflared` first, `digest` first) would have stayed in that order forever, because `images_new` is built by looping over the loaded pins. Reordering now with unchanged values gives the intended order at no cost, and a local render of the writer against the reordered file differs only in the version comment line.
Accepted cost: One extra container start per listed image on approval. A hand edit of `state/images.yml` that changes the order is kept by later approvals.

## D-26 — Make recipes return `ansible-playbook`'s exit status explicitly, because macOS GNU Make 3.81 ignores `.SHELLFLAGS`
Date: 2026-10-12 · Scope: Makefile `PIPE` variable, every target that uses it · Supersedes: —
Decision: `PIPE := 2>&1 | cat; exit $${PIPESTATUS[0]}` with `SHELL := /bin/bash`. `.SHELLFLAGS := -o pipefail -c` stays for make 3.82 and later, where it is redundant.
Why: On 2026-10-12, `make update </dev/null` failed the approval assertion (D-22) and still exited 0: `.SHELLFLAGS` was added in GNU Make 3.82, `/usr/bin/make` on macOS is 3.81, so `pipefail` was never set and every recipe returned `cat`'s status. Scripts and agents calling `make` could not see any failure.
Accepted cost: The recipes depend on bash's `PIPESTATUS`, which is already required by `SHELL := /bin/bash`.

## D-27 — Update approval records state in git-ignored local files and runs no git command
Date: 2026-10-12 · Scope: update.yml, playbooks/update.yml, playbooks/rollback.yml, roles/update "record" section, state/images.yml, harvest/motion.conf, safe-update spec · Supersedes: D-10
Decision: As D-10 for the order (inspect, OS upgrade, digest diff, snapshot to `/srv/motioneye/snapshots/<UTC timestamp>/` with `etc/`, compose file and pins, media excluded; upgrade; verify; approve) and for rollback (automatic on failed verification, and on rejection with re-verification). On approval the play fetches `motion.conf` to `harvest/motion.conf` (stripped per D-28, refused if it contains `rtsp://`) and rewrites `state/images.yml`. Both files are git-ignored. The play runs no git command; its final message lists the written files, the per-image old -> new digests, and tells the operator to back up `state/` and `harvest/`. Rejection reports "Nothing was recorded."
Why: The repo is a public template (D-29). An approval commit would put one deployment's pins and password hashes into version control, which is what this change removes. Approval stays the only point where local state changes, so D-10's ordering rationale holds.
Accepted cost: Git no longer keeps the history of approved pins, and nothing reminds the operator to back up except the approval message and the README. Snapshots still accumulate on the server and pruning stays manual.

## D-28 — Harvested motion.conf is a git-ignored local file, still stripped of motionEye's internal secrets
Date: 2026-10-12 · Scope: roles/update "Strip motionEye's internal secrets", harvest/motion.conf, .gitignore · Supersedes: D-18
Decision: `harvest/motion.conf` is git-ignored. Before it is written, the lines `# @relay_secret` and `# @client_secret` are removed. Account password lines (argon2 hashes) and UI settings are kept. The write is refused if any `rtsp://` string is present.
Why: Argon2 hashes are offline-crackable and must not be published, so the file cannot be tracked in a public repo. The stripping still matters because the file goes into the operator's backups.
Accepted cost: As D-18. A restore from the harvested file makes motionEye mint new internal secrets.

## D-29 — Per-deployment files are git-ignored and created from tracked `*.example` templates; the hostname is an inventory host var; pins fall back to tracked defaults
Date: 2026-10-12 · Scope: .gitignore, inventory/hosts.yml(.example), group_vars/all/vars.yml, group_vars/all/vault.yml(.example), state/images.yml(.example), state/cloudflare.yml, harvest/motion.conf, playbooks/{deploy,verify,update,rollback}.yml, Makefile `inputs` and `lint`, roles/cloudflare, operator-inputs and nvr-deployment specs · Supersedes: —
Decision: Git-ignored: `inventory/hosts.yml`, `group_vars/all/vault.yml`, `state/images.yml`, `state/cloudflare.yml`, `harvest/motion.conf` (Makefile `LIVE_FILES`). Tracked templates: `inventory/hosts.yml.example` (`ansible_host: 203.0.113.10`, `nvr_hostname: nvr.example.com`), `group_vars/all/vault.yml.example`, `state/images.yml.example` (default digests). `nvr_hostname` is a host var of `nvr` in `inventory/hosts.yml`; `group_vars/all/vars.yml` holds only shared defaults. `deploy`, `verify` and `update` load pins with the first-found form `["../state/images.yml", "../state/images.yml.example"]`. No playbook loads `state/cloudflare.yml` any more; the cloudflare role still writes it as a local record. `make inputs` checks for `inventory/hosts.yml`, `group_vars/all/vault.yml` and `.vault_pass`, printing the copy command for each missing file, and is a prerequisite of every flow target. `make lint` fails if any `LIVE_FILES` path is tracked.
Why: The repo is published and cloned by others, so no tracked file may describe a real deployment. One ignored non-secret file (the inventory) is fewer files to create and back up than a separate site vars file, whose name would also collide with `site.yml`. Without an inventory `ansible-playbook` skips every play and exits 0, so the guard has to sit in make (like D-22). The pins fallback lets a fresh clone deploy with no copy step.
Accepted cost: Backups of the live files are the operator's job. A direct `ansible-playbook` call bypasses the `inputs` guard. Deleting `state/images.yml` silently reverts the next deploy to the tracked default pins.

## D-30 — Published history is one root commit with a noreply identity; the full history stays on the local branch `master-copy`, which is never pushed or checked out
Date: 2026-10-12 · Scope: git history of `origin/master`, repo-local git config, `.git/hooks/pre-push`, `.git/info/sanitize-patterns`, local branch `master-copy` · Supersedes: —
Decision: `master` is replaced by a single orphan commit containing the sanitized tree and is force-pushed with `--force-with-lease=master:8ef25f3`. The repo-local identity is `drnetua <3127437+drnetua@users.noreply.github.com>`. The local, untracked `.git/hooks/pre-push` refuses a push of `refs/heads/master-copy`, any pushed commit whose author or committer email does not end in `@users.noreply.github.com`, and any pushed tree matching a line of `.git/info/sanitize-patterns` (an untracked list of real addresses, hostnames and names). `master-copy` (`113ac6d`, the old `8ef25f3` plus an empty commit) is the only copy of the old history. It is never checked out in the working tree, because switching to it overwrites the ignored live files and switching back deletes them; it is read with `git show master-copy:<path>` or a separate `git worktree`. SHAs cited in earlier entries (D-24, D-25: `d87e04f`) resolve only on `master-copy`.
Why: The old history carries the real server address, hostname and tunnel id, password hashes, and a personal author identity; rewriting is the only way to take them out of the published repo. A single commit avoids carrying old messages and dates that still describe the private deployment.
Accepted cost: Old SHAs stay reachable on GitHub by direct URL until GitHub purges them, so the exposed secrets are rotated regardless. Only this clone has the hook and the pattern list.

## D-31 — The agent guide keeps secrets out of the conversation and leaves server changes and the approval to the operator
Date: 2026-10-12 · Scope: docs/AGENT-GUIDE.md, README "With an AI coding agent", operator-inputs spec · Supersedes: —
Decision: `docs/AGENT-GUIDE.md` is agent-neutral Markdown. The agent never asks for, accepts, prints or writes a secret; never opens or decrypts the vault or `.vault_pass`; never runs `ansible-inventory --host/--list` or `debug var=` unfiltered (they decrypt the vault into the output); runs `make init/harden/deploy/update/rollback` only after an explicit yes; never chooses the update approval; never commits git-ignored files or pushes. A pasted secret is answered with "rotate it". The guide links `INPUTS.md`, `RUNBOOK.md` and the README instead of restating them.
Why: The transcript of an agent session is stored outside the operator's control, so a secret that enters it is exposed. This happened while this change was implemented: an unfiltered `ansible-inventory --host` printed the decrypted vault. Server changes and the approval are the operator's decisions in every flow (D-10, D-22).
Accepted cost: The operator types every secret and runs `make update` and `make verify` with passwords in their own terminal; the agent cannot complete a deployment unattended.

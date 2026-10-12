# Runbook

Operator walkthroughs. Inputs are described in [INPUTS.md](INPUTS.md).

## Initial deployment

```sh
git clone <this repo> && cd <repo>
bin/bootstrap                       # ansible via uv, collections
scripts/setup-ssh-access.sh         # once: install your key for root on the server
# create the tunnel, hostname and Access application in the Cloudflare dashboard (INPUTS.md §4)
# create inventory/hosts.yml and group_vars/all/vault.yml from their .example (README, INPUTS.md)
make check                          # validates inputs, touches nothing
make init                           # examine -> harden -> probe cameras -> deploy -> verify
```

`make init` stops at the first failed check and prints why. Safe to re-run.
Afterwards open `https://<nvr_hostname>`, pass the Cloudflare Access login (the
one-time PIN goes to an email you allowed in the dashboard policy),
log in to motionEye as the admin, and change both passwords
(Settings → General Settings). Later runs never reset them.

## Recording retention

Two independent rules bound disk use:

1. **Per camera, by age.** `retention_days` (default 14) is written to every
   camera as motionEye's "Preserve Movies" setting; motionEye deletes older
   recordings twice a day. Override per camera with `retention_days:` on the
   camera entry, or globally in `group_vars/all/vars.yml`.
2. **Whole volume, by usage.** A systemd timer (`nvr-prune.timer`, hourly) runs
   `/usr/local/sbin/nvr-prune`, which deletes the oldest recordings across all
   cameras until usage of the recordings filesystem is at or below
   `retention_max_usage_pct` (default 90). It touches only media files under
   `/srv/motioneye/media` and logs each run to the journal:

   ```sh
   journalctl -t nvr-prune -n 5
   systemctl list-timers nvr-prune.timer
   /usr/local/sbin/nvr-prune --dry-run     # show what would be deleted
   ```

Changing either value and running `make deploy` re-renders the camera files and
the prune configuration.

## Verification

```sh
make verify                                  # with bootstrap passwords
make verify ADMIN_PASSWORD=... VIEWER_PASSWORD=...   # after rotating them
```

The passwords are read from the `ADMIN_PASSWORD` and `VIEWER_PASSWORD`
environment variables (make exports them; `ADMIN_PASSWORD=... make verify` works
too) and are never echoed. Unset or empty falls back to the bootstrap passwords.

Read-only. Checks containers, tunnel, both logins, every camera streaming,
configuration against inventory, the prune timer, and that only port 22 listens.

## Update

```sh
make update                                   # with bootstrap passwords
make update ADMIN_PASSWORD=... VIEWER_PASSWORD=...   # after rotating them
```

Passwords are passed the same way as for `make verify`: through the environment,
never echoed.

What happens, in order:

1. Inputs validated; server examined (stops if this repo has never deployed here).
2. OS packages upgraded, reboot if the kernel asks for it, hardening re-applied.
3. The registry digest of every tracked image (`state/images.yml`, tag in `track`)
   is compared with the recorded one. Nothing new: the run ends here.
4. Snapshot to `/srv/motioneye/snapshots/<timestamp>/` (config, compose file,
   pins; recordings are never touched).
5. New images pulled and started, then the full verification runs. If it fails
   the snapshot is restored automatically and the run fails with the reason.
6. **Approval prompt.** Open the NVR, check live view and a recording, then type
   `approve`. Anything else restores the snapshot and records nothing.
7. On approval: `state/images.yml` gets the new digests and `harvest/motion.conf`
   gets the server's current motionEye main config (password hashes and UI
   settings, never camera URLs). Both files are git-ignored: nothing is committed.
   Copy `state/` and `harvest/` to your backup (README, "Before your first
   deploy"); they are the only record of what runs on the server.

Unattended runs: `make update APPROVAL=approve` (or `APPROVAL=reject`) skips the
prompt and applies that decision after verification. `make update` only prompts
when its stdin is a terminal; otherwise it stops before connecting to the server
with "stdin is not a terminal and no approval decision was given: run `make update
APPROVAL=approve` or `make update APPROVAL=reject`, or pass `-e
approval=approve|reject|prompt` to ansible-playbook. Nothing was changed." A
launcher that is not seen as a terminal (some multiplexer panes, IDE run buttons)
hits the same message; pass `APPROVAL=` by hand. Direct `ansible-playbook
update.yml` calls must always pass `-e approval=prompt|approve|reject`, and export
`ADMIN_PASSWORD`/`VIEWER_PASSWORD` or pass `-e nvr_admin_password=...` themselves.

To follow a fixed release instead of `latest`, set `track` for that image in
`state/images.yml` to the version tag and run `make update`. Before the first
approved update that file does not exist yet and the tracked defaults in
`state/images.yml.example` are used: copy it to `state/images.yml` first.

## Rollback by hand

```sh
ssh root@<server> ls /srv/motioneye/snapshots      # pick a timestamp
make rollback SNAPSHOT=20260101T120000Z             # default: the latest snapshot
```

Stops the containers, restores the snapshot's configuration, compose file and
image pins, starts the previous images and runs verification. Recordings stay.
Snapshots accumulate; delete old ones by hand when disk matters.

## Cameras exposed by public IP

The server pulls RTSP straight from the cameras' public addresses. Camera
firmware and RTSP credentials are therefore reachable from the internet. If the
camera-site router supports it, restrict each port forward to the server's IP
as the only allowed source.

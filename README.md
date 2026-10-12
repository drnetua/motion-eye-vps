# motion-eye-vps

Ops repo for a self-hosted camera NVR: [motionEye](https://github.com/motioneye-project/motioneye)
in Docker on one Ubuntu 24.04 server, reachable only through a Cloudflare Tunnel with a
Cloudflare Access login wall. You set up the tunnel, hostname and Access application in the
Cloudflare dashboard; the repo runs the connector from the tunnel's token and verifies the
result. The server exposes SSH and nothing else. Cameras are pulled over RTSP and recorded
only while motion is detected.

Everything is Ansible, run from a clone of this repo:

| command | what it does |
|---|---|
| `bin/bootstrap` | install Ansible and collections locally (needs `uv`, git, ssh) |
| `scripts/setup-ssh-access.sh` | one-time: install your SSH key for root on a fresh server |
| `make check` | validate inputs, touch nothing |
| `make init` | initial deployment: examine, harden, probe cameras, deploy, verify |
| `make verify` | read-only health, tunnel, logins, cameras, config, firewall checks |
| `make update` | OS upgrade, NVR image update with snapshot, verification, approval gate, rollback or record |
| `make rollback SNAPSHOT=<id>` | restore a snapshot by hand |

Start with [Before your first deploy](#before-your-first-deploy) below, then
[docs/INPUTS.md](docs/INPUTS.md) (what to provide and where to get it) and
[docs/RUNBOOK.md](docs/RUNBOOK.md) (walkthroughs). Design decisions are logged in
[docs/decisions.md](docs/decisions.md).

### With an AI coding agent

From the root of your clone, give your agent (Claude Code, Codex, Cursor, ...) this prompt:

> Read docs/AGENT-GUIDE.md and guide me through deploying to my fresh VPS.

or, later, "... guide me through updating my server". The guide keeps every
secret out of the conversation: you type passwords, tokens and camera URLs
yourself, and the agent asks before any command that changes the server.

## Before your first deploy

This repo is a template: nothing in git belongs to a real deployment. Everything
that does lives in git-ignored files in your clone. Create these before
`make init` (the flows refuse to start and name the missing file otherwise):

| file | create from | holds | secret |
|---|---|---|---|
| `.vault_pass` | `umask 077; echo '<long random password>' > .vault_pass` | the vault password | yes |
| `group_vars/all/vault.yml` | `group_vars/all/vault.yml.example`, then `make vault-encrypt` | cameras (RTSP URLs with credentials), bootstrap accounts, Cloudflare connector token | yes, encrypted |
| `inventory/hosts.yml` | `inventory/hosts.yml.example` | server address, public hostname | no |

The flows write these themselves; you do not create them:

| file | written by | holds |
|---|---|---|
| `state/images.yml` | `make update`, on approval (until then `state/images.yml.example` is used) | image digests running on the server |
| `state/cloudflare.yml` | `make deploy` | tunnel id decoded from the connector token |
| `harvest/motion.conf` | `make update`, on approval | motionEye settings and password hashes (no camera URLs) |

You also need, outside the repo: a fresh Ubuntu 24.04 server with a public IP
and root password (used once by `scripts/setup-ssh-access.sh`), your SSH key,
the RTSP URLs of your cameras, a domain on Cloudflare, and a Cloudflare tunnel
with an Access application ([docs/INPUTS.md](docs/INPUTS.md) §4).

**Back up off this machine**, after `make init` and after every approved update:
`.vault_pass`, `group_vars/all/vault.yml`, `inventory/hosts.yml`, `state/` and
`harvest/`. Keep `.vault_pass` apart from the vault file. Git does not keep
them; losing them means re-entering every input, and losing `state/images.yml`
means the next deploy falls back to the default image pins.

## Bootstrap SSH access

The deployment and update flows connect to the server as root over an SSH key
and never accept a password. Run this once against a fresh server to install
your key:

```sh
scripts/setup-ssh-access.sh
```

It asks for the server address, the remote user to grant access to (default
`root`), and the root password, which is used once over SSH and not stored.
It generates `~/.ssh/id_ed25519` if you have no key, installs the public key
in the user's `authorized_keys`, and verifies that key login works. It does
not change `sshd` settings; if `PermitRootLogin` or `PubkeyAuthentication`
would block key login, it warns and stops.

## Layout

```
site.yml / update.yml      entry points (also: make init / make update)
playbooks/                 check, examine, harden, preflight-rtsp, deploy, verify, update, rollback
roles/                     common, examine, hardening, docker, cloudflare, motioneye, retention, verify, update, rollback
inventory/hosts.yml        the server and its hostname (git-ignored; from hosts.yml.example)
group_vars/all/vars.yml    shared defaults;  vault.yml: secrets (ansible-vault, git-ignored)
state/                     image pins and tunnel id, written by the flows (git-ignored; defaults: images.yml.example)
harvest/                   server-side motionEye config harvested on approved updates (git-ignored)
docs/AGENT-GUIDE.md        prompt for an AI agent to walk you through deploy and update
```

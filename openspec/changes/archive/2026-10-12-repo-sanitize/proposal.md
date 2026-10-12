## Why

The repo is public (`github.com/drnetua/motion-eye-vps`), but it was built as the operator's private state store. It commits the real server address, the published hostname, the tunnel id, the encrypted vault holding real camera URLs, harvested password hashes, and commits authored with a personal work email. It has to become a template that anyone can clone and deploy to a fresh VPS. Nothing about a real deployment, or about who built it, may be tracked now or recoverable from history.

## What Changes

- **BREAKING** Live operator files are git-ignored and no longer tracked: `inventory/hosts.yml`, `group_vars/all/vault.yml`, `state/images.yml`, `state/cloudflare.yml`, `harvest/motion.conf`. Only `*.example` files with placeholder values are committed. Existing clones keep their files on disk (`git rm --cached`).
- `nvr_hostname` moves from the tracked `group_vars/all/vars.yml` into the inventory as a host variable, so all non-secret per-deployment values live in one ignored file, next to `ansible_host`.
- A fresh clone deploys without copying a pins file: the playbooks fall back to `state/images.yml.example`, which carries the current default digests. `state/cloudflare.yml` is still written by deploy, but no playbook loads it any more.
- **BREAKING** The update approval no longer runs `git commit`. It writes the new pins and the harvested `motion.conf` to the local ignored files and prints what changed and what to back up. Rejection is unchanged.
- `make` refuses to run any flow when a live input file is missing, and names the `.example` to copy. `make lint` fails if any live file is tracked by git.
- The README gains a "Before your first deploy" section listing each file to create, its template, whether it is secret, and what to back up off-machine. `docs/INPUTS.md`, `docs/RUNBOOK.md` and `bin/bootstrap` follow the new layout.
- New `docs/AGENT-GUIDE.md`: an agent-neutral prompt that walks an operator through first deploy and update. It keeps every secret out of the chat and asks before any server-changing command. The README has a one-line copy-paste invocation.
- The real hostname is replaced with a placeholder in the archived `cloudflare-token-only` design.
- `docs/initial-prompt.txt` (the original brief pasted into the first explore session) is deleted. Nothing references it.
- One-time repository operations: a repo-local git identity (GitHub noreply), a local `pre-push` hook that refuses the `master-copy` branch, history squashed to a single root commit, and a force-push of `master`. The operator runs the force-push and the secret rotation.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `operator-inputs`: secrets and all other per-deployment inputs are stored in git-ignored local files created from tracked placeholder templates, never committed. The hostname input moves to the inventory. Missing inputs are reported with the template to copy. Setup and backup are documented as a checklist, with an agent guide.
- `safe-update`: on approval, state is written to the local clone instead of committed. Diff-stability requirements now apply to the written file, not to a commit.
- `nvr-deployment`: digest pins are read from the local pins file, or from the tracked default pins when none exists yet, instead of "the same repo commit".

## Impact

- Code: `.gitignore`, `Makefile` (input guard, lint check), `ansible.cfg` (unchanged inventory path), `playbooks/{deploy,verify,update,rollback}.yml` (`vars_files`), `roles/update/tasks/main.yml` (commit step removed, messages), `roles/common/tasks/main.yml` (hostname message), `roles/cloudflare/tasks/main.yml` (comment), `group_vars/all/vars.yml`, `bin/bootstrap`.
- New tracked files: `inventory/hosts.yml.example`, `state/images.yml.example`, `docs/AGENT-GUIDE.md`.
- Docs: `README.md`, `docs/INPUTS.md`, `docs/RUNBOOK.md`, `docs/decisions.md` (new entries superseding D-10 and D-18, plus layout, history and agent-guide decisions), `openspec/changes/archive/2026-10-12-cloudflare-token-only/design.md` (placeholder hostname).
- Git: history rewritten to one commit, and `origin/master` force-pushed. Old SHAs cited in D-24 and D-25 then resolve only on the local `master-copy` branch.
- Live server: untouched. `make deploy` after the change must report no changed container.
- Operator (outside the repo): rotate the camera password, the tunnel connector token and both NVR passwords, which were exposed in history or in local notes.

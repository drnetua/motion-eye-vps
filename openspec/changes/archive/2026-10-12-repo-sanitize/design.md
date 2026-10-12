## Context

See proposal.md (Why). Current state, as inspected:

- Tracked live data: `inventory/hosts.yml` (real `ansible_host`), `group_vars/all/vars.yml:9` (`nvr_hostname`), `state/cloudflare.yml` (tunnel id), `group_vars/all/vault.yml` (encrypted, real camera URL), `harvest/motion.conf` (argon2 hashes), `openspec/changes/archive/2026-10-12-cloudflare-token-only/design.md:62` (hostname). The camera IP and connector token appear only in the git-ignored `_user_info.txt`, never in history.
- History: 7 commits. Five are authored by a personal work email, and the real IP, hostname and tunnel id enter in `d0c2edc` and `4753ad4`.
- `state/images.yml` and `state/cloudflare.yml` are loaded through `vars_files` in `playbooks/{deploy,verify,update}.yml`; `playbooks/rollback.yml` loads only `cloudflare.yml`. Nothing reads `cloudflare_tunnel_id` after it is written (`roles/cloudflare/tasks/main.yml:19-29`).
- The approval step commits in `roles/update/tasks/main.yml:226-245` (D-10, D-18).
- Local branch `master-copy` (`113ac6d`) is `8ef25f3` plus one empty `.WIP` commit, has no upstream, and is the operator's full-history backup.
- With no inventory file, `ansible-playbook` warns "provided hosts list is empty", skips every play and exits 0.

## Goals / Non-Goals

**Goals:**
- After the force-push, `git log` on GitHub shows one commit, authored by the GitHub noreply identity. Neither its tree nor its message contains the real IP, hostname, tunnel id, camera address, password hash or personal name.
- The operator's clone keeps working with no re-entry of inputs. `make check` passes, and `make deploy` reports no changed container on the live server.
- A newcomer gets from a fresh clone to `make init` using only the README checklist, or with `docs/AGENT-GUIDE.md` driving an agent.

**Non-Goals:**
- Purging GitHub's cached views of old SHAs. That is an optional request to GitHub Support, outside the repo.
- Rewriting `docs/decisions.md` entries. The log is append-only, so citations of old SHAs stay and are explained by a new entry.
- Removing the `cloudflare_mode` guard, pruning snapshots, or anything else from the earlier loose-end list.
- Secret rotation inside the repo. The operator does it in the camera UI, the Zero Trust dashboard and the motionEye UI.

## Decisions

### 1. Live-file set and where the hostname goes
Ignored: `inventory/hosts.yml`, `group_vars/all/vault.yml`, `state/images.yml`, `state/cloudflare.yml`, `harvest/motion.conf`. Tracked templates: `inventory/hosts.yml.example`, `group_vars/all/vault.yml.example` (exists), `state/images.yml.example`. `nvr_hostname` moves from `vars.yml` into `inventory/hosts.yml` as a host variable of `nvr`. Inventory-file host vars outrank playbook `group_vars/all`, and the key is deleted from `vars.yml` anyway. `vars.yml` stays tracked: it now holds only defaults (retention, motion, paths) that are not specific to a deployment.
Placeholders: server `203.0.113.10` (TEST-NET-3, the same block the camera examples use) and hostname `nvr.example.com`.
Alternative rejected: a separate ignored `group_vars/all/site.yml`. It's one more file to create and back up, and its name collides with the `site.yml` playbook.

### 2. Default pins without a copy step
`vars_files` uses Ansible's first-found list form: `- ["../state/images.yml", "../state/images.yml.example"]` in `deploy`, `verify` and `update`. `state/images.yml.example` carries today's `state/images.yml` content, which is public registry digests. The first approved update writes `state/images.yml`, and from then on the local file wins.
Alternatives rejected: having `make check` copy the example, which is a side effect in a validate-only target; and requiring a manual copy, which is one more step in which a newcomer can pin nothing.

### 3. `state/cloudflare.yml` is written but no longer loaded
The cloudflare role keeps writing it, because cloudflare-ingress requires the tunnel id to be recorded. The `../state/cloudflare.yml` entry is removed from all four playbooks' `vars_files`, since no task reads the variable, and a fresh clone would otherwise fail on a missing file. The header comment changes from "Committed so a token for a different tunnel shows up as a diff" to a local-record wording.

### 4. Approval writes, never commits
The shell task "Commit to the ops repo" is deleted. The final message lists `state/images.yml` and `harvest/motion.conf` as written, repeats the per-image old to new digests, and says to back both up. The RTSP assert stays, reworded "refusing to write". The rejection message becomes "Nothing was recorded." The approval stays the only point where local state changes, so D-10's ordering rationale still holds.

### 5. Input guard in the Makefile
A new `inputs` target runs `test -f` on `inventory/hosts.yml`, `group_vars/all/vault.yml` and `.vault_pass`, and for each missing file prints `missing <file>: cp <file>.example <file>` (for `.vault_pass`: the `umask 077; echo ... > .vault_pass` line). It is a prerequisite of `check init examine harden deploy verify update rollback`. It sits in make rather than Ansible because a missing inventory makes `ansible-playbook` exit 0 having done nothing. That is also where D-22 put the TTY detection.
Accepted cost: a direct `ansible-playbook` call bypasses the guard and gets Ansible's own empty-inventory warning.

### 6. Lint refuses tracked live files
`make lint` runs `git ls-files --error-unmatch` against each ignored live path and fails, naming the path, if any is tracked. This catches a `git add -f`, the only way an ignored file gets in. The existing "vault is encrypted" check stays: it now protects the file at rest on disk and in the operator's backups.

### 7. History rewrite and protection of `master-copy`
Order: all file changes are made and checked on `master` first. Then:
1. Run `git config user.name drnetua` and `git config user.email 3127437+drnetua@users.noreply.github.com` in the repo's local config. This identity already appears in history, from the GitHub web commit.
2. Install `.git/hooks/pre-push`. It refuses any push whose local or remote ref is `refs/heads/master-copy`, any pushed commit whose author or committer email does not end in `@users.noreply.github.com`, and any pushed commit whose tree matches a line of `.git/info/sanitize-patterns`.
3. Run `git rm --cached` on the live paths, then `git checkout --orphan sanitized`, commit the whole tree as one commit, and run `git branch -M sanitized master`.
4. Scan the tree: `git grep -f .git/info/sanitize-patterns` on the new commit must find nothing, and `git log master` must show exactly one commit. The pattern file lives under `.git/info/` and is never tracked. It holds one fixed string per line: the real IP, hostname, tunnel-id prefix, camera IP, the personal name and email domain, and `argon2`. It is created locally from the operator's notes, so the patterns themselves never reach the published repo.
5. The operator runs `git push --force-with-lease=master:8ef25f3 origin master`.

`master-copy` is never checked out in this working tree. Leaving `master` for it would overwrite the ignored live files, and coming back would delete them, because they are tracked there and absent here. Old content is read with `git show master-copy:<path>` or in a separate `git worktree add`.
Alternatives rejected: `git filter-repo`, which keeps 7 commits whose messages and dates still describe the private deployment and is a new tool for one run; and a bundle outside the repo, because the operator chose the existing branch.

### 8. Agent guide content
`docs/AGENT-GUIDE.md` follows the outline agreed in explore. It has hard rules: no secret enters the chat; the agent never opens `vault.yml`, `.vault_pass` or `_user_info.txt`; it asks before `make init/harden/deploy/update/rollback`; it never answers the update approval; it never commits ignored files; and a failed check means fixing inputs, not roles. Flow A is the first deploy and Flow B is an update. Each step names who acts and links the existing section of `INPUTS.md` or `RUNBOOK.md` instead of copying it. Defaults chosen where explore left a question open:
- A server-changing command runs after the operator's explicit yes. The guide also offers `! make ...` or the operator's own terminal, which `make update` needs anyway for its TTY prompt.
- A pasted secret means the agent tells the operator to rotate it.
- The guide doesn't mention `master-copy`, because that branch exists only in this one clone.

### 9. Decisions log
New entries, numbered from the next free number (D-27 at the time of writing):
- Approval records state locally and runs no git command; supersedes D-10, keeping its ordering and snapshot parts.
- Harvested `motion.conf` is git-ignored and still stripped of internal secrets; supersedes D-18.
- The live-file set, templates, hostname as an inventory host var, and default pins fallback, from decisions 1 to 3 and 5 to 6.
- History is a single root commit; repo-local noreply identity; `pre-push` hook; `master-copy` is local only and never checked out; SHAs cited in D-24 and D-25 resolve only on `master-copy`.
- The agent guide's secret and confirmation rules.

The archived design's hostname is replaced with `nvr.example.com`. That is the only edit to an archive, because the history rewrite publishes the archive anew.

## Risks / Trade-offs

- [The operator loses `state/` or the vault, since git no longer backs them up] → The README checklist names the backup set (`.vault_pass`, `group_vars/all/vault.yml`, `inventory/hosts.yml`, `state/`, `harvest/`). Agent-guide Flow A ends with the backup step, and every approval message repeats it.
- [The force-push hits a remote that moved since `8ef25f3`] → `--force-with-lease` pinned to `8ef25f3` refuses the push.
- [Old SHAs stay reachable on GitHub by direct URL for a while] → Rotating the secrets is what actually closes the exposure. An optional GitHub Support purge request is listed as an operator task.
- [Someone checks out `master-copy` here and loses live files] → Design 7's rule appears in the decisions entry, and the operator keeps the backup set anyway.
- [Inventory host var not picked up, so verify hits the wrong hostname] → `make check` prints the hostname in its summary line. The verification run on the live server (task) confirms the tunnel check uses it.

## Migration Plan

For this clone (and any other existing clone):
1. Pull the change. Ignored live files stay on disk.
2. Move `nvr_hostname` from the old `vars.yml` value into `inventory/hosts.yml` (done by the apply task for this clone, and documented for others).
3. Run `make check`.
4. Run `make deploy` and expect no changed container.

Rollback before the force-push: `git reset --hard 8ef25f3` on `master` (live files are ignored and untouched). After the push, `master-copy` still holds the full history, and pushing it back is a deliberate act the hook has to be bypassed for.

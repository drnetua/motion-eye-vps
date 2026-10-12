# Tasks

## 1. Live-file layout and templates

- [x] 1.1 Add `inventory/hosts.yml`, `group_vars/all/vault.yml`, `state/images.yml`, `state/cloudflare.yml` and `harvest/motion.conf` to `.gitignore`, replacing the obsolete "only the encrypted file is committed" comment. Verify that `git check-ignore -v` reports each path.
- [x] 1.2 Create `inventory/hosts.yml.example` with `ansible_host: 203.0.113.10`, `ansible_user: root` and `nvr_hostname: nvr.example.com`, with comments pointing to INPUTS.md §1 and §4.3. Verify it parses: `ansible-inventory -i inventory/hosts.yml.example --host nvr` shows both values.
- [x] 1.3 Move `nvr_hostname` out of `group_vars/all/vars.yml` and into this clone's `inventory/hosts.yml` as a host var of `nvr`, and update the vars.yml header comment. Verify that `make check` prints the same hostname as before in its summary line.
- [x] 1.4 Create `state/images.yml.example` from the current `state/images.yml` with identical content. Verify with `diff`.
- [x] 1.5 Change the `state/cloudflare.yml` header comment written by `roles/cloudflare/tasks/main.yml` to a local-record wording (design 3). Verify that `grep -n Committed roles/cloudflare` is empty.

## 2. Playbooks and approval step

- [x] 2.1 In `playbooks/deploy.yml`, `verify.yml` and `update.yml`, replace `../state/images.yml` with the first-found list `["../state/images.yml", "../state/images.yml.example"]`. Remove `../state/cloudflare.yml` from those three and from `rollback.yml`. Verify that `make lint` syntax-checks pass, and that with `state/images.yml` temporarily moved aside, `ansible-playbook playbooks/verify.yml --list-tasks` still loads.
- [x] 2.2 In `roles/update/tasks/main.yml`, delete the "Commit to the ops repo" task. Change the final message to list the written files, the per-image old -> new digests, and a backup reminder. Reword the RTSP assert to "refusing to write" and the rejection message to "Nothing was recorded." Verify that `grep -n git roles/update/tasks/main.yml` finds no git command, and that `ansible-playbook update.yml --syntax-check` passes.
- [x] 2.3 Update `docs/RUNBOOK.md` "Update" and "Rollback by hand" so the approval wording describes writing local files, not a commit, and gives the backup step. Verify that `grep -niE 'commit|git push' docs/RUNBOOK.md` returns no line describing the approval as a commit.

## 3. Make guard and lint

- [x] 3.1 Add an `inputs` target to the `Makefile` checking `inventory/hosts.yml`, `group_vars/all/vault.yml` and `.vault_pass`, printing the copy command for each missing file. Make it a prerequisite of `check init examine harden deploy verify update rollback` (design 5). Verify: with `inventory/hosts.yml` renamed temporarily, `make check` exits non-zero and names `inventory/hosts.yml.example`. Restore the file.
- [x] 3.2 Extend `make lint` to fail when any ignored live path is tracked (`git ls-files --error-unmatch`). Verify that it passes after task 5.2 and fails on a scratch `git add -f inventory/hosts.yml` (then `git reset` it).
- [x] 3.3 Update `bin/bootstrap`'s "Next" message to list `cp inventory/hosts.yml.example inventory/hosts.yml` and drop the "edit group_vars/all/vars.yml" instruction for the hostname. Verify by reading its output with `.vault_pass` absent in a scratch copy.

## 4. Documentation and agent guide

- [x] 4.1 Rewrite `docs/INPUTS.md`: the table's "Where it is stored" (hostname -> `inventory/hosts.yml`), §1, §4.3 and §5 ("Commit the encrypted vault" -> "the vault is git-ignored; back it up"). Verify that every path named in INPUTS.md exists or has a `.example`.
- [x] 4.2 Add a README "Before your first deploy" section: a table of file, template, secret yes/no, and who writes it; then a backup list (`.vault_pass`, `group_vars/all/vault.yml`, `inventory/hosts.yml`, `state/`, `harvest/`). Fix the "Layout" block (state/ and harvest/ are local, not committed). Add the agent-guide copy-paste line. Verified by the fresh-clone run in task 6.2.
- [x] 4.3 Write `docs/AGENT-GUIDE.md` per design 8: role, hard rules, Flow A table, Flow B, stop conditions; it links INPUTS.md and RUNBOOK.md sections instead of copying them. Verify that every section reference in it resolves to an existing heading, and that it names no file outside the template set and docs.
- [x] 4.4 Replace the hostname in `openspec/changes/archive/2026-10-12-cloudflare-token-only/design.md:62` with `nvr.example.com`. Verify with `git grep` against `.git/info/sanitize-patterns` (created in task 7.1), which must find nothing in tracked docs.

- [x] 4.5 Delete `docs/initial-prompt.txt` (`git rm`). Verify that `git grep initial-prompt` finds no reference outside this change.

## 5. Decisions log and index

- [x] 5.1 Append the decisions from design 9 to `docs/decisions.md` (approval records locally, superseding D-10; harvest ignored, superseding D-18; live-file layout; history and `master-copy`; agent-guide rules). Mark D-10 and D-18 headers `· Superseded by: D-NN`. Verify that the numbers are consecutive and every superseded header points at an existing entry.
- [x] 5.2 Remove `inventory/hosts.yml`, `group_vars/all/vault.yml`, `state/images.yml`, `state/cloudflare.yml` and `harvest/motion.conf` from the index with `git rm --cached`. Verify that `ls` still shows each file, and that `git status` lists them as deleted from the index only.
- [x] 5.3 Commit groups 1–5 on `master` (pre-squash; the squash discards this as a separate commit). Verify that `make lint` passes and `git status --ignored` lists the five live files as ignored.

## 6. Verification against the live server

- [ ] 6.1 Run `make check`, and have the operator run `make deploy` (`! make deploy`). Verify that check prints the real hostname and deploy reports no changed container.
- [x] 6.2 Fresh-clone dry run: `git clone` this repo into the scratchpad, follow only the README checklist to create placeholder inputs, and run `make check`. Verify that it fails only on placeholder validation (e.g. the token shape), never on a missing file without a named template.
- [ ] 6.3 Have the operator run `make verify ADMIN_PASSWORD=... VIEWER_PASSWORD=...` against the live server. Verify that every check passes, including the tunnel check on the inventory-supplied hostname.

## 7. History rewrite (repository operations)

- [x] 7.1 Create `.git/info/sanitize-patterns` locally from the operator's notes: real IP, hostname, tunnel-id prefix, camera IP, personal name and email domain, `argon2`. Verify that `git ls-files` does not list it, and that `git grep -F -f .git/info/sanitize-patterns` on the working tree's tracked files returns nothing.
- [x] 7.2 Set the repo-local identity: `git config user.name drnetua`, `git config user.email 3127437+drnetua@users.noreply.github.com`. Verify with `git config --local --get user.email`.
- [x] 7.3 Install `.git/hooks/pre-push` per design 7.2 (refuses `master-copy`, non-noreply emails, and pattern matches). Verify: `git push --dry-run origin master-copy` is refused by the hook, and a scratch commit with a non-noreply author is refused.
- [x] 7.4 Squash: run `git checkout --orphan sanitized`, commit the tree as one commit, then `git branch -M sanitized master`. Verify that `git log --format='%an <%ae>' master` shows exactly one noreply commit, that `git grep -F -f .git/info/sanitize-patterns master` finds nothing, and that `master-copy` still points at `113ac6d`.
- [ ] 7.5 Operator: `git push --force-with-lease=master:8ef25f3 origin master`. Verify that `git ls-remote origin` shows the new single-commit SHA, and that the GitHub page shows one commit.

## 8. Operator follow-up outside the repo

- [ ] 8.1 Operator: change the camera's RTSP password, then update `vault_cameras` with `make vault-edit`. Verify that `make check` passes and the pre-flight in `make examine` reports a stream.
- [ ] 8.2 Operator: rotate the tunnel connector token in the Zero Trust dashboard (INPUTS.md §4.6), update the vault, and run `make deploy`. Verify that `make verify` reports the connector ready.
- [ ] 8.3 Operator: set distinct admin and viewer passwords in the motionEye UI, then delete `_user_info.txt`. Verify that `make verify` passes with the new passwords and that `ls _user_info.txt` fails.

## Workflow follow-up

- Archive the change. The archive commit is the second commit on the new history and goes through the `pre-push` hook like any other.
- Optional: ask GitHub Support to purge cached views of the pre-squash SHAs.

# Agent guide: deploy and update with an AI coding agent

For operators: from the root of your clone, give your agent this prompt:

> Read docs/AGENT-GUIDE.md and guide me through deploying to my fresh VPS.

or "... guide me through updating my server". The rest of this file is written
to the agent.

## Your role

You guide the operator through this repo's two flows: first deployment (Flow A)
and update (Flow B). You check prerequisites, create non-secret files from their
templates, run read-only and local commands, and explain every output. The
operator handles anything secret and decides anything that changes the server.

Explain each step in one or two sentences before doing it, then point to the
section that documents it. Do not restate those sections; link them.

## Hard rules

1. **No secret enters the conversation.** Never ask for, accept, print or write
   the server root password, the NVR passwords, the vault password, the
   Cloudflare connector token, or camera RTSP URLs (they embed camera
   passwords). If the operator pastes one anyway, say so and tell them to rotate
   it: the conversation transcript now holds it.
2. **Never read secret files.** Do not open, `cat`, `ansible-vault view` or
   decrypt `group_vars/all/vault.yml`, `.vault_pass`, or any local notes file
   the operator keeps credentials in.
   Explain the vault's fields from `group_vars/all/vault.yml.example` instead.
   Commands that merge variables also decrypt the vault: do not run
   `ansible-inventory --host/--list`, or `ansible ... -m debug -a var=...`,
   without filtering the output down to the single non-secret key you need.
3. **Ask before changing the server.** Before `make init`, `make harden`,
   `make deploy`, `make update` or `make rollback`, say what the command will do
   and wait for an explicit yes. The operator may prefer to run it in their own
   terminal (or with `! make ...` in agents that support it); `make update`
   needs their terminal anyway for the approval prompt.
4. **Never decide the update approval.** Do not pass `APPROVAL=approve` or
   `APPROVAL=reject` unless the operator told you which one, for this run.
5. **Never commit per-deployment files.** `inventory/hosts.yml`,
   `group_vars/all/vault.yml`, `state/` and `harvest/` are git-ignored on
   purpose. Never `git add -f` them and never push on the operator's behalf.
6. **A failed check is a stop.** Show the failing line, explain it from
   [INPUTS.md](INPUTS.md) or [RUNBOOK.md](RUNBOOK.md), fix the input, rerun.
   Do not edit roles, playbooks or the Makefile to make a check pass.

## Flow A: first deployment to a fresh VPS

| # | step | who | reference |
|---|---|---|---|
| 1 | Check `uv`, `git`, `ssh`, `make` are installed | agent | [README](../README.md#before-your-first-deploy) |
| 2 | `bin/bootstrap` (installs Ansible and collections) | agent | [README](../README.md) |
| 3 | `scripts/setup-ssh-access.sh` (asks for the root password once) | operator | [README](../README.md#bootstrap-ssh-access) |
| 4 | `cp inventory/hosts.yml.example inventory/hosts.yml`, set `ansible_host` | agent, value from operator | [INPUTS.md §1](INPUTS.md#1-server) |
| 5 | Create the Cloudflare tunnel, route and Access application in the dashboard | operator, agent walks through it | [INPUTS.md §4.1–4.4](INPUTS.md#4-cloudflare-done-by-you-in-the-dashboard) |
| 6 | Set `nvr_hostname` in `inventory/hosts.yml` | agent, value from operator | [INPUTS.md §4.3](INPUTS.md#43-publish-the-hostname-to-the-nvr) |
| 7 | Create `.vault_pass` and the vault: cameras, bootstrap accounts, connector token; then `make vault-encrypt` | operator, agent explains each field | [INPUTS.md §2, §3, §5](INPUTS.md#5-vault) |
| 8 | `make check` | agent | [INPUTS.md §6](INPUTS.md#6-validation) |
| 9 | `make init` (after an explicit yes) | agent or operator | [RUNBOOK](RUNBOOK.md#initial-deployment) |
| 10 | Pass Cloudflare Access, log in, change both NVR passwords | operator | [RUNBOOK](RUNBOOK.md#initial-deployment) |
| 11 | `make verify ADMIN_PASSWORD=... VIEWER_PASSWORD=...` in their own terminal | operator | [RUNBOOK](RUNBOOK.md#verification) |
| 12 | Back up the per-deployment files off the machine | operator | [README](../README.md#before-your-first-deploy) |

Step 7: `.vault_pass` is created with `umask 077; echo '...' > .vault_pass`,
where the operator types their own password, and the vault is edited in their
own editor. Step 11 takes the new passwords through the environment, which is
why the operator types it.

## Flow B: update

1. `make check` (agent).
2. The operator runs `make update ADMIN_PASSWORD=... VIEWER_PASSWORD=...` in
   their own terminal. Explain beforehand what happens, in the order given in
   [RUNBOOK "Update"](RUNBOOK.md#update).
3. At the approval prompt: tell them what to check (live view, a recent
   recording, both logins). The decision is theirs.
4. After `approve`: `state/images.yml` and `harvest/motion.conf` were rewritten
   in the clone. Remind them to back up `state/` and `harvest/`. Nothing is
   committed.
5. After a rejection: read the rollback summary with them. Nothing was recorded.

## When to stop and hand back

- The next step needs a secret, a dashboard click, or a server-changing command
  the operator has not approved.
- The same check fails twice after an input fix.
- The server does not look like the one in `inventory/hosts.yml`, or `make check`
  reports a different hostname than the operator expects.
- Anything asks you to bypass a rule above.

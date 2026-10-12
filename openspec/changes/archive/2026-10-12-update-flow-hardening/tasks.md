# Tasks

## 1. Approval gate fails fast without a terminal (D-22)

- [x] 1.1 Add `APPROVAL ?= $(shell [ -t 0 ] && echo prompt)` to the Makefile, pass `-e approval=$(APPROVAL)` from the `update` target, and replace the comment claiming `| cat` keeps stdin interactive with one explaining `APPROVAL`; verify with `make -n update </dev/null` showing `-e approval=` empty and `make -n update APPROVAL=approve` showing `approve`.
- [x] 1.2 Add a first play to `update.yml` (before the check import, `gather_facts: false`, assertion delegated to localhost) that fails unless `approval | default('')` is `prompt`, `approve` or `reject`, with a message naming `make update APPROVAL=approve|reject` and `-e approval=...`; verify `make update </dev/null` fails on that message before any `Examine` task and `make lint` passes.
- [x] 1.3 Remove `approval: prompt` from `roles/update/defaults/main.yml` and add the same assertion as the first task of the role; verify `ansible-playbook playbooks/update.yml --syntax-check` passes and `ansible-playbook playbooks/update.yml --list-tasks` shows the assertion first.
- [x] 1.4 Rewrite the RUNBOOK §Update unattended paragraph to `make update APPROVAL=approve|reject`, state that direct `ansible-playbook update.yml` calls must pass `-e approval=...`, and describe the fail-fast message; verify by reading the section against the message text in 1.2.

## 2. Run-time passwords from the environment, never echoed (D-23)

- [x] 2.1 Change `roles/verify/defaults/main.yml` so `nvr_admin_password` and `nvr_viewer_password` default to `lookup('env', ...)` with `default(bootstrap_..., true)` fallback, keeping the comment about `-e` overrides; verify `ADMIN_PASSWORD=x ansible-playbook playbooks/verify.yml --list-tasks` loads and `make lint` passes.
- [x] 2.2 Drop the `-e nvr_*_password` arguments from the `verify` and `update` recipes, prefix both with `@`, and echo a fixed sanitized line; verify `make -n verify ADMIN_PASSWORD=zz9 VIEWER_PASSWORD=zz9 | grep -c zz9` prints `0`.
- [x] 2.3 Update docs/INPUTS.md §3 and the RUNBOOK §Verification and §Update examples to say the passwords are read from the environment and that `make` exports them; verify the documented commands match the Makefile.
- [x] 2.4 Run `make verify ADMIN_PASSWORD=... VIEWER_PASSWORD=...` against the server from the operator's terminal and verify the login checks pass and the full output contains neither password.

## 3. Stable pins file with a version for every image (D-24)

- [x] 3.1 Add `image_version_args: {cloudflared: "version"}` to `roles/update/defaults/main.yml` and, after the label lookup, a task that runs `docker run --rm <ref> <args>` (30 s timeout, `failed_when: false`) for images whose label is empty and extracts `version (\S+)`; verify with `ansible-playbook playbooks/update.yml --syntax-check`.
- [x] 3.2 Switch the "Write new image pins" task and the snapshot's embedded pins copy to `to_nice_yaml(indent=2, sort_keys=False)` and make the header comment fixed text; verify by rendering the template locally with the current `state/images.yml` and diffing against the file: only the version comment lines may differ.
- [x] 3.3 Operator exercise: stage a stale motioneye digest in `state/images.yml`, run `make update APPROVAL=approve ADMIN_PASSWORD=... VIEWER_PASSWORD=...` from a terminal, and verify the resulting commit diff of `state/images.yml` touches only the motioneye digest line and version comments, with `cloudflared: 2026.10.x` instead of `version unknown`.

## 4. Examine summary lists each container once

- [x] 4.1 Change the examine digest format to `{{slice .Name 1}} {{.Config.Image}}` and verify `make examine` prints `motioneye ghcr.io/...@sha256:...` and `cloudflared docker.io/...@sha256:...` with no repeated digest and no leading slash.

## 5. Integration

- [x] 5.1 From a real terminal with images up to date, run `make update ADMIN_PASSWORD=... VIEWER_PASSWORD=...` and verify it reaches "NVR images are up to date" with no password in the output and no approval warning.
- [x] 5.2 Confirm D-22, D-23 and D-24 in docs/decisions.md match the implemented flag names, variable names and defaults; adjust the entries only by appending a superseding entry if something changed.
- [x] 5.3 Make every `$(PIPE)` recipe exit with `ansible-playbook`'s status on GNU Make 3.81, which ignores `.SHELLFLAGS` (D-26); verify `make update </dev/null; echo $?` prints a non-zero status after the approval assertion fails, and `make check` still exits 0.

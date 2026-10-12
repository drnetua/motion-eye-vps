# Design

## Context

See proposal.md for motivation. Facts that shape the approach, all verified on 2026-10-12:

- Ansible's `pause` decides interactivity in the controller's main process (`os.isatty` on stdin plus a foreground process-group check) and, when it fails, only warns and returns an empty answer. The update role then treats the empty answer as a rejection.
- Task code cannot repeat that test: every worker process replaces its stdin with `/dev/null` (ansible-core 2.21, `executor/process/worker.py`). A role-local lookup plugin under a pseudo-terminal reported no terminal; the same test in a plain shell under the same pseudo-terminal reported one.
- GNU make exports command-line variables to recipe environments, and `$(shell [ -t 0 ])` sees make's own stdin. Make prints every recipe line unless it starts with `@`.
- `to_nice_yaml` passes keyword arguments to the YAML dumper, so `sort_keys=False` preserves insertion order. `images_new` is built by looping over the existing pins, so insertion order is the file's order.
- The cloudflared image carries no `org.opencontainers.image.version` label; its default command is `version`, printing `cloudflared version 2026.10.0 (built ...)`. The motionEye image has the label.
- The Makefile is the documented entry point (README, RUNBOOK). Direct `ansible-playbook` invocations are documented only for unattended runs that already pass `-e approval=...`.
- The tasks that receive passwords (`verify: Run motionEye checks inside the container`, `motioneye: Set admin and viewer passwords`) already carry `no_log`.

## Goals / Non-Goals

**Goals:**
- A non-interactive `make update` fails before touching the server unless the decision is explicit.
- Passwords never appear in make's recipe echo; the operator keeps typing `make update ADMIN_PASSWORD=... VIEWER_PASSWORD=...`.
- An approval commit diff of `state/images.yml` shows only the lines that changed, with a real version for every image.
- The examine summary stays one line per container.

**Non-Goals:**
- Hiding passwords from the operator's own shell history or from `ps` on the operator machine.
- Detecting the terminal from inside Ansible for direct `ansible-playbook` calls; those must state `approval` explicitly.
- Pruning snapshots on the server, or any other update-flow feature.

## Decisions

### Terminal detection lives in the Makefile; the play requires an explicit `approval` (D-22)

`make update` computes `APPROVAL ?= $(shell [ -t 0 ] && echo prompt)` and always passes `-e approval=$(APPROVAL)`. `update.yml` gains a first play, before validation and examine, that asserts `approval` is one of `prompt`, `approve`, `reject` and otherwise fails with: "stdin is not a terminal: run `make update APPROVAL=approve` or `APPROVAL=reject`, or pass `-e approval=...`". The role default `approval: prompt` is removed, so the same assertion in the role (kept as a second guard before the digest check) also fails loudly for anyone running `playbooks/update.yml` alone.

Alternatives considered:
- A lookup or action plugin testing the terminal: impossible, workers have `/dev/null` stdin (see Context).
- Keeping `approval: prompt` as the default and warning: the warning is exactly what already happens, and it is what caused the silent rollback.
- Always requiring `approval=approve|reject` and dropping the prompt: loses the interactive review the operator wants (D-10).

### Run-time passwords come from the environment (D-23)

`roles/verify/defaults/main.yml` becomes:

```
nvr_admin_password: "{{ lookup('env', 'ADMIN_PASSWORD') | default(bootstrap_admin_password, true) }}"
nvr_viewer_password: "{{ lookup('env', 'VIEWER_PASSWORD') | default(bootstrap_viewer_password, true) }}"
```

The update and rollback plays include the verify role, so they inherit this. `-e nvr_admin_password=...` still overrides a default. The `verify` and `update` recipes drop their `-e` password arguments, start with `@`, and echo a fixed sanitized line such as `ansible-playbook update.yml (passwords from ADMIN_PASSWORD/VIEWER_PASSWORD)`. `make update ADMIN_PASSWORD=x` still works because make exports command-line variables to the recipe's environment; `ADMIN_PASSWORD=x make update` works for the same reason.

Alternatives considered:
- Only `@`-prefixing the recipes while keeping `-e`: the value still lands in `ps` output on the operator machine and in Ansible's own `-v` output of the command line. Environment is one step better at the same UX.
- A prompt for passwords (`vars_prompt`): breaks `make verify` in non-interactive use and adds a second interactive gate.

### Pins are written in file order with a version fallback (D-24)

The "Write new image pins" task and the snapshot's embedded copy both use `to_nice_yaml(indent=2, sort_keys=False)`. The header comment is fixed text so repeated approvals produce no header diff. Version resolution per image: first the `org.opencontainers.image.version` label; if empty and the image is listed in `roles/update/defaults` `image_version_args` (default `{cloudflared: "version"}`), run `docker run --rm <repository>:<track>@<digest> <args>` on the server and take the first match of `version (\S+)`; only if both fail write `version unknown`. The run uses the image already pulled for the upgrade, so it adds no network traffic.

Alternatives considered:
- Writing the pins file from a hand-made Jinja template instead of the YAML filter: more code for the same result, and the filter already handles quoting.
- Dropping the version comment: it is the only human-readable release marker in git history and the operator reads it.

### Examine prints name and image reference only

The digest task's format becomes `{{slice .Name 1}} {{.Config.Image}}`. The image ID (`.Image`) is dropped: on this server it equals the manifest digest under the containerd image store, elsewhere it is an unrelated config digest, and in neither case does it tell the operator anything the reference does not. No decision entry: this is formatting with no alternative worth defending.

## Risks / Trade-offs

- [`$(shell [ -t 0 ])` misreads an unusual launcher, for example a terminal multiplexer pane that is not the foreground job] → The worst outcome is the fail-fast message with the explicit `APPROVAL=` escape hatch; nothing on the server is touched. Documented in RUNBOOK.
- [Operators who run `ansible-playbook update.yml` directly, as the RUNBOOK used to show for unattended runs, now must always pass `-e approval=...`] → RUNBOOK rewrites that section to `make update APPROVAL=...` and states the rule for direct calls.
- [`lookup('env')` on a defined but empty variable returns an empty string] → `default(..., true)` treats empty as unset and falls back to bootstrap credentials, which is the previous behaviour.
- [`docker run <image> version` could hang if an image's version argument starts a daemon] → The fallback runs only for images explicitly listed in `image_version_args`; the task carries a 30 second timeout and `failed_when: false`, so a hang degrades to `version unknown`.
- [The first approval after this change still produces one noisy diff, because the committed file came from the old writer] → Accepted; subsequent diffs are minimal.

## Migration Plan

No server-side change. After merge, the next `make update` from a real terminal behaves as before, with the prompt. From a non-terminal it fails before connecting. Rollback is reverting the commit.

# Proposal

## Why

The first real runs of `make update` on 2026-10-12 (all three paths: up to date, reject, approve) exposed four defects. The most serious: when stdin is not a terminal, the approval prompt is skipped with a warning, the empty answer counts as a rejection, and the flow snapshots, upgrades, verifies, rolls back and restarts the whole stack for nothing. Any unattended or agent-driven run would do this on every invocation. The other three are leaks and noise seen in the same runs.

## What Changes

- **Approval gate fails fast without a terminal.** When `approval` is `prompt` and the controller's stdin is not an interactive terminal, the update play stops before the snapshot with a message naming `-e approval=approve|reject` (and `make update APPROVAL=...`). The Makefile gains an `APPROVAL` pass-through and loses its incorrect claim that piping through `cat` keeps stdin interactive.
- **Run-time passwords are read from the environment, never echoed.** `make verify` and `make update` stop passing `-e nvr_admin_password=...` on the command line that make prints. The verify role reads `ADMIN_PASSWORD` and `VIEWER_PASSWORD` from the controller environment, falling back to the bootstrap credentials; `-e` overrides still work. The operator command stays `make update ADMIN_PASSWORD=... VIEWER_PASSWORD=...`.
- **Pins file is written in a stable format with a version for every image.** `state/images.yml` keeps the order `motioneye`, `cloudflared` and the key order `repository`, `track`, `digest` on every approval, so a commit diff shows only the digests that changed. The version comment falls back to running the image's own version command when the OCI version label is absent (cloudflared has none).
- **Inspection prints each running image once.** The examine summary lists `container image:tag@digest` per container and drops the duplicated image ID.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `safe-update`: the operator approval gate SHALL refuse to proceed without an interactive terminal unless an explicit approval is supplied; the committed pins SHALL be stable in order and carry a version for every image.
- `deployment-verification`: run-time credentials SHALL be accepted from the environment and SHALL NOT be printed by the flows.
- `server-inspection`: the existing-deployment summary SHALL list each container once with its image reference and digest.

## Impact

- `roles/update`: a controller-side terminal check before the snapshot, a version-command fallback, and a stable pins writer. A small role-local lookup plugin.
- `roles/verify/defaults`: environment-backed defaults for `nvr_admin_password` and `nvr_viewer_password` (also consumed by the update and rollback plays, which include the verify role).
- `roles/examine`: summary formatting only.
- `Makefile`, `docs/RUNBOOK.md`, `docs/INPUTS.md`: `APPROVAL` variable, corrected stdin note, environment-based password passing.
- `docs/decisions.md`: D-22 (terminal check and explicit approval), D-23 (passwords via environment), D-24 (pins format and version fallback).
- No change to the deployed server, snapshots, or the Cloudflare setup (D-19 untouched).

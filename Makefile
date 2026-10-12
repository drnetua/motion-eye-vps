# Operator entry points. See docs/RUNBOOK.md.
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
# Ansible refuses non-blocking stdout/stderr (e.g. when run from an IDE or agent
# prompt); piping through cat keeps them blocking. It does not make stdin a terminal.
# make 3.81 (macOS) ignores .SHELLFLAGS, so the pipe returns ansible-playbook's
# status explicitly instead of relying on pipefail (D-26).
ANSIBLE_PLAYBOOK ?= ansible-playbook
PIPE := 2>&1 | cat; exit $${PIPESTATUS[0]}
SNAPSHOT ?=
# Update approval: `prompt` when make's stdin is a terminal, empty otherwise, and the
# play then stops before touching the server. Unattended: APPROVAL=approve|reject.
APPROVAL ?= $(shell [ -t 0 ] && echo prompt)
# Run-time NVR passwords are read by the verify role from the ADMIN_PASSWORD and
# VIEWER_PASSWORD environment variables (make exports command-line variables), so
# they never appear on a command line. Recipes that receive them are not echoed.

.PHONY: bootstrap inputs check init examine harden deploy verify update rollback lint vault-edit vault-encrypt

# Per-deployment files: git-ignored, created from their *.example (README, D-29).
# Without an inventory ansible-playbook skips every play and exits 0, so the
# flows check for them here first.
LIVE_INPUTS := inventory/hosts.yml group_vars/all/vault.yml
LIVE_FILES := $(LIVE_INPUTS) state/images.yml state/cloudflare.yml harvest/motion.conf

bootstrap:            ## install local dependencies (ansible, collections)
	bin/bootstrap

inputs:
	@ok=1; for f in $(LIVE_INPUTS); do [ -f $$f ] || { echo "missing $$f: cp $$f.example $$f, then fill it in (docs/INPUTS.md)"; ok=0; }; done; \
	[ -f .vault_pass ] || { echo "missing .vault_pass: umask 077; echo 'your-vault-password' > .vault_pass"; ok=0; }; \
	[ $$ok = 1 ]

check: inputs         ## validate inputs only, touches nothing remote
	$(ANSIBLE_PLAYBOOK) playbooks/check.yml $(PIPE)

init: check           ## initial deployment: examine, harden, deploy, verify
	$(ANSIBLE_PLAYBOOK) site.yml $(PIPE)

examine: inputs       ## report server facts and pre-flight checks
	$(ANSIBLE_PLAYBOOK) playbooks/examine.yml $(PIPE)

harden: inputs        ## OS upgrade, ssh, firewall, fail2ban, docker
	$(ANSIBLE_PLAYBOOK) playbooks/harden.yml $(PIPE)

deploy: inputs        ## cloudflare ingress + motioneye + retention
	$(ANSIBLE_PLAYBOOK) playbooks/deploy.yml $(PIPE)

verify: inputs        ## health, tunnel, logins, cameras, config (read-only)
	@echo "$(ANSIBLE_PLAYBOOK) playbooks/verify.yml (passwords from ADMIN_PASSWORD/VIEWER_PASSWORD)"
	@$(ANSIBLE_PLAYBOOK) playbooks/verify.yml $(PIPE)

update: check         ## OS upgrade, image update check, safe upgrade with approval
	@echo "$(ANSIBLE_PLAYBOOK) update.yml -e approval=$(APPROVAL) (passwords from ADMIN_PASSWORD/VIEWER_PASSWORD)"
	@$(ANSIBLE_PLAYBOOK) update.yml -e approval=$(APPROVAL) $(PIPE)

rollback: inputs      ## restore a snapshot: make rollback SNAPSHOT=20260101T120000Z
	@test -n "$(SNAPSHOT)" || { echo "usage: make rollback SNAPSHOT=<timestamp>"; exit 1; }
	$(ANSIBLE_PLAYBOOK) playbooks/rollback.yml -e snapshot_id=$(SNAPSHOT) $(PIPE)

lint:                 ## syntax-check playbooks, lint, assert the vault is encrypted and no live file is tracked
	@for p in site.yml update.yml playbooks/*.yml; do $(ANSIBLE_PLAYBOOK) --syntax-check $$p >/dev/null && echo "syntax ok  $$p"; done
	@if [ -f group_vars/all/vault.yml ] && ! head -c 14 group_vars/all/vault.yml | grep -q '^\$$ANSIBLE_VAULT'; then echo "ERROR: group_vars/all/vault.yml is not encrypted"; exit 1; fi
	@bad=0; for f in $(LIVE_FILES); do git ls-files --error-unmatch $$f >/dev/null 2>&1 && { echo "ERROR: $$f is tracked by git; it is per-deployment: git rm --cached $$f"; bad=1; }; done; [ $$bad = 0 ]
	@command -v ansible-lint >/dev/null && ansible-lint || echo "ansible-lint not installed, skipped"

vault-edit:           ## edit the encrypted vault
	ansible-vault edit group_vars/all/vault.yml

vault-encrypt:        ## encrypt a freshly created plaintext vault
	ansible-vault encrypt group_vars/all/vault.yml

help:
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*##/\t/' | expand -t 14

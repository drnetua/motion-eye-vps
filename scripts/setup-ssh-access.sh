#!/usr/bin/env bash
#
# setup-ssh-access.sh — guided, one-time bootstrap of passwordless SSH access.
#
# Asks for the server address, the remote user that should get key-based
# access, and the server's root password. Uses the root password once to
# install your public key for that user, then verifies that key login works
# without a password. Nothing else on the server is changed.
#
# Usage: scripts/setup-ssh-access.sh
#
set -euo pipefail

# ---------- output helpers ----------------------------------------------------
if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=''; GREEN=''; YELLOW=''; RED=''; RESET=''
fi
step() { printf '\n%s==> %s%s\n' "$BOLD" "$*" "$RESET"; }
ok()   { printf '%s  ok%s  %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s warn%s %s\n' "$YELLOW" "$RESET" "$*"; }
die()  { printf '%s fail%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

ask() { # ask VAR "Prompt" "default"
  local var="$1" prompt="$2" default="${3:-}" reply
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " reply
    reply="${reply:-$default}"
  else
    read -r -p "$prompt: " reply
  fi
  printf -v "$var" '%s' "$reply"
}
ask_secret() { # ask_secret VAR "Prompt"
  local var="$1" prompt="$2" reply
  read -r -s -p "$prompt: " reply; printf '\n'
  printf -v "$var" '%s' "$reply"
}
confirm() { # confirm "Question" [default y|n]
  local default="${2:-n}" reply suffix='[y/N]'
  [ "$default" = y ] && suffix='[Y/n]'
  read -r -p "$1 $suffix " reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

# ---------- cleanup -----------------------------------------------------------
WORKDIR="$(mktemp -d)"
cleanup() { unset SETUP_SSH_PASSWORD; rm -rf "$WORKDIR"; }
trap cleanup EXIT

# ---------- 1. collect inputs -------------------------------------------------
printf '%sPasswordless SSH access setup%s\n' "$BOLD" "$RESET"
printf 'This installs your SSH public key for a user on a remote server.\n'
printf 'The root password is used once, over SSH, and is not stored.\n'

step "Server and user"
ask HOST "Server IP or hostname"
[ -n "$HOST" ] || die "server address is required"
ask PORT "SSH port" "22"
[[ "$PORT" =~ ^[0-9]+$ ]] || die "port must be a number"
ask TARGET_USER "Remote user to grant key access" "root"
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "invalid user name: $TARGET_USER"
ask_secret ROOT_PASSWORD "Root password for $HOST"
[ -n "$ROOT_PASSWORD" ] || die "root password is required"

step "Local SSH key"
DEFAULT_KEY="$HOME/.ssh/id_ed25519"
ask KEY_PATH "Private key to use (created if missing)" "$DEFAULT_KEY"
KEY_PATH="${KEY_PATH/#\~/$HOME}"
PUB_PATH="$KEY_PATH.pub"
if [ ! -f "$KEY_PATH" ]; then
  if confirm "No key at $KEY_PATH. Generate a new ed25519 key?" y; then
    mkdir -p "$(dirname "$KEY_PATH")"
    chmod 700 "$(dirname "$KEY_PATH")"
    ssh-keygen -t ed25519 -f "$KEY_PATH" -C "$(whoami)@$(hostname -s 2>/dev/null || hostname)" </dev/tty
  else
    die "a private key is required"
  fi
fi
[ -f "$PUB_PATH" ] || ssh-keygen -y -f "$KEY_PATH" > "$PUB_PATH"
PUB_KEY="$(head -n1 "$PUB_PATH")"
[ -n "$PUB_KEY" ] || die "could not read public key from $PUB_PATH"
ok "using key $PUB_PATH"

CREATE_USER=no
SUDO_USER_FLAG=no
if [ "$TARGET_USER" != root ]; then
  confirm "Create '$TARGET_USER' on the server if it does not exist?" y && CREATE_USER=yes
  if [ "$CREATE_USER" = yes ]; then
    confirm "If created, add '$TARGET_USER' to the sudo group?" n && SUDO_USER_FLAG=yes
  fi
fi

step "Summary"
printf '  server       : %s:%s\n' "$HOST" "$PORT"
printf '  login as     : root (password, once)\n'
printf '  grant key to : %s\n' "$TARGET_USER"
printf '  public key   : %s\n' "$PUB_PATH"
[ "$TARGET_USER" != root ] && printf '  create user  : %s (sudo: %s)\n' "$CREATE_USER" "$SUDO_USER_FLAG"
confirm "Proceed?" y || die "aborted"

# ---------- 2. choose how to feed the root password to ssh --------------------
# Preferred: OpenSSH >= 8.4 supports SSH_ASKPASS_REQUIRE=force, no extra tools.
# Fallback : sshpass if installed. Last resort: ssh prompts you interactively.
SSH_VERSION="$(ssh -V 2>&1 | sed -nE 's/^OpenSSH_([0-9]+)\.([0-9]+).*/\1 \2/p')"
PASS_MODE=interactive
if [ -n "$SSH_VERSION" ]; then
  read -r SSH_MAJOR SSH_MINOR <<<"$SSH_VERSION"
  if [ "$SSH_MAJOR" -gt 8 ] || { [ "$SSH_MAJOR" -eq 8 ] && [ "$SSH_MINOR" -ge 4 ]; }; then
    PASS_MODE=askpass
  fi
fi
if [ "$PASS_MODE" = interactive ] && command -v sshpass >/dev/null 2>&1; then
  PASS_MODE=sshpass
fi

ASKPASS="$WORKDIR/askpass.sh"
printf '#!/bin/sh\nprintf "%%s\\n" "$SETUP_SSH_PASSWORD"\n' > "$ASKPASS"
chmod 700 "$ASKPASS"
export SETUP_SSH_PASSWORD="$ROOT_PASSWORD"
unset ROOT_PASSWORD

ROOT_SSH_OPTS=(
  -p "$PORT"
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o NumberOfPasswordPrompts=1
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
)
root_ssh() { # root_ssh <ssh args...>   (stdin is passed through)
  case "$PASS_MODE" in
    askpass)
      SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-none}" \
        ssh "${ROOT_SSH_OPTS[@]}" "$@" ;;
    sshpass)
      SSHPASS="$SETUP_SSH_PASSWORD" sshpass -e ssh "${ROOT_SSH_OPTS[@]}" "$@" ;;
    interactive)
      ssh "${ROOT_SSH_OPTS[@]}" "$@" ;;
  esac
}

# ---------- 3. test the password login ---------------------------------------
step "Connecting to root@$HOST with the password ($PASS_MODE)"
[ "$PASS_MODE" = interactive ] && warn "old OpenSSH and no sshpass: ssh will prompt for the root password itself"
if ! root_ssh "root@$HOST" 'true' </dev/null; then
  die "password login as root failed. Check the address, port, password, and that sshd allows root password login."
fi
ok "root password login works"

# ---------- 4. install the key on the server ----------------------------------
step "Installing the public key for '$TARGET_USER'"
REMOTE_SCRIPT='
set -eu
target="$1"; key="$2"; create="$3"; sudo_flag="$4"

if ! id "$target" >/dev/null 2>&1; then
  if [ "$create" = yes ]; then
    useradd -m -s /bin/bash "$target"
    echo "created user $target"
    if [ "$sudo_flag" = yes ]; then
      usermod -aG sudo "$target" && echo "added $target to sudo"
    fi
  else
    echo "user $target does not exist on the server" >&2
    exit 3
  fi
fi

home="$(getent passwd "$target" | cut -d: -f6)"
[ -n "$home" ] || { echo "no home directory for $target" >&2; exit 4; }
group="$(id -gn "$target")"
mkdir -p "$home/.ssh"
touch "$home/.ssh/authorized_keys"
if grep -qxF "$key" "$home/.ssh/authorized_keys"; then
  echo "key already present in $home/.ssh/authorized_keys"
else
  printf "%s\n" "$key" >> "$home/.ssh/authorized_keys"
  echo "key added to $home/.ssh/authorized_keys"
fi
chown -R "$target:$group" "$home/.ssh"
chmod 700 "$home/.ssh"
chmod 600 "$home/.ssh/authorized_keys"

# Report sshd settings that would block key login. Nothing is modified.
if command -v sshd >/dev/null 2>&1; then
  cfg="$(sshd -T 2>/dev/null || true)"
  if printf "%s" "$cfg" | grep -qi "^pubkeyauthentication no"; then
    echo "WARN: sshd has PubkeyAuthentication no; key login will fail until this is changed"
  fi
  if [ "$target" = root ] && printf "%s" "$cfg" | grep -qi "^permitrootlogin no"; then
    echo "WARN: sshd has PermitRootLogin no; root key login will fail until this is changed"
  fi
fi
'
if ! root_ssh "root@$HOST" "bash -s -- $(printf '%q ' "$TARGET_USER" "$PUB_KEY" "$CREATE_USER" "$SUDO_USER_FLAG")" <<<"$REMOTE_SCRIPT" \
     | sed 's/^/  /'; then
  die "installing the key on the server failed (see output above)"
fi
ok "key installed"

# ---------- 5. verify passwordless login -------------------------------------
step "Verifying key login as $TARGET_USER@$HOST"
unset SETUP_SSH_PASSWORD
if ssh -p "$PORT" -i "$KEY_PATH" \
     -o BatchMode=yes -o PasswordAuthentication=no -o IdentitiesOnly=yes \
     -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
     "$TARGET_USER@$HOST" 'echo "logged in as $(id -un) on $(hostname)"' | sed 's/^/  /'; then
  ok "passwordless SSH access works"
else
  die "key login failed. See any WARN lines above for sshd settings that block it."
fi

printf '\n%sDone.%s Connect with:\n\n  ssh -p %s -i %s %s@%s\n\n' "$BOLD" "$RESET" "$PORT" "$KEY_PATH" "$TARGET_USER" "$HOST"

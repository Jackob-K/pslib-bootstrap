#!/usr/bin/env bash
set -euo pipefail

APP_NAME="pslib-vyuka"
PRIVATE_REPO="git@github.com:Jackob-K/pslib.git"
BASE_DIR="/srv/pslib-vyuka"
DEPLOY_KEY="$HOME/.ssh/pslib_vyuka_github"
BRANCH="${BRANCH:-main}"
TTY_DEVICE="${TTY_DEVICE:-/dev/tty}"

say() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

need() {
  have "$1" || fail "Missing required command: $1"
}

read_from_tty() {
  local prompt="$1"
  local answer
  if [ ! -r "$TTY_DEVICE" ]; then
    fail "Interactive terminal not available. Re-run this script from a terminal."
  fi
  read -r -p "$prompt" answer < "$TTY_DEVICE"
  printf '%s\n' "$answer"
}

run_privileged() {
  if [ -d "$BASE_DIR" ] && [ -w "$BASE_DIR" ]; then
    "$@"
  elif [ -w "$(dirname "$BASE_DIR")" ]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    fail "Cannot write to $BASE_DIR and sudo is not available."
  fi
}

ssh_git() {
  GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" git "$@"
}

HOSTNAME_VALUE="$(hostname -f 2>/dev/null || hostname)"
CURRENT_USER="$(id -un)"

say "$APP_NAME public bootstrap"
echo "Host:      $HOSTNAME_VALUE"
echo "User:      $CURRENT_USER"
echo "Sudo:      $(have sudo && echo available || echo unavailable)"
echo "Base dir:  $BASE_DIR"
echo "Repo:      $PRIVATE_REPO"
echo "Key:       $DEPLOY_KEY"

need ssh
need git
need curl

say "Preparing SSH deploy key"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ ! -f "$DEPLOY_KEY" ]; then
  ssh-keygen -t ed25519 -C "$APP_NAME-$HOSTNAME_VALUE" -f "$DEPLOY_KEY" -N ""
else
  echo "Deploy key already exists: $DEPLOY_KEY"
fi

chmod 600 "$DEPLOY_KEY"
chmod 644 "$DEPLOY_KEY.pub"

say "Add this public key to GitHub as read-only deploy key"
echo
cat "$DEPLOY_KEY.pub"
echo
echo "GitHub instructions:"
echo "  1. Open GitHub repo: Jackob-K/pslib"
echo "  2. Go to Settings -> Deploy keys -> Add deploy key"
echo "  3. Title: $APP_NAME-$HOSTNAME_VALUE"
echo "  4. Key: paste the public key printed above"
echo "  5. Allow write access: disabled"
echo
read_from_tty "Press Enter after the deploy key is saved in GitHub..." >/dev/null

say "Testing read-only GitHub access"
if ! ssh_git ls-remote "$PRIVATE_REPO" >/dev/null; then
  fail "GitHub access failed. Check that the deploy key was added to Jackob-K/pslib and that Allow write access is disabled."
fi

say "Preparing $BASE_DIR"
run_privileged mkdir -p "$BASE_DIR/repo" "$BASE_DIR/releases" "$BASE_DIR/shared" "$BASE_DIR/logs"
run_privileged chown -R "$(id -u):$(id -g)" "$BASE_DIR/repo" "$BASE_DIR/releases" "$BASE_DIR/shared" "$BASE_DIR/logs"

if [ ! -d "$BASE_DIR/repo/.git" ]; then
  say "Cloning private repository"
  ssh_git clone --branch "$BRANCH" "$PRIVATE_REPO" "$BASE_DIR/repo"
else
  say "Updating existing private repository checkout"
  git -C "$BASE_DIR/repo" remote set-url origin "$PRIVATE_REPO"
  ssh_git -C "$BASE_DIR/repo" fetch origin "$BRANCH"
  git -C "$BASE_DIR/repo" checkout "$BRANCH"
  ssh_git -C "$BASE_DIR/repo" pull --ff-only origin "$BRANCH"
fi

say "Running internal installer from private repository"
bash "$BASE_DIR/repo/web/server/install.sh"

say "Bootstrap finished"
echo "No DNS, Apache, cloudflared routing, production symlink, or deploy was changed by this public bootstrap."

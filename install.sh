#!/usr/bin/env bash
set -euo pipefail

APP_NAME="pslib-vyuka"
PRIVATE_REPO="git@github.com:Jackob-K/pslib.git"
BASE_DIR="/srv/pslib-vyuka"
DEPLOY_KEY="$HOME/.ssh/pslib_vyuka_github"
BRANCH="${BRANCH:-main}"
TTY_DEVICE="${TTY_DEVICE:-/dev/tty}"
APP_OWNER="${APP_OWNER:-$(id -un)}"
DEPLOY_USER="${DEPLOY_USER:-github-deploy}"
SETUP_GITHUB_DEPLOY="${SETUP_GITHUB_DEPLOY:-0}"
DEPLOY_WRAPPER="${DEPLOY_WRAPPER:-/usr/local/sbin/deploy-pslib}"
SUDOERS_FILE="${SUDOERS_FILE:-/etc/sudoers.d/github-deploy-pslib}"

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

run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    fail "This action requires root privileges and sudo is not available."
  fi
}

run_as_root_shell() {
  local script="$1"
  if [ "$(id -u)" -eq 0 ]; then
    bash -c "$script"
  elif have sudo; then
    sudo bash -c "$script"
  else
    fail "This action requires root privileges and sudo is not available."
  fi
}

have_sudo() {
  have sudo
}

path_owner_uid() {
  if stat -c '%u' "$1" >/dev/null 2>&1; then
    stat -c '%u' "$1"
  else
    stat -f '%u' "$1"
  fi
}

ensure_owned_by_current_user() {
  local target="$1"
  local uid gid owner

  [ -e "$target" ] || return 0

  uid="$(id -u)"
  gid="$(id -g)"
  owner="$(path_owner_uid "$target")"

  if [ "$owner" = "$uid" ]; then
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    chown -R "$uid:$gid" "$target"
  elif have_sudo; then
    sudo chown -R "$uid:$gid" "$target"
  else
    fail "$target is not owned by the current user and sudo is not available."
  fi
}

ensure_app_tree_ownership() {
  ensure_owned_by_current_user "$BASE_DIR"
  ensure_owned_by_current_user "$BASE_DIR/repo"
  ensure_owned_by_current_user "$BASE_DIR/releases"
  ensure_owned_by_current_user "$BASE_DIR/shared"
  ensure_owned_by_current_user "$BASE_DIR/logs"
}

ensure_github_deploy_hook() {
  say "Preparing GitHub Actions deploy hook"
  echo "Deploy SSH user:     $DEPLOY_USER"
  echo "Application owner:   $APP_OWNER"
  echo "Deploy wrapper:      $DEPLOY_WRAPPER"
  echo "Sudoers file:        $SUDOERS_FILE"

  if ! getent passwd "$APP_OWNER" >/dev/null; then
    fail "APP_OWNER does not exist: $APP_OWNER"
  fi

  if ! getent passwd "$DEPLOY_USER" >/dev/null; then
    run_root useradd --create-home --shell /bin/bash "$DEPLOY_USER"
  fi

  run_root install -d -o root -g root -m 0755 "$(dirname "$DEPLOY_WRAPPER")"
  run_as_root_shell "cat > '$DEPLOY_WRAPPER' <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

APP_ROOT=\"${APP_ROOT:-$BASE_DIR}\"

export HOME=\"\$(getent passwd \"\$(id -un)\" | cut -d: -f6)\"
export BUILD_RUNTIME=\"\${BUILD_RUNTIME:-docker}\"

cd \"\$APP_ROOT/repo\"
exec \"\$APP_ROOT/shared/deploy.sh\"
EOF
chown root:root '$DEPLOY_WRAPPER'
chmod 0755 '$DEPLOY_WRAPPER'"

  run_as_root_shell "cat > '$SUDOERS_FILE' <<EOF
$DEPLOY_USER ALL=($APP_OWNER) NOPASSWD: $DEPLOY_WRAPPER
EOF
chown root:root '$SUDOERS_FILE'
chmod 0440 '$SUDOERS_FILE'"

  run_root visudo -cf "$SUDOERS_FILE"
  echo "GitHub Actions deploy command:"
  echo "  sudo -n -u $APP_OWNER $DEPLOY_WRAPPER"
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
echo "App owner: $APP_OWNER"

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
ensure_app_tree_ownership

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
ensure_app_tree_ownership

case "$SETUP_GITHUB_DEPLOY" in
  1|true|TRUE|yes|YES) ensure_github_deploy_hook ;;
esac

say "Sanity check"
git -C "$BASE_DIR/repo" status --short
test -x "$BASE_DIR/shared/deploy.sh"
mkdir -p "$BASE_DIR/shared/pnpm-store"
ensure_owned_by_current_user "$BASE_DIR/shared/pnpm-store"
test -d "$BASE_DIR/shared/pnpm-store"

say "Bootstrap finished"
echo "No DNS, Apache, cloudflared routing, production symlink, or deploy was changed by this public bootstrap."
echo
echo "Next deploy command:"
echo "  BUILD_RUNTIME=docker $BASE_DIR/shared/deploy.sh"

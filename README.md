# PSLIB public bootstrap

This repository contains only the public bootstrap installer for the private PSLIB teaching web.

It does not contain:

- the Obsidian vault,
- teaching content,
- private notes,
- deploy tokens,
- private SSH keys,
- credentials.

## One-command bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/Jackob-K/pslib-bootstrap/main/install.sh | bash
```

The script creates a unique SSH deploy key on the server, prints the public key, and waits until you add it manually to the private `Jackob-K/pslib` repository as a read-only deploy key.

Without that manual GitHub step, the bootstrap cannot access the private repository.

## What It Does

1. Checks `ssh`, `git`, and `curl`.
2. Creates `~/.ssh/pslib_vyuka_github` if missing.
3. Prints `~/.ssh/pslib_vyuka_github.pub`.
4. Waits for confirmation that the public key was added to GitHub.
5. Tests read-only access to `git@github.com:Jackob-K/pslib.git`.
6. Prepares `/srv/pslib-vyuka`.
7. Clones or updates the private repository in `/srv/pslib-vyuka/repo`.
8. Runs `/srv/pslib-vyuka/repo/web/server/install.sh`.
9. Checks that deploy scripts are executable and that `shared/pnpm-store` exists.

It does not change DNS, Apache, cloudflared routing, redirects, or the production web symlink.

## After Bootstrap

Run the first deploy manually:

```bash
BUILD_RUNTIME=docker /srv/pslib-vyuka/shared/deploy.sh
```

## GitHub Actions Deploy Hook

The bootstrap can also prepare a minimal SSH deploy entrypoint for GitHub Actions:

```bash
APP_OWNER=jakub DEPLOY_USER=github-deploy SETUP_GITHUB_DEPLOY=1 bash install.sh
```

On a new server with a dedicated service user, set `APP_OWNER` to that user instead.

This creates:

- `/usr/local/sbin/deploy-pslib`, owned by `root:root` and not writable by `github-deploy`,
- `/etc/sudoers.d/github-deploy-pslib`, allowing `github-deploy` to run only that wrapper as `APP_OWNER`.

It does not add `github-deploy` to the `docker` group and does not grant `NOPASSWD: ALL`.

GitHub Actions should run only:

```bash
sudo -n -u "$APP_OWNER" /usr/local/sbin/deploy-pslib
```

Useful sanity checks:

```bash
git -C /srv/pslib-vyuka/repo status --short
test -x /srv/pslib-vyuka/shared/deploy.sh
test -d /srv/pslib-vyuka/shared/pnpm-store
sudo visudo -cf /etc/sudoers.d/github-deploy-pslib
sudo -l -U github-deploy
```

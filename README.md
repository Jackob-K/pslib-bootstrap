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

It does not change DNS, Apache, cloudflared routing, redirects, or the production web symlink.

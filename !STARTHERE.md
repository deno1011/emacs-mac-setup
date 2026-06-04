# Start Here

A preconfigured Emacs for macOS. One command, fully wired on first launch:
emacs-plus, the literate config, an example agenda, a populated LLM-wiki,
and a guided TOUR.org that explains the rest. No setup wizard, no
Bitwarden, no Keychain dance — just an editor that works.

## Open Terminal and run

```bash
curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/install.sh | /bin/bash
```

After ~10 minutes (most of it `brew install emacs-plus`), Emacs launches
with `TOUR.org` open. Five short sections show you the agenda, the
wiki, gptel chat, the key bindings to know, and where to put your API
keys.

## What's installed

| Component | Where it goes | Source of truth |
|---|---|---|
| `emacs-plus` | `/Applications/Emacs Plus.app` | Homebrew |
| Literate config | `~/.emacs.d/` (symlink) → `~/emacs-mac-setup-src/emacs.d/` | this repo |
| Starter wiki + agenda + TOUR.org | `~/emacs/` | seeded once from `starter-data/`, then yours |
| Per-Mac secrets | `~/emacs-mac-setup-src/emacs.d/secrets.el` | edit locally, never tracked |

The split is deliberate: distro code is symlinked and read-only from your
side (updates via `git pull`); user data is yours from first install on.

## Update later

```bash
bash ~/emacs-mac-setup-src/install.sh
```

Pulls latest distro code. Your data in `~/emacs/` and your `secrets.el`
are never touched.

## Uninstall

```bash
bash ~/emacs-mac-setup-src/uninstall.sh
# add --purge-data to also delete ~/emacs/ (irreversible)
# add --keep-emacs-app to preserve Emacs Plus.app + the brew formula
```

## Cross-Mac sync (optional, your choice)

The distro intentionally doesn't sync your data across Macs. Pick one
that works for you:

- **iCloud Drive** — `mv ~/emacs ~/Library/Mobile\ Documents/com~apple~CloudDocs/emacs` and symlink back. Apple handles the rest.
- **Private git repo** — `cd ~/emacs && git init && git remote add origin git@github.com:USER/emacs.git`. Commit + push.
- **Syncthing / Dropbox** — point them at `~/emacs/`.

All three work; the distro stays out of it.

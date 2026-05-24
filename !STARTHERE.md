# Start Here

> A one-command setup that turns a fresh Mac into a fully configured Emacs environment — org-mode, LSP, LaTeX, graphs, and Claude AI built in, synced to iCloud and ready in under 20 minutes.

Open **Terminal** and run:

```bash
curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/bootstrap.sh -o bootstrap.sh
chmod +x bootstrap.sh
./bootstrap.sh
```

Bootstrap guides you through config and Bitwarden setup, then **automatically starts the emacs-plus install** after a 5-second countdown.

> To install a different variant instead, **Ctrl-C** during the countdown — the other variants are shown on screen before it starts:
> ```
> bash ~/emacs-mac-setup/setup-emacs-native-yamamoto-mac.sh  # smooth rendering, trackpad
> bash ~/emacs-mac-setup/setup-emacs-docker-mac.sh           # isolated in Docker + XQuartz
> bash ~/emacs-mac-setup/setup-emacs-orbstack-mac.sh         # isolated in OrbStack, no XQuartz
> ```

All scripts land in `~/emacs-mac-setup/` — run any of them at any time without re-running bootstrap.  
See [README.md](README.md) for full documentation.

---

## What bootstrap installs automatically

| Software | When | Notes |
|---|---|---|
| Homebrew | always | installed if not present; requires sudo once |
| All setup scripts | always | downloaded to `~/emacs-mac-setup/` |
| `gh` (GitHub CLI) | GitHub mode | needed to access your private config repo |
| `bitwarden-cli` | GitHub mode | used to fetch your GitHub token and API keys |

> **GitHub mode** is active when `GH_USER` is set in your config file (filled in interactively during bootstrap).

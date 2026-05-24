# Start Here

> A one-command setup that turns a fresh Mac into a fully configured Emacs environment — org-mode, LSP, LaTeX, graphs, and Claude AI built in, synced to iCloud and ready in under 20 minutes.

## Open Terminal and Run

Open **Terminal**, `cd` to the folder where you want the scripts, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/bootstrap.sh -o bootstrap.sh
chmod +x bootstrap.sh
./bootstrap.sh
```

If you already have a private config repo, pass it as the first argument:

```bash
./bootstrap.sh your-github-user/your-private-config-repo
```

Bootstrap guides you through config, Bitwarden setup, and Emacs installation.  
See [README.md](README.md) for full documentation.

---

## What bootstrap installs automatically

| Software | When | Notes |
|---|---|---|
| Homebrew | always | installed if not present; requires sudo once |
| All setup scripts | always | downloaded to the current folder |
| `gh` (GitHub CLI) | GitHub mode | needed to access your private config repo |
| `bitwarden-cli` | GitHub mode | used to fetch your GitHub token and API keys |

> **GitHub mode** is active when you pass a private config repo (`bootstrap.sh user/repo`) or have `GH_USER` set in your config file.

After bootstrap completes, run one of the setup scripts it downloaded to install Emacs itself.

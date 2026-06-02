# Start Here

> A one-command setup that turns a fresh Mac into a fully configured Emacs environment — org-mode, LSP, LaTeX, graphs, and local gptel agent support built in, synced to iCloud and ready to use.

## Open Terminal and Run

Open **Terminal**, `cd` to the folder where you want the scripts, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/bootstrap.sh -o bootstrap.sh
chmod +x bootstrap.sh
./bootstrap.sh stable
```

For development testing, use the same pattern with another branch:

```bash
curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/bootstrap.sh -o bootstrap.sh
chmod +x bootstrap.sh
./bootstrap.sh main
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
| Ollama | default local AI mode | installed if missing |
| `qwen2.5-coder:7b` | default local AI mode | pulled with visible terminal progress |

> **GitHub mode** is active when bootstrap finds or you enter a GitHub user and your config file has `GH_USER` set.

After bootstrap completes, it starts the emacs-plus setup automatically.

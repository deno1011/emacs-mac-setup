# Start Here

> A one-command setup that turns a fresh Mac into a fully configured Emacs environment — org-mode, LSP, LaTeX, graphs, and local gptel agent support built in, synced to iCloud and ready to use.

## Open Terminal and Run

Open **Terminal** and run:

```bash
curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/bootstrap.sh | /bin/bash -s -- stable
```

For development testing, use the same pattern with another branch:

```bash
curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/bootstrap.sh | /bin/bash -s -- main
```

Bootstrap starts with one intake phase for config, Bitwarden/Keychain, and API
keys, then continues with installation. If something fails, run:

```bash
bash ~/emacs-mac-setup/setup-doctor.sh
```

See [README.md](README.md) for full documentation.

---

## What bootstrap installs automatically

| Software | When | Notes |
|---|---|---|
| Homebrew | always | installed if not present; requires sudo once |
| All setup scripts | always | downloaded to the current folder |
| `gh` (GitHub CLI) | GitHub mode | needed to access your private config repo |
| `bitwarden-cli` + Bitwarden app | GitHub mode | used to store/fetch your GitHub token, git-crypt key, and API keys |
| Gemini API key | default gptel mode | read from Bitwarden into `~/.emacs.d/secrets.el`; Ollama remains optional |

> **GitHub mode** is active when bootstrap finds or you enter a GitHub user and your config file has `GH_USER` set.

After bootstrap completes, it starts the emacs-plus setup automatically.

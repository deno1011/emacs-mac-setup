# Start Here

> A one-command setup that turns a fresh Mac into a fully configured Emacs environment — org-mode, LSP, LaTeX, graphs, and Claude AI built in, synced to iCloud and ready in under 20 minutes.

Open **Terminal**, `cd` to the folder where you want the scripts, then run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/bootstrap.sh)
```

Bootstrap guides you through config, Bitwarden setup, and Emacs installation.  
See [README.md](README.md) for full documentation.

---

## What gets installed automatically

**Prerequisite:** [Homebrew](https://brew.sh) must be installed before running any setup script.

### Native (emacs-plus or Yamamoto)

Installs on your Mac via Homebrew — no VM or container involved.

| Software | Notes |
|---|---|
| `emacs-plus@30` or `emacs-mac@30exp` | The Emacs binary (your chosen variant) |
| `bitwarden-cli` | Password manager CLI — used to fetch keys/tokens |
| `gh` | GitHub CLI — used to authenticate and clone your config repo |
| `git-crypt` | Encrypts your `org/` files in the config repo |

> Bitwarden CLI, gh, and git-crypt are only installed when GitHub mode is configured (i.e. `GH_USER` is set in your config file). Without GitHub, only Emacs is installed.

Tools like LaTeX, ripgrep, aspell, and gnuplot are **not** installed automatically on native — manage those yourself via Homebrew as needed.

---

### Docker (Colima + XQuartz)

**Mac-side** (Homebrew):

| Software | Notes |
|---|---|
| `docker` | Docker CLI |
| `colima` | Lightweight Docker runtime for macOS |
| XQuartz | X11 display server — installed via `sudo installer`, prompts once for admin password |
| `bitwarden-cli` | Key/token retrieval |
| `gh` | GitHub CLI |
| `git-crypt` | Config repo encryption |

**Inside the Docker image** (Ubuntu, apt-get + npm):

| Software | Notes |
|---|---|
| `emacs-lucid` | Emacs with X11 GUI |
| `texlive` + extras | LaTeX: `texlive-latex-extra`, `texlive-fonts-recommended`, `texlive-science` |
| `dvipng`, `imagemagick` | LaTeX preview rendering in org-mode |
| `aspell`, `aspell-de`, `aspell-en` | Spell checking |
| `ripgrep` | Fast text search |
| `python3`, `python3-pip` | Python runtime |
| `nodejs` (v20) | JavaScript runtime |
| `@anthropic-ai/claude-code` | Claude Code CLI (npm global) |
| `fonts-jetbrains-mono` | Monospace font |
| `git`, `git-crypt`, `curl`, `wget`, `build-essential` | Dev tooling |

---

### OrbStack

**Mac-side** (Homebrew):

| Software | Notes |
|---|---|
| `orbstack` | OrbStack app (VM runtime + GUI) |

**Inside the OrbStack VM** (Ubuntu, apt-get + npm):

| Software | Notes |
|---|---|
| `emacs-lucid` | Emacs with X11 GUI |
| `texlive` + extras | LaTeX: `texlive-latex-extra`, `texlive-fonts-extra`, `texlive-science` |
| `dvipng`, `imagemagick` | LaTeX preview rendering in org-mode |
| `gnuplot` | Plot rendering for org-mode |
| `graphviz`, `plantuml` | Diagram rendering |
| `r-base` | R language runtime |
| `aspell`, `aspell-de`, `aspell-en` | Spell checking |
| `ripgrep` | Fast text search |
| `python3`, `python3-pip` | Python runtime |
| `nodejs`, `npm` | JavaScript runtime |
| `@anthropic-ai/claude-code` | Claude Code CLI (npm global) |
| JetBrains Mono font | Downloaded from GitHub releases |
| `git`, `git-crypt`, `curl`, `wget`, `unzip`, `xclip`, `fontconfig` | Dev tooling |

# Emacs Mac Setup

Automated Emacs setup for macOS. Four installation variants share a common configuration stored on GitHub. Org files are kept in sync with the beorg app on iPhone via iCloud.

---

## Quick Start

**Have these ready before you begin:**

- [ ] GitHub account + personal access token — Settings › Developer settings › Personal access tokens › Classic › scope: `repo`
- [ ] Bitwarden account *(vault entries are created interactively by `setup-bitwarden.sh` — no manual setup needed)*
- [ ] iCloud Drive enabled *(native variants only)*

**Everything else is automated:**

| What | How |
|---|---|
| Homebrew | Installed by `bootstrap.sh` if missing |
| GitHub CLI, git-crypt, Bitwarden CLI | Installed by setup scripts |
| `emacs-config` repo | Created by `bootstrap.sh` if it does not exist |
| `mac-setup-conf` repo | Created by `bootstrap.sh` if `CONF_REPO` is set |
| Bitwarden vault entries | Created interactively by `setup-bitwarden.sh` |
| XQuartz | Installed by `setup-emacs-docker-mac.sh` (Docker only) |

**Run in Terminal:**

```bash
# 1. Download all scripts (pulls personal config automatically if accessible)
bash <(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/bootstrap.sh)

# 2. Only needed if GitHub was not yet authenticated during bootstrap:
bash ./fill-config.sh        # interactive guided config fill
# or manually:
open ~/setup-emacs-mac.conf  # set GIT_NAME, GIT_EMAIL, GH_USER, GH_REPO

# 3. Install — pick one variant
bash ./setup-emacs-native-plus-mac.sh       # recommended: native comp, fast LSP (~15 min)
bash ./setup-emacs-native-yamamoto-mac.sh   # smooth scrolling, trackpad gestures (~20 min)
bash ./setup-emacs-docker-mac.sh            # isolated in Docker + XQuartz
bash ./setup-emacs-orbstack-mac.sh              # isolated in OrbStack, no XQuartz needed

# 4. Start Emacs
open "/Applications/Plus Emacs.app"                # Plus
open "/Applications/Yamamoto Emacs.app"            # Yamamoto
open "$HOME/Applications/GUI Docker Emacs.app"     # Docker
open "$HOME/Applications/GUI OrbStack Emacs.app"   # OrbStack
```

---

## GitHub Repos

**This repo** (belongs to `deno1011` — the shared template everyone uses):

| Repo | Visibility | Purpose |
|---|---|---|
| `deno1011/emacs-mac-setup` | public | All setup, uninstall, and utility scripts. Also: `init.el`, `config.org` (index), `core.org`, `org-setup.org`, `gptel-setup.org` loader, `setup-emacs-mac.conf.template` |
| `deno1011/gptel-agent-runtime` | public | Standalone Emacs/gptel AI runtime package. Installed from Git by `gptel-setup.org`; intended to become MELPA-ready later. |

**Your repos** (created under your own GitHub account during bootstrap):

| Repo | Visibility | Purpose |
|---|---|---|
| `mac-setup-conf` | private | Only `setup-emacs-mac.conf` with personal details. Pulled automatically on bootstrap. No encryption needed — contains no actual secrets. |
| `emacs-config` | private | Emacs config split into `core.org`, `org-setup.org`, `gptel-setup.org`; `org/` files; `emacs.d/secrets.el` (all encrypted with git-crypt). Cloned to iCloud Drive. Synced to iPhone via beorg. |

---

## Scripts

Scripts download to whatever folder you run `bootstrap.sh` from.
`setup-emacs-mac.conf` always lives in `~/`.

### Config & Secrets

| Script | Purpose |
|---|---|
| `setup-emacs-mac.conf` | Personal config — pulled from private repo |
| `setup-emacs-mac.conf.template` | Fallback template if private repo not accessible |
| `init.el` | Emacs entry point — copied to `~/.emacs.d/init.el` |
| `config.org` | Emacs config index — entry point linking to the three config files below |
| `core.org` | Base config: UI, font, version control, protected files, auto-commit, startup sync |
| `org-setup.org` | Org mode: agenda, capture templates, tags, clocking, export, LaTeX |
| `gptel-setup.org` | Thin loader that installs/updates `deno1011/gptel-agent-runtime` via `package-vc-install` |
| `fill-config.sh` | Interactive guided config fill |
| `setup-bitwarden.sh` | Install Bitwarden + CLI, create required vault entries interactively |
| `setup-secrets.sh` | Symlink `~/.emacs.d/secrets.el` → repo file if decrypted; otherwise fetch from Bitwarden |

### Install

| Script | Purpose |
|---|---|
| `setup-emacs-native-plus-mac.sh` | Install emacs-plus@30 (native comp, LSP) — thin wrapper |
| `setup-emacs-native-yamamoto-mac.sh` | Install emacs-mac@30exp (Yamamoto patches) — thin wrapper |
| `setup-emacs-native-mac.sh` | Shared implementation called by both native wrappers |
| `setup-emacs-docker-mac.sh` | Install Emacs in a Docker container (XQuartz) |
| `setup-emacs-orbstack-mac.sh` | Install Emacs in an OrbStack Linux machine (no XQuartz) |
| `bw-unlock.sh` | Unlock Bitwarden vault (used internally by setup scripts) |

### Uninstall

| Script | Purpose |
|---|---|
| `uninstall-emacs-native-plus-mac.sh` | Remove emacs-plus |
| `uninstall-emacs-native-yamamoto-mac.sh` | Remove emacs-mac@30exp |
| `uninstall-emacs-docker-mac.sh` | Remove Docker variant |
| `uninstall-emacs-orbstack-mac.sh` | Remove OrbStack variant |

### Utilities

| Script | Purpose |
|---|---|
| `unlock-git-crypt.sh` | Decrypt org/ files in the iCloud repo |
| `remove-bitwarden-keychain.sh` | Delete Bitwarden master password from Keychain |

---

## Prerequisites

**System:**
- macOS 13 Ventura or newer
- iCloud Drive enabled (native variants store the repo in iCloud)

**Accounts:**
- GitHub account with a personal access token (Classic, `repo` scope)
- Bitwarden account

**Required config fields** (setup aborts if empty when `GH_USER` is set):
`GIT_NAME` `GIT_EMAIL` `GH_REPO`

Everything else — Homebrew, GitHub CLI, git-crypt, Bitwarden CLI, XQuartz, and all GitHub repos — is installed or created automatically by the setup scripts.

---

## Personal Config (`setup-emacs-mac.conf`)

Contains: name, email, GitHub username, Bitwarden item names, Docker names.  
Does **not** contain: passwords, API keys, or encryption keys — those stay in Bitwarden.  
Safe to store in a private GitHub repo without encryption.

**On a new Mac, bootstrap.sh handles the config automatically:**

- **GitHub already authenticated** (e.g. second Mac): pulls `setup-emacs-mac.conf` from private repo → ready immediately
- **Brand new Mac**: copies the template → `fill-config.sh` guides you through each field → setup re-pulls latest conf after GitHub auth is established

`CONF_REPO` in the conf file is the repo name only (e.g. `mac-setup-conf`). `GH_USER` is prepended automatically. Leave empty to disable auto-pull.

---

## Emacs Variants

### 1. emacs-plus *(recommended for developers)*

- Emacs 30.2 with native compilation
- Packages compiled to native machine code — significantly faster LSP
- Native macOS fullscreen
- Install time: ~15–20 minutes

```bash
bash ./setup-emacs-native-plus-mac.sh
```

Starts as: `/Applications/Plus Emacs.app`

### 2. emacs-mac — Yamamoto *(smooth rendering)*

- Emacs 30 with Yamamoto patches
- Pixel-perfect scrolling, better Retina rendering, native trackpad gestures
- Install time: ~15–25 minutes

```bash
bash ./setup-emacs-native-yamamoto-mac.sh
```

Starts as: `/Applications/Yamamoto Emacs.app`

### 3. Docker *(isolated, XQuartz)*

- Emacs runs in a Docker container, config pulled from GitHub on start
- Display via XQuartz — clipboard image paste not supported
- Only the beorg iCloud folder is mounted — no Mac filesystem exposure

```bash
bash ./setup-emacs-docker-mac.sh
```

App bundles in `~/Applications/`:
- `GUI Docker Emacs.app` — graphical Emacs via XQuartz
- `Console Docker Emacs.app` — Emacs in terminal (`-nw`)
- `Shell Docker Emacs.app` — shell inside the container
- `Root Shell Docker Emacs.app` — root shell inside the container

### 4. OrbStack *(isolated, no XQuartz)*

- Emacs runs in an OrbStack Linux machine (Ubuntu 24.04)
- No XQuartz needed — OrbStack handles display natively on macOS 14+
- Mac home directory accessible in the machine → clipboard image paste works
- Requires OrbStack (`brew install --cask orbstack`)

```bash
bash ./setup-emacs-orbstack-mac.sh
```

App bundles in `~/Applications/`:
- `GUI OrbStack Emacs.app` — graphical Emacs
- `Console OrbStack Emacs.app` — Emacs in terminal (`-nw`)
- `Shell OrbStack Emacs.app` — shell inside the machine
- `Root Shell OrbStack Emacs.app` — root shell inside the machine

---

## Starting Emacs

**Native (Plus / Yamamoto):**

```bash
open "/Applications/Plus Emacs.app"
open "/Applications/Yamamoto Emacs.app"
# or via Spotlight — type "Emacs"
emacs -nw   # TUI mode
```

**Docker:** Double-click one of the app bundles in `~/Applications/`, or use Spotlight.

**OrbStack:** Double-click one of the app bundles in `~/Applications/`, or run `emacs-orb` in the terminal (after reloading shell: `source ~/.zshrc`).

---

## What Not To Do

**Two native instances at the same time:**  
emacs-plus and emacs-mac@30exp share `~/.emacs.d/` and `~/emacs-config/`. Running both simultaneously causes lock file collisions and git-auto-commit-mode writing to the same repo concurrently.

**Native and Docker at the same time:**  
Both use the same GitHub repo. Concurrent edits lead to git conflicts on the next sync.

**`emacs` in the terminal while a GUI instance is running:**  
The Homebrew wrapper starts a second instance with the same config.

---

## beorg iPhone Setup

**One-time configuration in the beorg app:**

1. Open beorg on iPhone
2. Tap the **gear icon** (Settings) → **Files**
3. Set **Directory** to: `iCloud Drive → beorg → Documents → org`
   - This is the folder beorg creates automatically on first launch
   - On Mac the full path is: `~/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org/`
4. Tap **Done**

The setup scripts sync the repo's `org/` folder to that path automatically. beorg picks up changes via iCloud within seconds.

> If the `org/` folder is empty on first launch (fresh repo), beorg will show no files — that is expected. Add or commit an `.org` file in Emacs and it will appear in beorg after the next sync.

---

## beorg Sync

```
GitHub (source of truth)
     │
     │ git pull / push
     │
Native Emacs        Docker Emacs       OrbStack Emacs
     │                   │                   │
on startup:         startup-sync.sh    startup-sync.sh
  git pull + revert      │                   │
  rsync → beorg          │                   │
     │                   │                   │
post-commit hook    post-commit hook   post-commit hook
     │                   │                   │
beorg iCloud folder ◄────┴───────────────────┘
     │
iPhone (beorg app)
```

**Native (Plus / Yamamoto):**  
On startup, `my/startup-sync` runs in the background:
1. `git pull --ff-only origin main`
2. Reverts all open org buffers so the agenda reflects the latest content
3. Syncs `org/` to `~/Library/Mobile Documents/.../beorg/Documents/org/`

After every save, `git-auto-commit-mode` commits and a post-commit hook pushes to GitHub and re-syncs beorg.

**Docker:**  
`startup-sync.sh` runs when the container starts:
1. `git clone` if repo not yet in container, then `git pull origin main`
2. `rsync org/ → /beorg/` (the mounted beorg iCloud folder)

A post-commit hook inside the container repeats the rsync and pushes after each commit.

| Side | Path |
|---|---|
| Mac | `~/Library/Mobile Documents/.../beorg/org/` |
| Container | `/beorg/` |

---

## Docker Specifics

- **Volume `emacs-home`:** persistent Emacs packages (`~/.emacs.d/`) survive container restarts without living on the Mac
- **Config:** via `git clone/pull` to fixed path `~/emacs-config/` inside the container — not a bind-mount
- **Only one bind-mount:** the beorg folder for iPhone sync

**Container management:**

```bash
docker ps                   # check running containers
docker start emacs-dev      # start manually
docker logs emacs-dev       # view logs
```

---

## Parallel Installation (Plus + Yamamoto)

Both variants can coexist in the Homebrew Cellar:
- Each has its own app icon in `/Applications/`
- Only one is active via the `emacs` command in the terminal (the most recently linked one)
- Each setup script automatically links its own version and unlinks the other

When uninstalling one variant while the other is still installed, shared resources (`~/.emacs.d/`, iCloud repo, packages) are preserved and the remaining variant is automatically linked.

---

## Fresh Repo (for friends / first-time setup)

Starting with an empty `emacs-config` repo is fine:

| Situation | Result |
|---|---|
| `git clone` on empty repo | OK |
| `git-crypt unlock` fails | Warning only — not an error |
| Config files missing | `config.org`, `core.org`, `org-setup.org`, `gptel-setup.org` copied automatically from bundled copies |
| `org/` folder missing | beorg hook runs empty — no crash |

A friend only needs their own GitHub account and Bitwarden account — no access to your git-crypt key or org files needed.

---

## GitHub Mode vs Local Mode

**`GH_USER` set:**  
Full setup — Bitwarden auth, GitHub auth, iCloud clone, git-crypt unlock, post-commit hook, beorg sync.

**`GH_USER` empty:**  
Local mode — no Bitwarden, no GitHub, no iCloud. `config.org` is copied locally. Emacs starts fully configured. Good for offline or trial use. Add `GH_USER` later and re-run to enable full sync.

---

## Installed Packages

### Native (emacs-plus and Yamamoto) — Mac-side

Installed via Homebrew by `setup-emacs-native-{plus,yamamoto}-mac.sh`:

| Package | When | Purpose |
|---|---|---|
| `emacs-plus@30` / `emacs-mac@30exp` | always | Emacs itself |
| `bitwarden-cli` | GitHub mode | Secret retrieval (git-crypt key, GitHub token, API keys) |
| `gh` | GitHub mode | GitHub CLI (repo clone, auth, API) |
| `git-crypt` | GitHub mode | Encrypt/decrypt org files in the repo |

Additional tools (LaTeX, ripgrep, aspell, etc.) are installed by `core.org` on first Emacs launch — see [core.org-installed packages](#coreorg-installed-packages) below.

### Docker — Mac-side

Installed via Homebrew by `setup-emacs-docker-mac.sh`:

| Package | Purpose |
|---|---|
| `docker` | Docker CLI |
| `colima` | Lightweight Docker runtime for macOS |
| `bitwarden-cli` | Secret retrieval |
| `gh` | GitHub CLI |
| `git-crypt` | Repo encryption |
| XQuartz | X11 display server for GUI Emacs (installed via `sudo installer`, prompts for admin password once) |

### Docker — Inside the container (Ubuntu)

Built into the Docker image via `apt-get` and `npm`:

| Package | Purpose |
|---|---|
| `emacs-lucid` | Emacs with X11 GUI |
| `texlive`, `texlive-latex-extra`, `texlive-fonts-recommended`, `texlive-science` | LaTeX and math preview |
| `dvipng`, `imagemagick` | LaTeX fragment rendering in org |
| `aspell`, `aspell-de`, `aspell-en` | Spell checking |
| `ripgrep` | Fast text search |
| `python3`, `python3-pip` | Python runtime |
| `nodejs` (v20) | JavaScript runtime |
| `@anthropic-ai/claude-code` | Claude Code CLI |
| `fonts-jetbrains-mono` | Editor font |
| `git`, `git-crypt`, `curl`, `wget`, `build-essential` | Dev tooling |

### OrbStack — Mac-side

Installed via Homebrew by `setup-emacs-orbstack-mac.sh`:

| Package | Purpose |
|---|---|
| `orbstack` (cask) | OrbStack app — VM runtime and display server |

### OrbStack — Inside the VM (Ubuntu)

Installed via `apt-get` and `npm` inside the OrbStack Linux machine:

| Package | Purpose |
|---|---|
| `emacs-lucid` | Emacs with X11 GUI |
| `texlive`, `texlive-latex-extra`, `texlive-fonts-extra`, `texlive-science` | LaTeX and math preview |
| `dvipng`, `imagemagick` | LaTeX fragment rendering in org |
| `gnuplot` | Plot generation via org-babel |
| `r-base` | R language via org-babel |
| `graphviz`, `plantuml` | Diagram rendering via org-babel |
| `aspell`, `aspell-de`, `aspell-en` | Spell checking |
| `ripgrep` | Fast text search |
| `python3`, `python3-pip` | Python runtime |
| `nodejs`, `npm` | JavaScript runtime |
| `@anthropic-ai/claude-code` | Claude Code CLI |
| JetBrains Mono font | Monospace editor font (downloaded from GitHub releases) |
| `git`, `git-crypt`, `curl`, `wget`, `unzip`, `xclip`, `fontconfig` | Dev tooling |

### core.org-installed packages

Installed at first Emacs launch on **native variants only** (tracked in `~/.emacs.d/system-packages.log`). Docker and OrbStack have equivalent packages pre-installed in their container/VM.

**brew:**

| Package | Purpose |
|---|---|
| `gnuplot` | Plot generation via org-babel |
| `r` | R language support via org-babel |
| `graphviz` | Dot/graph diagrams via org-babel |
| `plantuml` | UML diagrams via org-babel |
| `mermaid-cli` | Mermaid diagrams via org-babel |
| `texlive` | LaTeX rendering and math preview |
| `pngpaste` | Paste images into org buffers |
| `aspell` | Spell checking |
| `font-jetbrains-mono` | Editor font (cask) |

**pip:**

| Package | Purpose |
|---|---|
| `matplotlib` | Python plots and math function graphs |
| `numpy` | Numerical computing for Python babel blocks |

The uninstall scripts read `system-packages.log` and remove all tracked packages (brew and pip). Use `--ask` to be prompted before each removal.

---

## AI Integration

The setup now loads the AI assistant through a separate package:

[`deno1011/gptel-agent-runtime`](https://github.com/deno1011/gptel-agent-runtime)

`gptel-setup.org` is intentionally only a thin loader. It installs the package
from Git with `package-vc-install`, schedules a quiet background `git pull`, and
then requires the package. This keeps the installer repo small while the AI
runtime can evolve independently and later be prepared for MELPA.

The package currently contains the extracted Emacs/gptel runtime: backend
registration, local Ollama/Qwen defaults, prompt directives, web helpers,
response execution, tools, workspace context, and the experimental planner loop.

Package development is literate: edit
`gptel-agent-runtime.org` in the package repo, then tangle
`gptel-agent-runtime.el`. The `.el` file is the generated package artifact used
by `package-vc-install`; it should not be the primary development target.

### Backends

Multiple AI backends are configured by the package and switchable from Emacs:

| Backend | Models |
|---|---|
| **Claude** (Anthropic) | Opus 4.7, Sonnet 4.6, Haiku 4.5 |
| **ChatGPT** (OpenAI) | GPT-4o, GPT-4o-mini, o3-mini, o4-mini |
| **LM Studio** | Local OpenAI-compatible models |
| **MLX** | Local Apple Silicon models |
| **Ollama** | Local models, defaulting to active Ollama model or `qwen2.5-coder:7b` |

API keys are stored in Bitwarden and loaded at startup via `secrets.el` — never hardcoded.

### Package Loader

The loader follows the same pattern as `org-apple-reminders-setup.org`:

```elisp
(unless (package-installed-p 'gptel-agent-runtime)
  (package-vc-install
   '(gptel-agent-runtime
     :url "https://github.com/deno1011/gptel-agent-runtime"
     :branch "main")))

(use-package gptel-agent-runtime
  :ensure nil
  :demand t)
```

`main` is the current auto-update branch. The package repo also has a `stable`
branch pointing to the current version; it can later become the slower-moving
install target.

### Executable Responses

The package contains a response executor compatibility layer. AI responses can
produce visible Org blocks that are automatically executed:

| Method | What happens |
|---|---|
| `run_elisp` tool | Emacs action executes silently, no code block appears in the buffer |
| `` #+begin_src elisp :AUTORUN `` | Executed immediately — code block visible; runs any Emacs command, edits buffers, opens files |
| `` #+begin_src python/R/gnuplot :results output `` | Executed via org-babel, output inserted inline |
| `` #+begin_src python/R/gnuplot :file name.png `` | Executed and result displayed as an inline image |
| `` #+begin_src sh :results output `` | Shell command executed, output inserted |

This means you can ask the assistant to "add a TODO to inbox.org", "plot sin(x)
from 0 to 2π", or "set the font size to 14" and the package provides the hooks
and tools needed to perform the action directly.

### Graph and Diagram Generation

Supported renderers for inline output:

| Tool | Output |
|---|---|
| Python + matplotlib | 2D/3D plots, data visualisations |
| gnuplot | Function plots, data graphs |
| R | Statistical plots |
| graphviz (dot) | Dependency and flow graphs |
| mermaid | Sequence diagrams, flowcharts |
| plantuml | UML diagrams |
| LaTeX / dvipng | Inline math, rendered equations |

Diagrams appear inline in the Org buffer when the model emits proper `:file`
Org Babel blocks and local dependencies such as `gnuplot` are installed.

### Org-mode Tools

The package exposes live Emacs state via gptel tools:

| Tool | What it does |
|---|---|
| `get_todos` | Reads all open TODO entries from the org agenda |
| `read_org_file` | Reads any org file by path |
| `write_org_file` | Overwrites an org file (protected files blocked) |
| `add_todo` | Appends a new TODO heading to an org file |
| `change_todo_state` | Changes the state of a TODO entry (e.g. TODO → DONE) |
| `set_deadline` | Sets or updates the DEADLINE on a TODO entry |
| `add_tag` | Adds a tag to a heading |
| `get_org_structure` | Returns the heading outline of an org file |
| `execute_code` | Runs a code block (Python, R, shell, etc.) via org-babel |
| `run_elisp` | Evaluates Elisp and performs Emacs actions silently (no code block in buffer) |
| `read_file` | Reads any plain-text file |
| `write_file` | Writes a plain-text file (protected files blocked) |
| `list_directory` | Lists files and directories at a given path |
| `search_files` | Full-text search across files (ripgrep) |
| `list_buffers` | Lists all currently open Emacs buffers |
| `get_buffer_content` | Returns the content of an open buffer |
| `org_export` | Exports an org file to PDF, HTML, or other formats |

`run_elisp` is the primary tool for silent Emacs actions. Combined with the
other tools, the assistant can query tasks, reason about them, and update Org
files in a single response.

### LaTeX in Responses

LaTeX fragments in responses are rendered by the Org setup. The runtime package
focuses on gptel/tool/executor behavior.

### Local Models

Local backends include LM Studio, MLX, and Ollama. Ollama startup/model
selection is handled by the package; if a model is already running, it is
preferred, otherwise the default is `qwen2.5-coder:7b`.

Local models follow custom block/tool conventions less reliably than Claude or
other stronger cloud models. The package has some compatibility/repair hooks,
but the next architectural step is stricter structured-output and tool-call
handling inside `gptel-agent-runtime`.

---

## Uninstall

```bash
bash ./uninstall-emacs-native-plus-mac.sh       # remove emacs-plus
bash ./uninstall-emacs-native-yamamoto-mac.sh   # remove emacs-mac@30exp
bash ./uninstall-emacs-docker-mac.sh            # remove Docker variant
bash ./uninstall-emacs-orbstack-mac.sh              # remove OrbStack variant

bash ./remove-bitwarden-keychain.sh             # remove Bitwarden master password from Keychain
```

> The Bitwarden Keychain entry is **not** deleted by the uninstall scripts (it is shared). Remove it explicitly with the script above after all variants have been uninstalled.

### `--ask` flag

Pass `--ask` to be prompted before each brew package is removed. Useful when a package (e.g. `ripgrep`) is also used outside Emacs and you want to keep it:

```bash
bash ./uninstall-emacs-native-plus-mac.sh --ask
bash ./uninstall-emacs-native-yamamoto-mac.sh --ask
bash ./uninstall-emacs-docker-mac.sh --ask
```

Without `--ask`, all packages installed by the setup are removed automatically.

---

## git-crypt

The `org/` files and `emacs.d/secrets.el` in the GitHub repo are encrypted with git-crypt. The key is stored in Bitwarden (`emacs-git-crypt-key`, field: `Key`).

After `git-crypt unlock`, setup scripts automatically symlink `~/.emacs.d/secrets.el` to the decrypted repo file. Bitwarden is only used as a fallback if the repo file is missing or still encrypted.

**Manual unlock:**

```bash
bash ./unlock-git-crypt.sh
```

Setup scripts unlock automatically — on first clone and on every subsequent run if the org files are found encrypted.

---

## Theme

All variants use **modus-vivendi** — built into Emacs 28+, designed for high contrast and readability (WCAG AAA standard).

---

## Development

This section is for the repo owner testing changes before promoting them to `stable`.

### Branch structure

| Branch | Purpose |
|---|---|
| `stable` | What new users get via bootstrap. Always a known-good state. |
| `main` | Active development. May contain untested changes. |
| `session-YYYY-MM-DD-working` | Tags marking the last known-good commit of a session. Used for rollback. |

### Reinstall from `stable` (new-user path)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/bootstrap.sh)
```

Bootstrap downloads all scripts from `stable`, configures Bitwarden + GitHub auth, then prompts you to run a setup script.

### Reinstall from `main` (dev/testing path)

Bootstrap always pulls `stable` scripts — use it for first-time machine setup only. For testing `main` changes, work with the local clone directly:

```bash
# Refresh scripts from main
cd /tmp/emacs-mac-setup && git pull origin main

# Run setup directly (brew / gh / Bitwarden already installed)
bash setup-emacs-native-plus-mac.sh
```

Or from scratch on a fresh machine:

```bash
git clone -b main https://github.com/deno1011/emacs-mac-setup.git /tmp/emacs-mac-setup
bash /tmp/emacs-mac-setup/setup-emacs-native-plus-mac.sh
```

### Session tags and rollback

After every working session, tag the last known-good commit:

```bash
git tag session-YYYY-MM-DD-working
git push origin session-YYYY-MM-DD-working
```

Rollback the whole repo:

```bash
git reset --hard session-YYYY-MM-DD-working
```

Restore a single file from a tag:

```bash
git checkout session-YYYY-MM-DD-working -- config.org
```

### Promoting `main` → `stable`

Once changes are tested:

```bash
git checkout stable
git merge main --no-edit
git push origin stable
git checkout main
```

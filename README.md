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
bash <(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/bootstrap.sh)

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
open "/Applications/Emacs (emacs-plus).app"
open "/Applications/Emacs (Yamamoto).app"
```

---

## GitHub Repos

| Repo | Visibility | Purpose |
|---|---|---|
| `emacs-mac-setup` | public | All setup, uninstall, and utility scripts. Also: `init.el`, `config.org`, `setup-emacs-mac.conf.template` |
| `mac-setup-conf` | private | Only `setup-emacs-mac.conf` with personal details. Pulled automatically on bootstrap. No encryption needed — contains no actual secrets. |
| `emacs-config` | private | Emacs config: `config.org`, `org/` files, `emacs.d/secrets.el` (all encrypted with git-crypt). Cloned to iCloud Drive. Synced to iPhone via beorg. |

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
| `config.org` | Default Emacs config — used when `emacs-config` repo is empty |
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

Starts as: `/Applications/Emacs (emacs-plus).app`

### 2. emacs-mac — Yamamoto *(smooth rendering)*

- Emacs 30 with Yamamoto patches
- Pixel-perfect scrolling, better Retina rendering, native trackpad gestures
- Install time: ~15–25 minutes

```bash
bash ./setup-emacs-native-yamamoto-mac.sh
```

Starts as: `/Applications/Emacs (Yamamoto).app`

### 3. Docker *(isolated, XQuartz)*

- Emacs runs in a Docker container, config pulled from GitHub on start
- Display via XQuartz — clipboard image paste not supported
- Only the beorg iCloud folder is mounted — no Mac filesystem exposure

```bash
bash ./setup-emacs-docker-mac.sh
```

App icons in `~/Applications/`:
- `Emacs Docker GUI.app` — graphical Emacs via XQuartz
- `Emacs Docker Console.app` — Emacs in terminal (`-nw`)
- `Emacs Docker Shell.app` — shell inside the container
- `Emacs Docker Root Shell.app` — root shell inside the container

### 4. OrbStack *(isolated, no XQuartz)*

- Emacs runs in an OrbStack Linux machine (Ubuntu 24.04)
- No XQuartz needed — OrbStack handles display natively on macOS 14+
- Mac home directory accessible in the machine → clipboard image paste works
- Requires OrbStack (`brew install --cask orbstack`)

```bash
bash ./setup-emacs-orbstack-mac.sh
```

App launchers in `~/Applications/`:
- `Emacs OrbStack GUI.command` — graphical Emacs
- `Emacs OrbStack Console.command` — Emacs in terminal (`-nw`)
- `Emacs OrbStack Shell.command` — shell inside the machine
- `Emacs OrbStack Root Shell.command` — root shell inside the machine

---

## Starting Emacs

**Native (Plus / Yamamoto):**

```bash
open "/Applications/Emacs (emacs-plus).app"
open "/Applications/Emacs (Yamamoto).app"
# or via Spotlight — type "Emacs"
emacs -nw   # TUI mode
```

**Docker:** Double-click one of the app icons in `~/Applications/`, or use Spotlight.

**OrbStack:** Double-click one of the `.command` launchers in `~/Applications/`, or run `emacs-orb` in the terminal (after reloading shell).

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
Native Emacs              Docker Emacs
     │                         │
on startup:              startup-sync.sh
  git pull + revert           │
  rsync → beorg               │
     │                         │
post-commit hook         post-commit hook
     │                         │
beorg iCloud folder  ◄─────────┘
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
| `config.org` missing | Copied automatically from bundled `config.org` |
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

The setup scripts install the following brew packages automatically:

**All native variants (emacs-plus and Yamamoto):**

| Package | Purpose |
|---|---|
| `emacs-plus@30` / `emacs-mac@30exp` | Emacs itself |
| `bitwarden-cli` | Secret retrieval (git-crypt key, GitHub token, API keys) |
| `gh` | GitHub CLI (repo clone, auth, API) |
| `git-crypt` | Encrypt/decrypt org files in the repo |

**Docker variant (additionally):**

| Package | Purpose |
|---|---|
| `colima` | Docker runtime for macOS |
| `docker` | Docker CLI |
| XQuartz | X11 display server for GUI Emacs |

**config.org-installed packages (brew):**

Installed at first Emacs launch, tracked in `~/.emacs.d/system-packages.log`:

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

**config.org-installed packages (pip):**

| Package | Purpose |
|---|---|
| `matplotlib` | Python plots and math function graphs |
| `numpy` | Numerical computing for Python babel blocks |

The uninstall scripts read `system-packages.log` and remove all tracked packages (brew and pip). Use `--ask` to be prompted before each removal.

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

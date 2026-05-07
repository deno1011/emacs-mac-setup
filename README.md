# Emacs Mac Setup

Automated Emacs setup for macOS. Three installation variants share a common configuration stored on GitHub. Org files are kept in sync with the beorg app on iPhone via iCloud.

---

## Quick Start

**Have these ready before you begin:**

- [ ] [Homebrew](https://brew.sh) installed
- [ ] GitHub account + personal access token — Settings › Developer settings › Personal access tokens › Classic › scope: `repo`
- [ ] Bitwarden account with vault entries (`setup-bitwarden.sh` creates these interactively):

  | Item name | Field | Value |
  |---|---|---|
  | `github-cli-token` | custom field `Key` | GitHub token |
  | `emacs-git-crypt-key` | custom field `Key` | base64 git-crypt key *(required if org/ is encrypted)* |
  | `anthropic-api-key` | custom field `Key` | Anthropic API key *(optional, for gptel)* |

- [ ] GitHub repo named `emacs-config` (can be empty)
- [ ] iCloud Drive enabled (native variants only)

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
bash ./setup-emacs-docker-mac.sh            # isolated in Docker

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
| `emacs-config` | private | Emacs config: `config.org`, `org/` files (encrypted with git-crypt). Cloned to iCloud Drive. Synced to iPhone via beorg. |

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
| `setup-secrets.sh` | Re-fetch Anthropic API key from Bitwarden and rewrite `~/.emacs.d/secrets.el` |

### Install

| Script | Purpose |
|---|---|
| `setup-emacs-native-plus-mac.sh` | Install emacs-plus@30 (native comp, LSP) |
| `setup-emacs-native-yamamoto-mac.sh` | Install emacs-mac@30exp (Yamamoto patches) |
| `setup-emacs-docker-mac.sh` | Install Emacs in a Docker container |

### Uninstall

| Script | Purpose |
|---|---|
| `uninstall-emacs-native-plus-mac.sh` | Remove emacs-plus |
| `uninstall-emacs-native-yamamoto-mac.sh` | Remove emacs-mac@30exp |
| `uninstall-emacs-docker-mac.sh` | Remove Docker variant |

### Utilities

| Script | Purpose |
|---|---|
| `unlock-git-crypt.sh` | Decrypt org/ files in the iCloud repo |
| `remove-bitwarden-keychain.sh` | Delete Bitwarden master password from Keychain |

---

## Prerequisites

**System:**
- macOS 13 Ventura or newer
- [Homebrew](https://brew.sh)
- iCloud Drive enabled (native variants store the repo in iCloud)
- XQuartz — Docker GUI only, installed automatically

**Accounts:**
- GitHub account with a personal access token (Classic, `repo` scope)
- Bitwarden account

**Required config fields** (setup aborts if empty when `GH_USER` is set):
`GIT_NAME` `GIT_EMAIL` `GH_REPO`

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

### 3. Docker *(isolated)*

- Emacs runs in a Docker container, config pulled from GitHub on start
- Only the beorg iCloud folder is mounted — no Mac filesystem exposure

```bash
bash ./setup-emacs-docker-mac.sh
```

App icons in `~/Applications/`:
- `Emacs Docker GUI.app` — graphical Emacs via XQuartz
- `Emacs Docker Console.app` — Emacs in terminal (`-nw`)
- `Emacs Docker Shell.app` — shell inside the container
- `Emacs Docker Root Shell.app` — root shell inside the container

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
post-commit hook         startup-sync.sh
     │                         │
beorg iCloud folder  ◄─────────┘
     │
iPhone (beorg app)
```

**Native (Plus / Yamamoto):**  
A git post-commit hook fires automatically after every commit:
1. Syncs `org/` to `~/Library/Mobile Documents/.../beorg/Documents/org/`
2. Pushes the commit to GitHub (async — does not block Emacs)

`git-auto-commit-mode` commits on every save, so beorg sees changes within seconds.

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

## Uninstall

```bash
bash ./uninstall-emacs-native-plus-mac.sh       # remove emacs-plus
bash ./uninstall-emacs-native-yamamoto-mac.sh   # remove emacs-mac@30exp
bash ./uninstall-emacs-docker-mac.sh            # remove Docker variant

bash ./remove-bitwarden-keychain.sh             # remove Bitwarden master password from Keychain
```

> The Bitwarden Keychain entry is **not** deleted by the uninstall scripts (it is shared). Remove it explicitly with the script above after all variants have been uninstalled.

---

## git-crypt

The `org/` files in the GitHub repo are encrypted with git-crypt. The key is stored in Bitwarden (`emacs-git-crypt-key`, field: `Key`).

**Manual unlock:**

```bash
bash ./unlock-git-crypt.sh
```

Setup scripts unlock automatically on first clone.

---

## Theme

All variants use **modus-vivendi** — built into Emacs 28+, designed for high contrast and readability (WCAG AAA standard).

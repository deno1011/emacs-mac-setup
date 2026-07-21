# Start Here

A preconfigured Emacs distribution for macOS. One command installs
emacs-plus, drops a literate config into `~/.emacs.d/`, and walks you
through a one-time setup form on first launch. After that: a working
agenda, a populated LLM-wiki, a guided `TOUR.org`, and gptel chat with
Claude / GPT / Gemini / Groq / Ollama — wired up against your own API
keys, with credentials kept in Bitwarden and cached in the macOS
Keychain.

## Open Terminal and run

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/install.sh)"
```

Or pin to the last tagged release on the `stable` branch:

```bash
EMACS_MAC_BRANCH=stable /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/install.sh)"
```

After ~10 minutes (most of it `brew install emacs-plus`), Emacs
launches and the setup form opens. You fill in:

- Your Bitwarden master password + login email
- Your GitHub username, fine-grained PAT, and the repo name where your
  Emacs data should live (default: `emacs-data` → `~/emacs-data/`)
- API keys for any LLM provider you actually use (OpenAI / Anthropic /
  Gemini / Groq) — leave any field blank to opt out of that provider
  permanently

Hit Save. The bootstrap orchestrator then:

1. Caches your Bitwarden credentials in the macOS Keychain so future
   launches are silent
2. Writes everything else into a single Bitwarden item
   (`emacs_credentials`) so the same setup follows you to other Macs
3. Clones (or creates) your private data repo into `~/emacs-data/`
4. Seeds missing starter Org files for the compact GTD setup:
   `inbox.org`, `gtd.org`, `calendar.org`, `archive.org`, GTD/coaching
   skills, and the neutral GTD source registry template

Next launch: nothing prompts, your data folder is already cloned, the
agenda already finds your org files, gptel chat already has its keys.
The form only re-opens if something is missing.

## What's installed

| Component | Where it goes | Source of truth |
|---|---|---|
| `emacs-plus@30` | `/Applications/Emacs Plus.app` | Homebrew |
| Literate config | `~/.emacs.d/config/` | this repo (refreshed by `install.sh`) |
| `async-tasks` framework | `~/.emacs.d/config/modules/10_tasks.el` | [`deno1011/async-tasks`](https://github.com/deno1011/async-tasks) (vendored by install.sh) |
| Emacs Agent Runtime | `~/emacs-agent-runtime/` | [`deno1011/emacs-agent-runtime`](https://github.com/deno1011/emacs-agent-runtime) (cloned/updated by `install.sh`) |
| QMD retrieval CLI | optional global CLI | [`@tobilu/qmd`](https://github.com/tobi/qmd), only via `M-x my/emacs-agent-runtime-qmd-install` |
| Org/EAR diagram renderers | optional Homebrew CLIs | Graphviz, PlantUML, Mermaid CLI, D2; only via `M-x my/org-diagram-renderers-install` |
| MLX local model | `~/.emacs.d/ear-mlx/` | [`mlx-lm`](https://github.com/ml-explore/mlx-lm), only via `M-x my/emacs-agent-runtime-mlx-install` |
| Personal data (agenda, GTD, wiki) | `~/emacs-data/` (or whatever Repo name you picked) | your private GitHub repo |
| Bitwarden master + email | macOS Keychain (`emacs_credentials` service) | Bitwarden |
| GitHub PAT + API keys | Bitwarden item `emacs_credentials`, mirrored to Keychain | Bitwarden |

The split is deliberate: distro code lives at `~/.emacs.d/`
(overwritten by `install.sh` on every run), per-Mac credentials live in
the macOS Keychain (never leave the machine), the canonical source of
truth for credentials is your Bitwarden vault (so a fresh Mac picks
them up by just unlocking BW), and your personal data lives in your
private GitHub repo (you cross-Mac sync however you want).

## What runs in the background

The first launch also kicks off two fire-and-forget background tasks:

- **distro config update** — pulls the latest tip of whichever branch
  you installed from, every launch, so distro fixes reach you without
  you running `install.sh` again. Status: `M-x async-tasks-status` →
  look for `distro-config-update`.
- **daemon service install** — registers Emacs as a launchd service so
  later `emacs` launches go through `emacsclient` for instant startup.
  Status in the same list: `emacs-daemon-service-setup`.

Both are observable via the modeline indicator (`⌛N` while N tasks
run, `✗N` if any failed) and cancelable with `M-x async-tasks-cancel`.

## Update later

```bash
bash ~/emacs-mac-setup-src/install.sh
```

Pulls the latest distro code on whichever branch you installed from.
Re-fetches `async-tasks.el` from upstream so the vendored framework
stays current and updates `~/emacs-agent-runtime/`. Never touches
`~/emacs-data/` or your Keychain entries except to add missing starter files
through the bootstrap. Optional QMD retrieval support is configured in EAR, but
the `qmd` CLI is installed only from inside Emacs via
`M-x my/emacs-agent-runtime-qmd-install`; it does not index your Org files
automatically.
Optional MLX local-model support is also configured, but Python packages and
model weights are downloaded only when you explicitly run
`M-x my/emacs-agent-runtime-mlx-install`. Start it later with
`M-x my/emacs-agent-runtime-mlx-start-server`.
Optional EAR dashboard diagram rendering is configured the same way: renderer
CLIs are provisioned only when you explicitly run
`M-x my/org-diagram-renderers-install`.

After a fresh install, run `M-x my/doctor`. It checks that EAR is loadable, that
the reusable starter pack is present, and that the optional QMD retrieval pack
files and optional diagram renderers are available without installing QMD or
reading private Org data.

## Uninstall

```bash
bash ~/emacs-mac-setup-src/uninstall.sh
# --purge-data also wipes ~/emacs-data/ (irreversible)
# --keep-emacs-app preserves Emacs Plus.app + the brew formula
```

Removes `~/.emacs.d/`, the cloned distro source, the Emacs Plus app
bundle, and the brew formula. Your data folder, Keychain entries,
Bitwarden vault are all left untouched unless you pass `--purge-data`.

## Per-Mac credential override

The `EMACS_DATA_DIR` env var overrides the auto-derived data folder
path (the one that comes from your Bitwarden `Repo` field). Useful for
scripted installs or testing.

```bash
EMACS_DATA_DIR=/Users/me/scratch-emacs/  bash install.sh
```

## Pin a specific async-tasks release

The vendored task framework defaults to `main`. To lock to a tagged
release:

```bash
EMACS_MAC_ASYNC_TASKS_TAG=v0.1.0  bash install.sh
```

The same `EMACS_MAC_ASYNC_TASKS_REPO=user/fork` env var lets you point
the curl at a fork for testing.

## Override init.el entirely

Create `~/.emacs.d/override_init.el`. The distro's init.el detects
that file, loads it verbatim, and skips its own logic. install.sh
overwrites init.el on every run; override_init.el is never touched, so
you can keep a fully custom setup that survives distro updates.

## Architecture in two paragraphs

The literate config lives in numbered modules under
`~/.emacs.d/config/modules/`. `!00_startfirst.el` bootstraps elpaca
(source-loaded — never byte-compiled, because elpaca's macros need to
be defined before they're used in the same file). `00_startfirst.org`
sets the dark theme and fullscreen. `10_tasks.el` is the
async-tasks framework (vendored from upstream). `20_bootstrap.org`
defines every credential primitive, the setup form, and the orchestrator
that runs once at the end of its own load — so by the time
`30_core.org` / `40_org.org` / etc. tangle, `my/data-dir` is final and
all module-level paths resolve correctly.

The orchestrator's job is to make every subsequent launch silent. It
probes the Keychain first (no Bitwarden round-trip in the steady
state); only when Keychain is missing something does it unlock
Bitwarden and rehydrate from the canonical item there. The setup form
only opens when neither source has the values it needs.

## Cross-Mac sync

Your data folder is a real GitHub repo — sync mechanics are git.
Whichever Mac you install onto, the Bitwarden `Repo` field tells the
bootstrap which repo to clone, the GH PAT in the same item authorizes
the clone, and you're done. No iCloud / Syncthing / Dropbox needed,
though they all still work if you prefer a sync mechanism that's
already running.

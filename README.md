# emacs-mac-setup

Opinionated, preconfigured Emacs distribution for macOS. One curl, one
command, fully wired: installs emacs-plus@30, lays down a literate
config under `~/.emacs.d/`, clones your private data repo (org files,
wiki, agenda), and survives toolchain quirks (libgccjit, LaunchAgent
env loss, etc.) through four explicit protection layers.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/install.sh)"
```

See [`!STARTHERE.md`](!STARTHERE.md) for the user-facing walkthrough.

Conservative install from the `stable` branch (last tagged release):

```bash
EMACS_MAC_BRANCH=stable /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/install.sh)"
```

---

## Layout

```
emacs-mac-setup/
├── install.sh                        # the only thing the curl one-liner runs
├── uninstall.sh
├── !STARTHERE.md                     # user-facing intro (GitHub landing page)
├── README.md                         # this file
├── .gitignore
│
└── emacs.d/                          # mirrors ~/.emacs.d/ layout 1:1
    ├── early-init.el                 # GC tuning + env snapshot loader + UTF-8 + dark frame
    ├── init.el                       # thin loader + override_init.el escape hatch
    ├── secrets.el.template
    └── config/
        ├── CONVENTIONS.md            # general code rules for non-bootstrap modules
        ├── config.org                # discovery loop + my/-load-module (3-tier cache)
        └── modules/
            ├── !00_startfirst.el     # source-loaded elpaca bootstrap
            ├── 00_startfirst.org     # dark theme + fullscreen
            ├── 10_tasks.el           # async-tasks framework (vendored)
            ├── 20_bootstrap/         # the bootstrap subsystem
            │   ├── BOOTSTRAP.md      # complete ruleset for bootstrap code
            │   ├── 20.01.01_bootstrap_keychain.org    ← Layer 1 (macOS Keychain)
            │   ├── 20.01.02_bootstrap_git.org         ← Layer 1 (git)
            │   ├── 20.01.03_bootstrap_gh.org          ← Layer 1 (gh CLI)
            │   ├── 20.02.01_bootstrap_repo.org        ← Layer 2 (resolve data-dir)
            │   ├── 20.02.02_bootstrap_repo_clone.org  ← Layer 2 (clone repo)
            │   ├── 20.02.03_bootstrap_secrets.org     ← Layer 2 (API keys + form)
            │   ├── 20.02.04_bootstrap_identity.org    ← Layer 2 (git config + gh auth)
            │   └── 20.03.01_bootstrap.org             ← Layer 3 (orchestrator)
            ├── 20_bootstrap.org.old  # retired legacy monolith — kept for reference, not loaded
            ├── 30_core.org           # base Emacs, completion, magit, modeline
            ├── 40_org.org            # org-mode, agenda, GTD, capture, org-roam, LaTeX
            ├── 50_apple_reminders.org
            ├── 60_gptel.org          # LLM backends (Claude, OpenAI, Gemini, Groq, …)
            ├── 70_wiki.org           # LLM-Wiki helpers
            ├── 80_gtd.org            # GTD overlay loader
            └── 90_doctor.org         # M-x my/doctor — health check
```

Both `.org` and `.el` are tracked. `.elc` is git-ignored. See
"Cache priority" below for what happens on each launch.

---

## What runs when you start Emacs

`config.org`'s discovery loop walks `modules/` recursively, sorting
files and subdirectories together by `string<`. Numeric prefixes drive
the order; underscores separate prefix from name; bumping a number
moves a module without renaming. A subdirectory participates in the
sort by its bare name — `20_bootstrap/` slots in between
`10_tasks.el` and `30_core.org` without any code change.

Actual load order on a populated install:

```
!00_startfirst.el                                 — elpaca bootstrap (source-loaded)
00_startfirst.org                                  — dark theme, fullscreen
10_tasks.el                                        — async-tasks framework
20_bootstrap/20.01.01_bootstrap_keychain.org       ← Layer 1
20_bootstrap/20.01.02_bootstrap_git.org            ← Layer 1
20_bootstrap/20.01.03_bootstrap_gh.org             ← Layer 1
20_bootstrap/20.02.01_bootstrap_repo.org           ← Layer 2
20_bootstrap/20.02.02_bootstrap_repo_clone.org     ← Layer 2
20_bootstrap/20.02.03_bootstrap_secrets.org        ← Layer 2
20_bootstrap/20.02.04_bootstrap_identity.org       ← Layer 2
20_bootstrap/20.03.01_bootstrap.org                ← Layer 3 (auto-fires my/bootstrap)
30_core.org                                        — base Emacs
40_org.org                                         — org + agenda + roam
50_apple_reminders.org
60_gptel.org
70_wiki.org
80_gtd.org
90_doctor.org                                      — M-x my/doctor
```

### Cache priority (3-tier)

`my/-load-module` decides per file:

| Tier | Condition | Cost | Hits |
|---|---|---|---|
| 1 | `.elc` newer than the source | ~10 ms | steady-state (90% of launches) |
| 2 | `.org`, `.el` newer than `.org`, no `.elc` | ~50 ms (byte-compile only) | fresh install (rsync mtimes), post-`eln-cache` wipe |
| 3 | `.org` newer than `.el` and `.elc` | 50–350 ms (re-tangle + compile) | after you edit the `.org` |

`install.sh`'s post-install AOT byte-compile (see Layer C below)
makes every module hit Tier 1 on the first launch after install.

---

## Bootstrap subsystem (`20_bootstrap/`)

A three-layer architecture for the credential / data-folder /
identity provisioning. Self-contained ruleset in
[`emacs.d/config/modules/20_bootstrap/BOOTSTRAP.md`](emacs.d/config/modules/20_bootstrap/BOOTSTRAP.md).

The orchestrator (`my/bootstrap`) runs four steps in order:

| # | Step | Layer-2 function | Required? |
|---|---|---|---|
| 1 | data-folder resolution | `my/data-dir-resolve` | YES |
| 2 | data-folder clone | `my/repo-ensure-cloned` | YES |
| 3 | github identity | `my/identity-ensure-loaded` | optional |
| 4 | secrets readable | `my/secrets-ensure-readable` | optional |

A required-step failure halts the bootstrap with a `*Warnings*`
popup containing the exact shell command to fix it. Feature modules
guard path-dependent code with `(when (my/bootstrap-ready-p) …)`, so
Emacs comes up cleanly even when bootstrap halts — Org-mode still
loads for editing, just no agenda paths configured.

All credentials live in one macOS Keychain service
(`emacs_credentials`). Nine entries:

| Account | Required | Layer-2 owner |
|---|---|---|
| `GitHubRepo` | yes | repo (`20.02.01`) |
| `GitHubUsername` | yes | repo-clone (`20.02.02`) |
| `GitHubToken` | optional | identity (`20.02.04`) |
| `GitHubFullname` | optional | identity (`20.02.04`) |
| `GitHubEmail` | optional | identity (`20.02.04`) |
| `OPENAI_API_KEY`     | optional | secrets (`20.02.03`) |
| `ANTHROPIC_API_KEY`  | optional | secrets (`20.02.03`) |
| `GEMINI_API_KEY`     | optional | secrets (`20.02.03`) |
| `GROQ_API_KEY`       | optional | secrets (`20.02.03`) |

API keys can be marked `__SKIPPED__` to permanently opt out of a
backend without nagging.

---

## Feature modules (`30_*` and up)

Sequential, flat, growable per `emacs.d/config/CONVENTIONS.md`. No
three-layer architecture — each file configures one feature area
with `use-package` blocks, helper defuns, and per-section Org
headings.

| Module | Concern |
|---|---|
| `30_core.org` | base Emacs, completion, modeline, magit, font, GC, font |
| `40_org.org` | org-mode + agenda + GTD + capture + LaTeX + org-roam |
| `50_apple_reminders.org` | Apple Reminders bidirectional sync |
| `60_gptel.org` | LLM backends — Claude, ChatGPT, Gemini, Groq, GitHub Models, Ollama, LM Studio, MLX |
| `70_wiki.org` | LLM-Wiki helpers (Karpathy pattern, org-roam-backed) |
| `80_gtd.org` | Thin loader for `~/emacs/data/org/gtd-config.el` |
| `90_doctor.org` | `M-x my/doctor` — health check command |

---

## Protection layers

Inspired by Doom Emacs's reliability mechanisms, adapted to this
codebase. Four layers; the third is intentionally skipped (see why).

### Layer A — env snapshot (Doom-env equivalent)

`install.sh` writes `~/.emacs.d/env-snapshot.el` capturing PATH,
LIBRARY_PATH, MANPATH, INFOPATH from the install shell (which has
brew shellenv sourced and your zsh profile loaded). `early-init.el`
sources it on every launch BEFORE anything tries to find brew, gcc,
or libgccjit.

This prevents the failure where emacs-plus@30's LaunchAgent starts
Emacs without ~/.zshrc env vars — libgccjit fails to find gcc,
native-comp falls back to interpreted, the user sees no error until
.eln files are missing.

### Layer B — exec-path-from-shell: intentionally NOT used

The standard `exec-path-from-shell` package would need to load AFTER
elpaca bootstrap (i.e. AFTER `!00_startfirst.el`), which is too late
for native-comp's first invocations. Layer A's snapshot mechanism
runs in `early-init.el` — strictly earlier than any elpa package
can. The hardcoded LIBRARY_PATH fallback in `early-init.el` covers
installs where the snapshot file is missing.

### Layer C — AOT byte-compile (post-install pre-warming)

`install.sh` runs `emacs --batch ... batch-byte-compile` over every
`.el` under `modules/` immediately after rsync. The shell still has
all tools available, the user is not yet waiting. Effect on first
launch: every module hits Tier 1 of the loader (~10 ms each)
instead of Tier 3 (re-tangle + compile, 50-350 ms each). Total
config-discovery cost drops from 1-5 seconds to ~150 ms.

### Layer D — `M-x my/doctor` (health check)

The interactive equivalent of `doom doctor`. Runs 11 checks in 4
sections:

```
Toolchain       — brew, gcc-15, libgccjit, native-comp,
                  LIBRARY_PATH, eln-cache writable
Bootstrap state — my/bootstrap-ready-p, my/data-dir,
                  data folder is correct clone
Credentials     — every Keychain entry classified
                  set / skipped / missing-optional / missing-required
External        — gh CLI authentication
```

Per failed check: a literal `FIX:` line with the exact shell
command. Re-run with `M-x my/doctor-rerun` after applying a fix.
The doctor uses `fboundp` / `boundp` throughout, so it still works
when bootstrap halted (which is the case where you most need it).

---

## User-facing commands

| Command | What it does |
|---|---|
| `M-x my/bootstrap` | Re-run the orchestrator (idempotent; reflects current Keychain state). |
| `M-x my/credential-set` | Set or rotate ANY of the 9 bootstrap credentials. Unified completing-read menu. |
| `M-x my/api-key-set` | Focused on the 4 LLM API keys (convenience). |
| `M-x my/doctor` | Run 11 health checks, render `*Doctor*` buffer. |
| `M-x my/doctor-rerun` | Re-run after applying a fix. |

---

## Override hatches

| Override | How | What it does |
|---|---|---|
| `~/.emacs.d/override_init.el` | create the file | init.el loads it and skips its own logic; survives install.sh overwrites |
| `EMACS_DATA_DIR=/path` | env var | overrides the auto-derived data folder path |
| `EMACS_MAC_BRANCH=branch` | env var (persisted in `~/.emacs.d/distro-source.el`) | install.sh installs from a non-`main` branch |
| `EMACS_MAC_ASYNC_TASKS_REPO=user/fork` + `_TAG=v0.1.0` | env vars | install.sh fetches `async-tasks.el` from a fork / pinned release |
| `~/.emacs.d/config/modules/local.org` | create the file | loads LAST in discovery; can shadow any module's setting |

---

## Update flow

```bash
bash ~/emacs-mac-setup-src/install.sh
```

Pulls the latest distro on whichever branch you installed from
(persisted via `~/.emacs.d/distro-source.el`), refreshes
`async-tasks.el` from upstream, rsyncs `emacs.d/config/` to
`~/.emacs.d/config/`, copies `init.el` + `early-init.el`,
regenerates `env-snapshot.el`, and runs AOT byte-compile. Never
touches `~/.emacs.d/custom.el`, `~/.emacs.d/secrets.el`, or your
data folder.

After the install, restart the daemon to pick up changes:

```bash
emacsclient -e '(kill-emacs)'
open ~/Applications/Emacs\ Client.app
```

---

## Branches

- `main` — current production tip; recommended for the curl
  one-liner unless you have a specific reason to pin.
- `stable` — last tagged release; identical to whatever `main` was
  at the time of the most recent tag. Move with deliberate steps.
- Tags — semver. `v1.x` is the pre-orchestrator distro-model.
  `v2.x` introduced the Bitwarden + Keychain orchestrator. The
  current head re-architects to Keychain-only, splits bootstrap
  into a layered subsystem, adds the protection layers, and adds
  `M-x my/doctor`.

Install from any non-`main` branch:

```bash
EMACS_MAC_BRANCH=branch-name /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/branch-name/install.sh)"
```

---

## Where to read more

| Topic | File |
|---|---|
| General code conventions (feature modules) | [`emacs.d/config/CONVENTIONS.md`](emacs.d/config/CONVENTIONS.md) |
| Bootstrap subsystem ruleset (strict) | [`emacs.d/config/modules/20_bootstrap/BOOTSTRAP.md`](emacs.d/config/modules/20_bootstrap/BOOTSTRAP.md) |
| User walkthrough | [`!STARTHERE.md`](!STARTHERE.md) |

---

## Uninstall

```bash
bash ~/emacs-mac-setup-src/uninstall.sh
```

Removes the cloned distro source, the `~/.emacs.d/` directory
(moved to a timestamped backup), the Emacs Plus app bundle, and
the brew formula. Your data folder, Keychain entries, and
Bitwarden vault are left untouched. Add `--purge-data` to also
delete your data folder, or `--keep-emacs-app` to leave Emacs
Plus.app + the brew formula installed.

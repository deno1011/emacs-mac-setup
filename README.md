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
        ├── starter-data/org/         # first-install Org starter files
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
            │   ├── 20.02.05_bootstrap_git_crypt.org   ← Layer 2 (git-crypt unlock)
            │   ├── 20.02.06_bootstrap_starter_data.org ← Layer 2 (starter Org files)
            │   └── 20.03.01_bootstrap.org             ← Layer 3 (orchestrator)
            ├── 20_bootstrap.org.old  # retired legacy monolith — kept for reference, not loaded
            ├── 30_core.org           # base Emacs, completion, magit, modeline
            ├── 40_org.org            # org-mode, agenda, GTD, capture, org-roam, LaTeX
            ├── 50_apple_reminders.org
            ├── 60_gptel.org          # LLM backends (Claude, OpenAI, Gemini, Groq, …)
            ├── 70_wiki.org           # LLM-Wiki helpers
            ├── 80_gtd.org            # compact GTD defaults + assistant skill manuals
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
20_bootstrap/20.01.04_bootstrap_git_crypt.org      ← Layer 1
20_bootstrap/20.02.01_bootstrap_repo.org           ← Layer 2
20_bootstrap/20.02.02_bootstrap_repo_clone.org     ← Layer 2
20_bootstrap/20.02.03_bootstrap_secrets.org        ← Layer 2
20_bootstrap/20.02.04_bootstrap_identity.org       ← Layer 2
20_bootstrap/20.02.05_bootstrap_git_crypt.org      ← Layer 2
20_bootstrap/20.02.06_bootstrap_starter_data.org   ← Layer 2
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

The orchestrator (`my/bootstrap`) runs six steps in order:

| # | Step | Layer-2 function | Required? |
|---|---|---|---|
| 1 | data-folder resolution | `my/data-dir-resolve` | YES |
| 2 | data-folder clone | `my/repo-ensure-cloned` | YES |
| 3 | git-crypt unlock | `my/git-crypt-ensure-unlocked` | YES |
| 4 | starter Org files | `my/starter-data-ensure` | YES |
| 5 | github identity | `my/identity-ensure-loaded` | optional |
| 6 | secrets readable | `my/secrets-ensure-readable` | optional |

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
| `80_gtd.org` | Compact GTD defaults, capture/templates, project views, higher-horizon views, assistant manuals |
| `90_doctor.org` | `M-x my/doctor` — health check command |

---

## Compact GTD user manual

New installs seed a small GTD system in the selected data repo. The
starter files are copied only when missing, so existing user files are
never overwritten.

| File | Purpose |
|---|---|
| `data/org/inbox.org` | raw capture, brain dumps, and unclarified items |
| `data/org/gtd.org` | next actions, projects, waiting-for, someday/maybe, tickler, review lists, and the in-file manual |
| `data/org/calendar.org` | appointments, hard deadlines, and dated commitments |
| `data/org/archive.org` | default archive target for completed/cancelled items |
| `data/org/gtd/{projects,next,waiting,someday,tickler,reference}.org` | optional split GTD operational files seeded when missing |
| `data/org/gtd/sources.org` | neutral GTD source registry template for provider-backed inbox/calendar/reminder sources |
| `data/org/gtd/{daily-coach,scheduling-policy,inbox-clarifier,weekly-review-coach,horizon-coach,life-coach,life-agent-roles}.org` | GTD, coaching, role, and Memento-ready assistant skill manuals seeded when missing |

The seed that creates the in-system manual is
[`emacs.d/config/starter-data/org/gtd.org`](emacs.d/config/starter-data/org/gtd.org).
The GTD/coaching assistant skill manuals are seeded from
[`emacs.d/config/starter-data/org/gtd/`](emacs.d/config/starter-data/org/gtd/).
The same directory also contains split GTD operational file templates
for users who prefer smaller files or already have a split setup.
The initially empty top-level headings in that file are intentional
landing zones for capture and refile. They start empty so a new system
contains real user actions, not installer sample tasks.

Reusable EAR behavior that is not specific to one user's GTD data lives in the
separate `emacs-agent-runtime` checkout.  Its package `knowledge/` directory is
loaded by EAR itself and can ship neutral coaching, Memento, session, workflow,
job, and future dreams guidance to new users.  The setup starter files remain
the place for local GTD/profile manuals and provider-specific examples.

Optional local retrieval uses QMD through EAR's neutral `ear-retrieval`
boundary. QMD is not a hard dependency and is not installed by default. To add
the reviewed CLI during install:

```bash
EMACS_QMD_INSTALL=1 bash ~/emacs-mac-setup-src/install.sh
```

The installer uses `npm install -g @tobilu/qmd@2.6.3` by default after ensuring
Node is available. A Bun install can be requested with
`EMACS_QMD_PACKAGE_MANAGER=bun`. Installing QMD only provides the `qmd` command;
it does not start a daemon, download models, export projections, or index
private Org files. EAR keeps Org as source of truth and expects generated
Markdown projections under the configured QMD projection directory.

The current EAR test-user setup intentionally enables God Mode, write tools,
Codex approval bypass, and persistent jobs so coaching behavior can be tested
end to end. Product-ready installs should later switch to source-aware,
tenant-aware policies that can distinguish the owner's trusted Emacs/chat
inputs from delegated or third-party messenger input.

Existing installs get any newly added starter files by running
`M-x my/starter-data-ensure` after updating the setup, or simply by
restarting Emacs so `M-x my/bootstrap` runs during startup.

Use the system as a loop: capture everything unfinished into
`inbox.org`, clarify one inbox item at a time, organize it into the
right trusted bucket, review daily/weekly, then engage from agenda views
by context, time, energy, and priority.

Use the small TODO keyword set deliberately:

```org
TODO       not yet ready or not yet selected as the next physical action
NEXT       the next visible action you can do
WAITING    delegated, blocked, or waiting for external input
DONE       completed
CANCELLED  intentionally dropped
```

Clarify inbox items by asking whether the item is actionable, whether
it is one physical next action or a multi-step outcome, whether it
belongs on a date, whether someone else owns it, and whether it should
instead become reference, someday/maybe, or trash.

Projects are marked by a local `:project:` tag. The tag is excluded
from inheritance, so children can inherit normal context/topic tags
without making every child look like a project in agenda views.
Use `C-c g p` on a heading to mark it as a project, or `C-u C-c g p`
to also set `CATEGORY`.

This follows Karl Voit's Org project model: a project remains a normal
TODO heading, marked with `:project:`, a progress cookie, recursive
`COOKIE_DATA`, and an ID. During migration, TODO headings with TODO
children are still treated as projects so older data remains visible.

```org
** TODO [/] Renew driving license :project:admin:
:PROPERTIES:
:CATEGORY: license
:COOKIE_DATA: todo recursive
:END:
*** NEXT Find required city-office documents :@computer:
*** TODO Book appointment :@computer:
*** WAITING Confirmation from city office
```

If a task grows, promote it into its own project and link it to the
parent with an Org ID link or an `org-super-links` backlink instead of
forcing everything into one large tree. Use `org-edna` only for real
dependencies that should block or trigger state changes automatically.

`org-edna` is installed by Elpaca from
`https://github.com/emacsmirror/gnu_elpa`, branch
`externals/org-edna`, pinned to commit
`8258a4dfa00aa522249cdf9aeea5be4de97bd7c1`.

`org-super-links` is installed by Elpaca from
`https://github.com/toshism/org-super-links.git`, branch `develop`,
pinned to commit `ce53993edc0fcfb85289f3eea74d1caa4dce8b60`.

Backlink keys:

| Key | Command |
|---|---|
| `C-c g s` | create a bidirectional super link by search |
| `C-c g l` | store current heading for later super-link insertion |
| `C-c g i` | insert the stored super link here |
| `C-c g d` | delete the super link at point and its backlink |

Use `C-c g e` on an Org heading, or `M-x my/org-edna-edit`, to edit the
`BLOCKER` and `TRIGGER` properties. In the Edna edit buffer, write only
the value below the `BLOCKER` or `TRIGGER` section header and save with
`C-c C-c`. Use `M-x org-id-get-create` on the target headings first so
the IDs are stable.

```org
:BLOCKER: ids("id:parent-project-id")
:TRIGGER: ids("id:child-action-id") todo!(NEXT)
```

Daily review: empty `inbox.org`, check `calendar.org`, and choose a
realistic set of `NEXT` actions. Weekly review: inspect every
`:project:` heading, make sure each active project has a `NEXT` child,
then review `WAITING`, `Someday / Maybe`, areas, goals, and life
horizons.

Agenda keys under `C-c a`:

| Key | View |
|---|---|
| `g` | GTD dashboard |
| `r` | weekly review |
| `J` | all active projects |
| `X` | stuck projects without a `NEXT` child |
| `B` | blocked and waiting items |
| `H` | `@home` next actions |
| `C` | `@computer` next actions |
| `E` | `@errand` next actions |
| `K` | `@calls` next actions |
| `A` | areas |
| `G` | goals |
| `L` | life and values |
| `R` | higher-horizon review |
| `f` | flights and travel |

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
| `EMACS_AGENT_RUNTIME_REPO_URL=url` | env var (persisted in `~/.emacs.d/distro-source.el`) | install.sh clones/updates EAR from a fork or alternate remote |
| `EMACS_AGENT_RUNTIME_BRANCH=branch` | env var (persisted in `~/.emacs.d/distro-source.el`) | install.sh checks out a non-`main` EAR branch |
| `EMACS_AGENT_RUNTIME_DIR=/path` | env var (persisted in `~/.emacs.d/distro-source.el`) | install.sh clones EAR to a custom path and the Emacs loader uses that path |
| `EMACS_QMD_INSTALL=1` | env var | optionally installs the reviewed QMD retrieval CLI; default is off |
| `EMACS_QMD_PACKAGE_MANAGER=npm\|bun` | env var | chooses the QMD global installer when `EMACS_QMD_INSTALL=1` |
| `EMACS_MAC_ASYNC_TASKS_REPO=user/fork` + `_TAG=v0.1.0` | env vars | install.sh fetches `async-tasks.el` from a fork / pinned release |
| `~/.emacs.d/config/modules/NN_yours.org` | add a high-numbered module | discovery loads modules in numeric order, so a high `NN` shadows earlier modules' settings |
| iCloud CalDAV / account secrets | `M-x my/caldav-setup` → macOS Keychain | per-Mac account & secret values (CalDAV URL with DSID, calendar UUID, Apple ID, app-password) live in the Keychain, never in a config file |

---

## Update flow

```bash
bash ~/emacs-mac-setup-src/install.sh
```

Pulls the latest distro on whichever branch you installed from
(persisted via `~/.emacs.d/distro-source.el`), updates the separate
`~/emacs-agent-runtime` checkout, refreshes `async-tasks.el` from upstream,
rsyncs `emacs.d/config/` to
`~/.emacs.d/config/`, copies `init.el` + `early-init.el`,
regenerates `env-snapshot.el`, and runs AOT byte-compile. Never
touches `~/.emacs.d/custom.el`, `~/.emacs.d/secrets.el`, or your
data folder. QMD remains skipped unless you explicitly pass
`EMACS_QMD_INSTALL=1`.

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

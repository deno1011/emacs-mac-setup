# emacs-mac-setup

Preconfigured Emacs distribution for macOS. One curl, one command,
fully wired after a one-time setup form on first launch — installs
emacs-plus, drops a literate config under `~/.emacs.d/`, clones your
private data repo into the path stored in Bitwarden, and seeds it with
a sample agenda, a populated LLM-wiki, and a guided `TOUR.org`.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/install.sh)"
```

See [`!STARTHERE.md`](!STARTHERE.md) for the user-facing walkthrough.

Conservative install from the `stable` branch (frozen at the last
tagged release):

```bash
EMACS_MAC_BRANCH=stable /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/install.sh)"
```

## Layout

```
emacs-mac-setup/
├── install.sh                        # the only thing the curl one-liner runs
├── uninstall.sh
├── !STARTHERE.md                     # user-facing intro (GitHub landing page)
├── README.md                         # this file
├── .gitignore                        # *.elc, .claude/, editor temp files
│
└── emacs.d/                          # mirrors ~/.emacs.d/ layout 1:1
    ├── early-init.el                 # GC tuning, package.el silenced, UTF-8 defaults
    ├── init.el                       # thin loader + override_init.el escape hatch
    ├── secrets.el.template           # template; copied to secrets.el on first install
    └── config/                       # rsynced to ~/.emacs.d/config/ on install
        ├── config.org                # discovery loop + my/-load-module
        └── modules/
            ├── !00_startfirst.el     # source-loaded elpaca bootstrap (no byte-compile)
            ├── 00-startfirst.org / .el   # dark theme + fullscreen
            ├── 10-tasks.el           # async-tasks framework (vendored from deno1011/async-tasks)
            ├── 20-bootstrap.org / .el    # credentials + form + orchestrator
            ├── 30-core.org / .el     # base Emacs, completion, magit
            ├── 40-org.org / .el      # org-mode, agenda, GTD, capture, LaTeX
            ├── 50-apple-reminders.org / .el
            ├── 60-gptel.org / .el    # gptel + gptel-agent-runtime + provider backends
            ├── 70-wiki.org / .el     # LLM-Wiki helpers
            └── 80-gtd.org / .el      # GTD overlay
```

Both `.org` and `.el` are tracked. The `.el` is the tangled output of
the `.org` — shipped pre-tangled so the user's first launch doesn't
have to do the org-babel round-trip. `.elc` is git-ignored; it's
byte-compiled fresh by the user's Emacs at load time, where elpaca's
macros are already in scope.

## Architecture

### Source-of-truth split

| Layer | Owned by | Source of truth | Sync mechanism |
|---|---|---|---|
| Distro code (`emacs.d/` — including the `config/` subdir that lands at `~/.emacs.d/config/`) | this repo | upstream `git` | `install.sh` → `rsync` |
| `async-tasks` framework | [`deno1011/async-tasks`](https://github.com/deno1011/async-tasks) | upstream git | `install.sh` → `curl` → `~/.emacs.d/config/modules/10-tasks.el` |
| Per-Mac credentials | Bitwarden + macOS Keychain | Bitwarden item `emacs_credentials` | bootstrap orchestrator syncs Keychain → BW on form save; probe rehydrates Keychain from BW when needed |
| Per-user data (agenda, wiki) | the user's private GitHub repo | git | bootstrap clones once; `M-x my/repo-sync-now` for explicit pull |
| Per-Mac runtime state (custom.el, eln-cache) | `~/.emacs.d/` | local | not synced |

### Bootstrap flow

`config.org`'s discovery loop loads modules in sorted-by-name order.
`!` sorts before digits, so the first module is always
`!00_startfirst.el` — a source-loaded (never byte-compiled) elpaca
bootstrap. It clones elpaca, builds `elpaca-use-package`, and blocks
on `(elpaca-wait)` until both are available. Subsequent modules can
then use `(use-package … :ensure …)` with the elpaca recipe form.

`00-startfirst.org` paints the dark theme. `10-tasks.el` (vendored
async-tasks) installs the task framework's session marker and orphan
cleanup. `20-bootstrap.org` defines every credential primitive, the
setup form, the orchestrator, and the eight orchestrator steps:

1. **probe-credentials** — read Keychain; if complete, skip the form
2. **ensure-form-submitted** — open form only if Keychain probe failed
3. **ensure-data-folder** — clone or adopt the GitHub data repo
4. **unlock-git-crypt** — apply key if the repo is git-crypt-encrypted
5. **refresh-keychain** — sync Keychain from BW (skip if already in sync)
6. **generate-starter-data** — write `TOUR.org`, gtd files, wiki pages
7. **authenticate-gh** — `gh auth login` from BW token if needed
8. **finalize** — lock BW, log summary

The orchestrator runs as the last form of `20-bootstrap.el` so
`my/data-dir` is final before `30-core` / `40-org` / etc. tangle. By
the time `40-org.org`'s `:config` runs `(setq org-agenda-files …)`
relative to `my/data-dir`, the data folder is already cloned + seeded.

### Auto-update on every launch

The orchestrator fires two background `async-tasks-shell` jobs as
fire-and-forget:

- `distro-config-update` — pulls latest tip of the installed branch
- `emacs-daemon-service-setup` — registers the Emacs daemon launchd
  service if it's not already there

Both observable via the modeline indicator (`⌛N` running, `✗N`
failed) and `M-x async-tasks-status`.

### Override hatches

| Override | How | What it does |
|---|---|---|
| `~/.emacs.d/override_init.el` | create the file | init.el loads it and skips its own logic; survives `install.sh` overwrites |
| `EMACS_DATA_DIR=/path` | env var | overrides the auto-derived data folder path |
| `EMACS_MAC_BRANCH=branch` | env var (persisted in `~/.emacs.d/distro-source.el`) | install.sh installs from a non-`main` branch |
| `EMACS_MAC_ASYNC_TASKS_REPO=user/fork` + `_TAG=v0.1.0` | env vars | install.sh fetches `async-tasks.el` from a fork / pinned release |

### Failure surfacing

install.sh's section 6c (`Vendor async-tasks`) refuses to leave you in
a broken state: if the curl fails AND no on-disk copy exists, install
exits 1 with a four-step recovery checklist. (Earlier behavior was a
silent skip with a warning that the user couldn't see at install time
— the result was an Emacs that loaded but where `(my/bootstrap)` was
guarded by a `(require 'async-tasks)` gate that returned nil. We
chased symptoms of that bug for several commits; section 6c's hard
fail makes it impossible to land that state again.)

The bootstrap orchestrator gates its auto-invocation on the same
`(require 'async-tasks nil 'noerror)`. If the gate fails at runtime,
init still completes (you get a usable Emacs), but a `*Warnings*`
buffer surfaces the missing-package message and the recovery path.

## Update flow

```bash
bash ~/emacs-mac-setup-src/install.sh
```

Pulls the latest distro on whichever branch you installed from
(persisted via `~/.emacs.d/distro-source.el`), refreshes
`async-tasks.el` from upstream, rsyncs `emacs.d/config/` to
`~/.emacs.d/config/`, copies init.el + early-init.el. Never touches
`~/.emacs.d/custom.el`, `secrets.el`, or your data folder.

## Branches

- `main` — current production tip; recommended for the curl one-liner
  unless you have a specific reason to pin
- `stable` — last tagged release; identical to whatever `main` was at
  the time of the most recent tag. Move with deliberate steps; safer
  for users who don't want rolling updates
- Tags — semver. `v1.x` is the pre-orchestrator distro-model design;
  `v2.0.0` introduced the orchestrator + Bitwarden + Keychain + setup
  form + async-tasks framework

Install from any non-`main` branch:

```bash
EMACS_MAC_BRANCH=branch-name /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/branch-name/install.sh)"
```

## Uninstall

```bash
bash ~/emacs-mac-setup-src/uninstall.sh
```

Removes the cloned distro source, the `~/.emacs.d/` directory (moved
to a timestamped backup), the Emacs Plus app bundle, and the brew
formula. Your data folder, Keychain entries, and Bitwarden vault are
left untouched. Add `--purge-data` to also delete your data folder,
or `--keep-emacs-app` to leave Emacs Plus.app + the brew formula
installed.

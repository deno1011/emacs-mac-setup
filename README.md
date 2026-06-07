# emacs-mac-setup

Opinionated preconfigured Emacs distribution for macOS.

One curl, one command, fully wired on first launch — installs
emacs-plus, drops a literate config into `~/.emacs.d/`, and seeds
`~/emacs/` with an example agenda, a populated LLM-wiki, and a guided
`TOUR.org` so a brand-new user can see the whole stack working without
having to build it themselves.

```bash
EMACS_MAC_BRANCH=refactor/modular-config /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/refactor/modular-config/install.sh)"
```

See [!STARTHERE.md](!STARTHERE.md) for the user-facing intro.

## Layout

```
emacs-mac-setup/
├── install.sh                  # the only thing the curl one-liner runs
├── uninstall.sh
├── !STARTHERE.md               # user-facing intro (GitHub landing page)
├── README.md                   # this file
│
├── emacs.d/                    # symlinked to ~/.emacs.d on install
│   ├── early-init.el           # GC tuning (runs before package.el)
│   ├── init.el                 # thin loader → config/config.org
│   ├── secrets.el.template     # copied to secrets.el on first install
│   ├── .gitignore              # ignores secrets.el, custom.el, elpa/, etc.
│   └── config/                 # literate config
│       ├── config.org          # entry — loads the split files
│       ├── core.org            # base Emacs, completion, version control
│       ├── org-setup.org       # org-mode, agenda, GTD, capture, LaTeX
│       ├── gptel-setup.org     # AI: Gemini/Anthropic/OpenAI/Groq/Ollama
│       ├── wiki-setup.org      # LLM-Wiki helpers (C-c n I/M/U/Q/L)
│       └── org-apple-reminders-setup.org
│
└── starter-data/               # seeded ONCE to ~/emacs/ on first install
    ├── TOUR.org                # auto-opens on first launch
    ├── wiki/                   # 5 sample pages, one per type
    │   ├── WIKI.org            # schema
    │   ├── index.org           # catalog with 5 entries
    │   ├── log.org             # timeline; starts with the scaffold entry
    │   ├── sources/welcome.org
    │   ├── entities/emacs.org
    │   ├── concepts/llm-wiki-pattern.org
    │   ├── comparisons/llm-wiki-vs-rag.org
    │   └── overviews/how-to-use-this-wiki.org
    └── org/                    # example GTD agenda
        ├── inbox.org refile.org calendar.org diary.org
        └── gtd/{next,projects,someday,waiting,tickler,reference}.org
```

## Three-layer model

Each layer has exactly one sync mechanism and one source of truth.
No layer reaches into another's responsibilities.

| Layer | Owned by | Sync | Update mechanism |
|---|---|---|---|
| Distro code (`emacs.d/`, `starter-data/`) | this repo | `install.sh` → git on user's side | `git pull` |
| User data (`~/emacs/`) | user | user's choice (iCloud / git / Syncthing / nothing) | user |
| Per-Mac secrets (`secrets.el`) | user, per machine | never synced | user |

What's deliberately NOT here:
- No Bitwarden integration, no master-password Keychain dance, no git-crypt
- No two-repo branch-protection workflow
- No `setup-intake.sh` / multi-phase wizard
- No `setup-emacs-mac.conf` template with 12 BW_* slots
- No automatic cross-Mac sync of user data (intentional — user picks the mechanism)

## Design principle

This is a *distribution*, not a *framework*. The goal isn't to let the
user customize everything; it's for a fresh user to see a working
agenda, a populated wiki, and a working gptel chat within 15 minutes of
typing one command. Customization happens by:

1. Editing your own `~/.emacs.d/secrets.el` (per-Mac config)
2. Editing the files in your own `~/emacs/` (your data)
3. Forking this repo if you want to change the distro itself

The distro code itself is symlinked and treated as read-only from the
user's side.

## Update flow

```bash
bash ~/emacs-mac-setup-src/install.sh
```

- Pulls latest distro on whichever branch you checked out
- Re-runs the symlink check (no-op if already correct)
- Never touches `~/emacs/` or `secrets.el`

## Branches

- `main` — current production tip
- `sketch/distro-model` — this branch, the rewrite proposal

Install from a non-`main` branch:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/deno1011/emacs-mac-setup/sketch/distro-model/install.sh \
  | EMACS_MAC_BRANCH=sketch/distro-model /bin/bash
```

## Uninstall

```bash
bash ~/emacs-mac-setup-src/uninstall.sh
```

Removes the symlink, cloned distro source, Emacs Plus app bundles/registrations,
and the `emacs-plus` formula. Leaves `~/emacs/` untouched. Add
`--purge-data` to also delete `~/emacs/`, or `--keep-emacs-app` to leave
Emacs Plus.app and the brew formula installed.

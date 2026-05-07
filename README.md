Emacs Mac Setup
===============

Automated Emacs setup for macOS. Three installation variants share a common
configuration stored on GitHub. Org files are kept in sync with the beorg
app on iPhone via iCloud.


QUICK START
-----------

Before you begin — have these ready:

  [ ] Homebrew installed                https://brew.sh
  [ ] GitHub account + personal token  Settings > Developer settings >
                                        Personal access tokens > Classic > "repo"
  [ ] Bitwarden account with vault entries:
        github-cli-token      custom field    "Key" = GitHub token (from above)
        emacs-git-crypt-key   custom field    "Key" = base64 git-crypt key  (required if org/ files are encrypted)
        anthropic-api-key     custom field    "Key" = Anthropic API key     (optional, only for gptel)
        → setup-bitwarden.sh creates these for you interactively
  [ ] GitHub repo named "emacs-config" (can be empty)
  [ ] iCloud Drive enabled (native variants only)

Setup — run in Terminal:

  # 1. Download all scripts (also pulls personal config automatically if accessible)
  bash <(curl -fsSL https://raw.githubusercontent.com/YOUR-GH-USER/emacs-mac-setup/main/bootstrap.sh)

  # 2. Only needed if GitHub was not yet authenticated during bootstrap:
  bash ~/fill-config.sh              # interactive guided config fill
  # or manually:
  open ~/setup-emacs-mac.conf        # set GIT_NAME, GIT_EMAIL, GH_USER, GH_REPO

  # 3. Install — pick one variant
  bash ~/setup-emacs-native-plus-mac.sh       # recommended: native comp, fast LSP (~15 min)
  bash ~/setup-emacs-native-yamamoto-mac.sh   # smooth scrolling, trackpad gestures (~20 min)
  bash ~/setup-emacs-docker-mac.sh            # isolated in Docker

  # 4. Start Emacs
  open "/Applications/Emacs (emacs-plus).app"
  open "/Applications/Emacs (Yamamoto).app"


GITHUB REPOS
------------

Two repos are used:

  emacs-mac-setup  (public)
    All setup, uninstall, and utility scripts. This repo.
    Also contains: init.el, config.org, setup-emacs-mac.conf.template

  mac-setup-conf  (private)
    Contains only setup-emacs-mac.conf with personal details.
    Pulled automatically by bootstrap.sh and setup scripts when accessible.
    No encryption needed — the file contains no actual secrets, only
    Bitwarden item names and GitHub username.

  emacs-config  (private)
    Emacs configuration: config.org, org/ files (org/ encrypted with git-crypt).
    Cloned to iCloud Drive on setup. Synced to iPhone via beorg.


SCRIPTS (all belong in ~/)
---------------------------

  setup-emacs-mac.conf                  Personal config — pulled from private repo
  setup-emacs-mac.conf.template         Fallback template if private repo not accessible
  init.el                               Emacs entry point — copied to ~/.emacs.d/init.el
  config.org                            Default Emacs config — used when emacs-config repo is empty

  setup-emacs-native-plus-mac.sh        Install emacs-plus@30 (native comp, LSP)
  setup-emacs-native-yamamoto-mac.sh    Install emacs-mac@30exp (Yamamoto patches)
  setup-emacs-docker-mac.sh            Install Emacs in a Docker container

  fill-config.sh                        Interactive guided config fill (prompts for each value)
  setup-bitwarden.sh                    Install Bitwarden + CLI, create required vault entries
  setup-secrets.sh                      (Re-)write ~/.emacs.d/secrets.el from Bitwarden

  uninstall-emacs-native-plus-mac.sh    Remove emacs-plus
  uninstall-emacs-native-yamamoto-mac.sh  Remove emacs-mac@30exp
  uninstall-emacs-docker-mac.sh         Remove Docker variant

  unlock-git-crypt.sh                   Decrypt org files in the iCloud repo
  remove-bitwarden-keychain.sh          Delete Bitwarden master password from Keychain


PREREQUISITES
-------------

System:
  - macOS 13 Ventura or newer
  - Homebrew installed (https://brew.sh)
  - iCloud Drive enabled (native variants store the repo in iCloud)
  - XQuartz (Docker GUI only — installed automatically)

Accounts:
  - GitHub account with a personal access token (Classic, "repo" scope)
  - Bitwarden account

Bitwarden entries required before running setup:

  github-cli-token      custom field    "Key" = GitHub personal access token
  emacs-git-crypt-key   custom field    "Key" = base64-encoded git-crypt key
                        (required if org/ files are encrypted, not needed for fresh repos)
  anthropic-api-key     custom field    "Key" = Anthropic API key (optional, for gptel)

Required config fields (setup aborts with a clear error if these are empty
and GH_USER is set):  GIT_NAME  GIT_EMAIL  GH_REPO


PERSONAL CONFIG (setup-emacs-mac.conf)
---------------------------------------

Contains: name, email, GitHub username, Bitwarden item names, Docker names.
Does NOT contain: passwords, API keys, or encryption keys — those stay in Bitwarden.
Therefore: safe to store in a private GitHub repo without encryption.

On a new Mac, bootstrap.sh handles the config automatically:

  GitHub already authenticated (e.g. second Mac):
    bootstrap.sh pulls setup-emacs-mac.conf from private repo → ready immediately

  Brand new Mac (no credentials yet):
    bootstrap.sh copies the template to ~/setup-emacs-mac.conf
    Fill in GIT_NAME, GIT_EMAIL, GH_USER, GH_REPO, then run setup
    After GitHub auth is established, setup re-pulls the latest conf from the private repo

CONF_REPO in the conf file points to the private repo — repo name only, e.g. mac-setup-conf
(GH_USER is prepended automatically). Leave it empty to disable auto-pull.


EMACS VARIANTS
--------------

1. emacs-plus  (recommended for developers)

   - Emacs 30.2 with native compilation
   - Packages compiled to native machine code — significantly faster LSP
   - Native macOS fullscreen (new Space when clicking the green button)
   - Install time: ~15-20 minutes (compilation)

     bash ~/setup-emacs-native-plus-mac.sh

   Starts as:  /Applications/Emacs (emacs-plus).app


2. emacs-mac — Yamamoto  (smooth rendering)

   - Emacs 30 (snapshot emacs-30-20260504) with Yamamoto patches
   - Pixel-perfect scrolling, better Retina rendering, native trackpad gestures
   - Install time: ~15-25 minutes (compilation)

     bash ~/setup-emacs-native-yamamoto-mac.sh

   Starts as:  /Applications/Emacs (Yamamoto).app


3. Docker  (isolated)

   - Emacs runs in a Docker container, config pulled from GitHub on start
   - Only the beorg iCloud folder is mounted — no Mac filesystem exposure
   - Install time: depends on image build and package download

     bash ~/setup-emacs-docker-mac.sh

   App icons in ~/Applications/:
     Emacs Docker GUI.app          graphical Emacs via XQuartz
     Emacs Docker Console.app      Emacs in terminal (-nw)
     Emacs Docker Shell.app        shell inside the container
     Emacs Docker Root Shell.app   root shell inside the container


STARTING EMACS
--------------

Native (Plus / Yamamoto):

  open "/Applications/Emacs (emacs-plus).app"
  open "/Applications/Emacs (Yamamoto).app"

  or via Spotlight: type "Emacs" and select the desired variant

  Terminal (TUI mode):
  emacs -nw

Docker:

  Double-click one of the app icons in ~/Applications/, or use Spotlight.


WHAT NOT TO DO
--------------

Two native Emacs instances at the same time:
  emacs-plus and emacs-mac@30exp share ~/.emacs.d/ and ~/emacs-config/.
  Running both simultaneously causes lock file collisions, session file
  conflicts, and git-auto-commit-mode writing to the same repo concurrently.
  Always run only one native instance at a time.

Native and Docker at the same time:
  Both use the same GitHub repo as their data source. Concurrent edits lead
  to git conflicts on the next sync.

"emacs" in the terminal while a GUI instance is running:
  The Homebrew wrapper starts a second instance with the same config.


BEORG SYNC
----------

iPhone sync architecture:

  GitHub (source of truth)
       |
       | git pull / push
       |
  Native Emacs              Docker Emacs
       |                         |
  post-commit hook         startup-sync.sh
       |                         |
  beorg iCloud folder  <---------+
       |
  iPhone (beorg app)

Native (Plus / Yamamoto):
  A git post-commit hook fires automatically after every commit:
    1. Syncs org/ to ~/Library/Mobile Documents/.../beorg/Documents/org/
    2. Pushes the commit to GitHub

  git-auto-commit-mode commits on every save in Emacs, so the hook fires
  immediately and beorg sees the change within seconds.

Docker:
  startup-sync.sh runs when the container starts:
    1. git clone if the repo is not yet in the container (always to ~/emacs-config/)
    2. git pull origin main
    3. rsync org/ -> /beorg/ (the mounted beorg iCloud folder)

  A post-commit hook inside the container repeats the rsync after each commit
  and pushes to GitHub. The beorg folder is the only bind-mount:

    Mac:       ~/Library/Mobile Documents/.../beorg/org/
    Container: /beorg/


DOCKER SPECIFICS
----------------

Architecture:
  - Docker volume "emacs-home": persistent Emacs packages (~/.emacs.d/)
    survive container restarts without living on the Mac
  - Config comes via git clone/pull to fixed path ~/emacs-config/, not as a bind-mount
  - Only one mount: the beorg folder for iPhone sync

Container management:
  docker ps                       check running containers
  docker start emacs-dev          start the container manually
  docker logs emacs-dev           view logs


PARALLEL INSTALLATION (Plus + Yamamoto)
----------------------------------------

Both variants can coexist in the Homebrew Cellar:
  - Each has its own app icon in /Applications/
  - Only one is active via the "emacs" command in the terminal
    (the most recently installed / linked one)
  - Each setup script automatically links its own version and unlinks the other

When uninstalling one variant while the other is still installed:
  - Shared resources (~/.emacs.d/, iCloud repo, packages) are preserved
  - The remaining variant is automatically linked as active


FRESH REPO (for friends / first-time setup)
--------------------------------------------

Starting with an empty emacs-config repo is fine:

  git clone succeeds on an empty repo                OK
  git-crypt unlock fails with a warning              OK (not an error)
  config.org missing -> copied from ~/config.org     OK (bundled with scripts)
  org/ folder missing -> beorg hook runs empty       OK (no crash)

config.org is included in this repo as a working starting point. On first clone,
if config.org is not yet in the emacs-config repo, it is copied there automatically.
The friend only needs their own GitHub account and a Bitwarden account — they do not
need your git-crypt key or access to your org files.


GITHUB MODE vs LOCAL MODE
--------------------------

GH_USER set in config:
  Full setup — Bitwarden auth, GitHub auth, iCloud clone, git-crypt unlock,
  post-commit hook, beorg sync. Config is synced to GitHub and iPhone.

GH_USER empty in config:
  Local mode — no Bitwarden, no GitHub, no iCloud.
  config.org is copied from ~/config.org to ~/emacs-config/.
  Emacs starts fully configured. No sync, no beorg. Good for offline or
  trial use. Add GH_USER later and re-run setup to enable full sync.


UNINSTALL
---------

  bash ~/uninstall-emacs-native-plus-mac.sh       remove emacs-plus
  bash ~/uninstall-emacs-native-yamamoto-mac.sh   remove emacs-mac@30exp
  bash ~/uninstall-emacs-docker-mac.sh            remove Docker variant

  bash ~/remove-bitwarden-keychain.sh             remove Bitwarden master
                                                  password from Keychain

The Bitwarden Keychain entry is treated as a shared resource and is NOT deleted
by any of the uninstall scripts. Remove it explicitly with the script above
after all variants have been uninstalled.


GIT-CRYPT
---------

The org/ files in the GitHub repo are encrypted with git-crypt. The key is
stored in Bitwarden (item: emacs-git-crypt-key, field: Key).

Manual unlock:
  bash ~/unlock-git-crypt.sh

The setup scripts unlock automatically on first clone.


THEME
-----

All variants use modus-vivendi — built into Emacs 28+, designed for high
contrast and readability (WCAG AAA standard).

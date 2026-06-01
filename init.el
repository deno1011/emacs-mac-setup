;; Entry point — loads config from ~/GH_REPO/config/config.org
;;
;; This file is intentionally minimal. Its only job is to:
;;   1. Set up package archives and use-package
;;   2. Locate the user's config directory (iCloud / local / first-install)
;;   3. Fetch config.org from emacs-mac-setup/stable on first install
;;   4. Hand off to config.org for everything else
;;
;; The setup-emacs-*.sh scripts only place this file. The rest of the
;; config (config.org, split files, wiki templates) self-bootstraps from
;; emacs-mac-setup/stable on first Emacs run via url-copy-file. After
;; each layer's first-install completes, a .bootstrap-completed marker
;; is dropped to lock further auto-fetching for that layer — the user
;; owns it from then on. See my/-bootstrap-marker-template below for
;; the full explanation that gets written into each marker file.

;; Suppress byte-compile warnings at startup
(setq warning-minimum-level :error)

;; Fullscreen without animation freeze
(setq ns-use-fullscreen-animation nil)

;; Package archives
(require 'package)
(setq package-archives '(("melpa"  . "https://melpa.org/packages/")
                         ("gnu"    . "https://elpa.gnu.org/packages/")
                         ("nongnu" . "https://elpa.nongnu.org/packages/")))
(package-initialize)

;; Bootstrap use-package
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;; Load secrets (API keys etc.) — not tracked in git
(load (expand-file-name "~/.emacs.d/secrets.el") t t)

;; Base theme — applied before config so config can override or build on top.
;; modus-vivendi is built into Emacs 28+ and requires no packages.
(load-theme 'modus-vivendi t)

;; Hardcoded by setup script at install time. Repo: emacs
;; Re-running setup with a different repo overwrites this file.
(defvar my/data-dir (expand-file-name "~/GH_REPO/")
  "Root of the personal data repo symlink.")

;; First-install fallback: fetch missing config files from the public
;; bootstrap repo (emacs-mac-setup/stable). The personal layer (iCloud
;; / ~/GH_REPO/) always takes priority; this is the bootstrap-of-last-
;; resort. The same URL pattern is reused by config.org for the split
;; files and by wiki-setup.org / org-setup.org for templates.
(defvar my/config-bootstrap-url
  "https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/"
  "Base URL for fetching config files on first install.")

;; Locate config directory: prefer the live iCloud / personal repo,
;; then the read-only local fallback, then default to the iCloud-style
;; path so the bootstrap can populate it on first run.
(defvar my/config-dir
  (let ((primary  (expand-file-name "config/" my/data-dir))
        (fallback (expand-file-name "~/.emacs.d/config-readonly/")))
    (cond
     ((file-directory-p primary)  primary)
     ((file-directory-p fallback) fallback)
     (t primary)))
  "Directory containing the Emacs config org files.")

;; --- Bootstrap markers ------------------------------------------------
;;
;; Each layer (config / wiki / gtd) drops a `.bootstrap-completed' file
;; after its first-install fetch succeeds. While the marker exists,
;; that layer's bootstrap does nothing — the user is presumed to own
;; the content (renames, deletions, edits are all respected).
;;
;; Markers live INSIDE the user's iCloud-synced ~/GH_REPO/ tree so they
;; travel with the repo across Macs. See the marker text below for the
;; full explanation that gets written into each file.

(defvar my/-bootstrap-marker-template
  "Bootstrap-completion sentinel for Emacs setup at ~/GH_REPO/.

Layer:         %s
Created:       %s
Public source: https://github.com/deno1011/emacs-mac-setup (branch: stable)
Public raw:    https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/


================================================================
Why this file is here
================================================================

The Emacs config has a three-layer self-bootstrap. On first install,
each layer fetches its starter files from the PUBLIC mac-setup repo
above. After a layer's first-install completes successfully, this
marker is created. Subsequent Emacs runs see the marker and skip
auto-fetching for this layer entirely — the user owns it from then on.


================================================================
What the marker protects
================================================================

  Edits to existing files  → always safe (file already exists →
                              never fetched whether marker is here
                              or not)
  Renames                  → without marker, original filename would
                              be re-fetched, creating a duplicate
                              next to your renamed version. With
                              marker, no fetch — your rename stands.
  Deletions                → without marker, a deleted file would be
                              restored on next start. With marker,
                              the deletion is respected.
  Content additions        → never touched

Once this marker is present, your customizations are fully owned by
you. The bootstrap will not silently undo them.


================================================================
Three layers, three independent markers
================================================================

  ~/GH_REPO/config/.bootstrap-completed       init.el + config.org
                                            governs the config split
                                            files (core, org-setup,
                                            gptel-setup, wiki-setup,
                                            org-apple-reminders-setup)

  ~/GH_REPO/wiki/emacs/.bootstrap-completed   wiki-setup.org
                                            governs WIKI.org schema,
                                            index.org, log.org. Wiki
                                            page CONTENT is never auto-
                                            fetched, only the schema.

  ~/GH_REPO/data/org/.bootstrap-completed     org-setup.org GTD bootstrap
                                            governs inbox/calendar/
                                            refile/diary plus gtd/
                                            {projects,next,waiting,
                                            tickler,someday,reference}.org

Each layer is independent. Removing one marker re-enables auto-fetch
for that layer only.


================================================================
Repo layout
================================================================

PUBLIC repo (read by the elisp bootstrap, no authentication required):

  github.com/deno1011/emacs-mac-setup, branch `stable`
  https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/

  Contains:
    init.el                      the entry point
    config.org                   loader for the split files
    core.org / org-setup.org / gptel-setup.org / wiki-setup.org /
    org-apple-reminders-setup.org    the split config files
    wiki-templates/              WIKI.org, index.org, log.org seeds
    gtd-templates/               inbox.org, calendar.org, gtd/*.org seeds
    setup-emacs-*.sh             platform installer scripts
    bootstrap.sh                 top-level installer

PRIVATE repo (your personal data, iCloud-synced, NEVER fetched by elisp):

  github.com/<your-github-user>/emacs   (e.g., deno1011/emacs)

  Authenticated git access only. Contains the iCloud-synced ~/GH_REPO/
  tree on disk:
    config/                      your customizations of the config files
    data/org/                    your GTD files, journal, personal notes
    wiki/                        your wiki content (ingested pages,
                                 plans, notes)
    notes/, etc.

The elisp bootstrap reads ONLY:
  1. Your local filesystem (which iCloud syncs from the private repo)
  2. The PUBLIC mac-setup raw URLs over HTTPS

It does not authenticate to git or to any private repo.


================================================================
iCloud sync — why this marker travels with the repo
================================================================

~/GH_REPO/ is symlinked to:
  ~/Library/Mobile Documents/com~apple~CloudDocs/GH_REPO/

iCloud Drive syncs that folder to all your Macs (and read-only to
iOS via the Files app). This marker file lives inside that synced
area, so it travels automatically across all your devices:

  1. First Mac: bootstrap runs → marker created → iCloud syncs it
     into the cloud and to your other devices.
  2. Second Mac: open Emacs → iCloud has already delivered the
     marker → bootstrap is skipped → uses your personal config
     directly.
  3. Customize on either Mac → no fetch needed → no overwrites
     possible.

Race-condition warning: if you open Emacs on a FRESH Mac BEFORE
iCloud has finished the initial sync of ~/GH_REPO/, this marker may
not have arrived yet. The bootstrap would then treat the layer as
first-install, fetch public files, and iCloud would later arrive
with your personal files — creating conflict copies that you'd
need to resolve manually. To avoid: wait until Finder's iCloud
status indicator shows the folder fully synced (green checkmark)
before launching Emacs.


================================================================
How to reset bootstrap on this layer
================================================================

  rm <this file>

That is the entire reset procedure. On the next Emacs start:
  - The layer is treated as first-install again
  - Each expected file is checked for existence
  - Missing files are re-fetched from public mac-setup/stable
  - Existing files are left alone (the bootstrap never overwrites)
  - A new marker is created at the end


================================================================
What is NEVER auto-fetched (even without the marker)
================================================================

  - Your wiki PAGE content (entities, concepts, sources, comparisons,
    overviews). Only the schema files (WIKI.org / index.org / log.org)
    are templates that get auto-fetched on first install.
  - Your GTD TASK content. Only the file STRUCTURE is seeded on
    first install (with FILETAGS headers); content stays empty.
  - Any custom files you've added beyond the original split files.

The bootstrap creates files only by exact NAME match against a fixed
list. New files you add and content you write inside any file are
fully yours.


================================================================
References
================================================================

  Bootstrap entry point:   ~/.emacs.d/init.el
  Per-layer source:        ~/GH_REPO/config/config.org
                           ~/GH_REPO/config/wiki-setup.org
                           ~/GH_REPO/config/org-setup.org
  Public bootstrap repo:   github.com/deno1011/emacs-mac-setup
  Setup scripts:           bootstrap.sh + setup-emacs-*.sh
"
  "Template for the .bootstrap-completed marker files. Two %s
placeholders: the layer name and the creation timestamp.")

(defun my/-bootstrap-write-marker (dir layer)
  "Write a bootstrap-completion marker file in DIR identifying LAYER.
File is named `.bootstrap-completed' and contains the verbose
explanation in `my/-bootstrap-marker-template'. No-op if the marker
already exists or DIR is not a directory."
  (let ((path (expand-file-name ".bootstrap-completed" dir)))
    (when (and (file-directory-p dir)
               (not (file-exists-p path)))
      (with-temp-file path
        (insert (format my/-bootstrap-marker-template
                        layer
                        (format-time-string "%Y-%m-%dT%H:%M:%S")))))))

(defvar my/-config-bootstrap-marker
  (expand-file-name ".bootstrap-completed" my/config-dir)
  "Marker file. Once present, the config layer's auto-fetch is locked.")

(defun my/ensure-config-file-from-url (filename)
  "If FILENAME is missing from `my/config-dir' AND the layer's bootstrap
marker is absent, fetch from `my/config-bootstrap-url'. Returns the
absolute path. Once `my/-config-bootstrap-marker' exists, this is a
no-op for everything — the user owns the layer."
  (let ((path (expand-file-name filename my/config-dir)))
    (when (and (not (file-exists-p path))
               (not (file-exists-p my/-config-bootstrap-marker)))
      (unless (file-directory-p my/config-dir)
        (make-directory my/config-dir t))
      (message "Bootstrap: fetching %s from emacs-mac-setup/stable..." filename)
      (condition-case err
          (progn
            (require 'url)
            (url-copy-file (concat my/config-bootstrap-url filename) path t))
        (error (message "Bootstrap: failed to fetch %s: %s"
                        filename (error-message-string err)))))
    path))

(add-hook 'after-init-hook
          (lambda ()
            (let* ((org-dir   (expand-file-name "data/org/" my/data-dir))
                   (first-org (car (and (file-directory-p org-dir)
                                        (directory-files org-dir t "\\.org$")))))
              (when (and first-org
                         (with-temp-buffer
                           (insert-file-contents-literally first-org nil 0 10)
                           (string-match-p "\x00" (buffer-string))))
                (display-warning
                 'emacs-setup
                 (format "Org files appear encrypted (git-crypt not unlocked).\nRun: bash ~/unlock-git-crypt.sh")
                 :warning)))))

;; Load config — fetch config.org first if missing, then hand off.
;; config.org bootstraps and loads the split files via the same URL
;; pattern; wiki-setup.org / org-setup.org bootstrap their layers
;; the same way. On success of the whole config load, drop the
;; config-layer marker.
(let ((path (my/ensure-config-file-from-url "config.org")))
  (if (file-exists-p path)
      (progn
        (condition-case err
            (org-babel-load-file path)
          (error (message "CONFIG LOAD ERROR: %s" err)))
        (my/-bootstrap-write-marker my/config-dir "config"))
    (message "CONFIG BOOTSTRAP FAILED — could not load or fetch config.org")))

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))

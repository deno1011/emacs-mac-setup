;;; init.el --- Emacs-for-Mac distro entry point  -*- lexical-binding: t; -*-
;;
;; Thin loader. Responsibilities, in order:
;;
;;   1. Set my/data-dir (root of the user's PRIVATE data + config; the
;;      EMACS_DATA_DIR env var overrides; default ~/emacs/).
;;   2. Set my/config-dir = my/data-dir/config/ (where the LITERATE
;;      config lives — including bootstrap.org).
;;   3. If `<my/config-dir>/.bootstrap-completed' is ABSENT (first launch
;;      on this Mac), seed `my/config-dir' with the canonical .org files
;;      from the distro: prefer the local clone at $EMACS_MAC_SRC_DIR/
;;      seed-config/<file>, fall back to a URL fetch from the public
;;      distro on the configured branch.
;;   4. Package archives + use-package.
;;   5. Load secrets.el (per-Mac; lives in ~/.emacs.d/).
;;   6. Load `<my/config-dir>/config.org' — which loads bootstrap.org as
;;      the first split file (BW unlock, gh, repo clone, ...).
;;
;; The .bootstrap-completed marker is dropped by bootstrap.org once it
;; completes the first-run flow. After that, init.el's seeding step is
;; a no-op — the user owns my/config-dir and edits files freely; they
;; sync across Macs via git in the private repo.
;;
;; Init-phase GC tuning is in early-init.el (Emacs 27+).

;; 1. my/data-dir + my/config-dir ------------------------------------------
(defvar my/data-dir
  (expand-file-name
   (file-name-as-directory
    (or (getenv "EMACS_DATA_DIR") "~/emacs/")))
  "Root directory for the user's personal data + literate config.
Override per-Mac with EMACS_DATA_DIR (and `launchctl setenv' for GUI
Emacs).")

(defvar my/config-dir
  (expand-file-name "config/" my/data-dir)
  "Directory containing the literate config (config.org, bootstrap.org,
core.org, ...). Lives INSIDE the user's private repo so edits sync
across Macs via git.")

(add-to-list 'load-path my/config-dir)

;; 2. Seed my/config-dir if not yet bootstrapped --------------------------
(defvar my/seed-files
  '("bootstrap.org" "config.org" "core.org" "org-setup.org"
    "gptel-setup.org" "wiki-setup.org" "org-apple-reminders-setup.org")
  "Files to seed into my/config-dir on first launch from the public
distro. Order doesn't matter — config.org's split-files list decides
load order.")

(defvar my/distro-src-dir
  (or (getenv "EMACS_MAC_SRC_DIR")
      (expand-file-name "~/emacs-mac-setup-src/"))
  "Local checkout of the public distro. Used as the preferred source
for seed files (offline-safe, no network).")

(defvar my/distro-seed-branch
  (or (getenv "EMACS_MAC_BRANCH") "main")
  "Branch on github.com/deno1011/emacs-mac-setup to fetch seed files
from when the local distro checkout isn't present.")

(defvar my/distro-seed-url-base
  (format "https://raw.githubusercontent.com/deno1011/emacs-mac-setup/%s/seed-config/"
          my/distro-seed-branch)
  "URL base for fetching seed-config files when no local copy exists.")

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))

(defvar my/-bootstrap-completed-marker
  (expand-file-name ".bootstrap-completed" my/config-dir)
  "Sentinel file. While ABSENT, init.el seeds missing config files
from the distro. bootstrap.org drops it on first successful run; from
then on this layer is the user's. Delete it manually to re-trigger a
distro re-seed on next launch (existing files preserved — only missing
ones are fetched).")

(defun my/-seed-fetch (filename)
  "Place FILENAME into my/config-dir. Prefer local distro checkout,
fall back to URL. No-op if the destination already exists."
  (let ((dest (expand-file-name filename my/config-dir))
        (local (expand-file-name (concat "seed-config/" filename) my/distro-src-dir)))
    (unless (file-exists-p dest)
      (cond
       ((file-readable-p local)
        (make-directory my/config-dir t)
        (copy-file local dest)
        (message "Seed: copied %s from local distro." filename))
       (t
        (make-directory my/config-dir t)
        (condition-case err
            (progn
              (require 'url)
              (url-copy-file (concat my/distro-seed-url-base filename) dest t)
              (message "Seed: fetched %s from %s." filename my/distro-seed-url-base))
          (error
           (message "Seed: could NOT fetch %s — %s.
You'll need to either populate %s manually or `cd %s && git pull`."
                    filename (error-message-string err)
                    dest my/distro-src-dir))))))))

(unless (file-exists-p my/-bootstrap-completed-marker)
  (message "init: %s absent — seeding missing config files from %s."
           my/-bootstrap-completed-marker
           (if (file-directory-p (expand-file-name "seed-config" my/distro-src-dir))
               "local distro"
             my/distro-seed-url-base))
  (dolist (f my/seed-files) (my/-seed-fetch f)))

;; 3. Package archives + use-package --------------------------------------
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(package-initialize)
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;; 4. Secrets — per-Mac, never tracked in git ------------------------------
(let ((secrets (expand-file-name "secrets.el" user-emacs-directory)))
  (when (file-exists-p secrets)
    (load secrets nil 'nomessage)))

;; 5. Literate config -------------------------------------------------------
(let ((config-org (expand-file-name "config.org" my/config-dir)))
  (cond
   ((file-exists-p config-org)
    (require 'org)
    (org-babel-load-file config-org))
   (t
    (display-warning
     'emacs-setup
     (format "config.org missing at %s after seeding — distro install incomplete.
Try: `bash ~/emacs-mac-setup-src/install.sh` then restart Emacs."
             config-org)
     :error))))

;; 6. custom.el (so customize doesn't pollute init.el) ---------------------
(when (file-exists-p custom-file) (load custom-file))

(provide 'init)
;;; init.el ends here

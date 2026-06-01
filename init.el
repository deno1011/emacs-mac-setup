;; Entry point — loads config from ~/emacs/config/config.org
;;
;; This file is intentionally minimal. Its only job is to:
;;   1. Set up package archives and use-package
;;   2. Locate the user's config directory (iCloud / local / first-install)
;;   3. Fetch config.org from emacs-mac-setup/stable on first install
;;   4. Hand off to config.org for everything else
;;
;; The setup-emacs-*.sh scripts only place this file. The rest of the
;; config (config.org, split files, wiki templates) self-bootstraps from
;; emacs-mac-setup/stable on first Emacs run via url-copy-file.

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
(defvar my/data-dir (expand-file-name "~/emacs/")
  "Root of the personal data repo symlink.")

;; First-install fallback: fetch missing config files from the public
;; bootstrap repo (emacs-mac-setup/stable). The personal layer (iCloud
;; / ~/emacs/) always takes priority; this is the bootstrap-of-last-
;; resort. The same URL pattern is reused by config.org for the split
;; files and by wiki-setup.org for the wiki schema templates.
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

(defun my/ensure-config-file-from-url (filename)
  "If FILENAME is missing from `my/config-dir', fetch it from
`my/config-bootstrap-url'. Returns the absolute path. Creates the
config directory if necessary. Silently no-ops if the fetch fails;
the caller is expected to check `file-exists-p' on the return."
  (let ((path (expand-file-name filename my/config-dir)))
    (unless (file-exists-p path)
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
;; pattern; wiki-setup.org bootstraps the wiki templates the same way.
(let ((path (my/ensure-config-file-from-url "config.org")))
  (if (file-exists-p path)
      (condition-case err
          (org-babel-load-file path)
        (error (message "CONFIG LOAD ERROR: %s" err)))
    (message "CONFIG BOOTSTRAP FAILED — could not load or fetch config.org")))

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))

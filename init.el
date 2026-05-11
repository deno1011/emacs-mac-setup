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

;; Locate config.org: prefer the fixed symlink (native setup always creates
;; ~/emacs-config → iCloud repo), fall back to ~/GH_REPO (Docker, custom name)
(defvar my/config-org-path
  (let ((symlink (expand-file-name "~/emacs-config/config.org"))
        (from-env (when (getenv "GH_REPO")
                    (expand-file-name (concat "~/" (getenv "GH_REPO") "/config.org")))))
    (cond
     ((file-exists-p symlink)   symlink)
     ((and from-env (file-exists-p from-env)) from-env)
     (t nil)))
  "Resolved path to config.org, or nil if not found.")

;; Load full config from org file
(if my/config-org-path
    (condition-case err
        (org-babel-load-file my/config-org-path)
      (error (message "CONFIG LOAD ERROR: %s" err)))
  (message "CONFIG NOT FOUND: ~/emacs-config/config.org not found and GH_REPO env var not set"))

;; Force theme regardless of config errors
(add-hook 'after-init-hook
          (lambda ()
            (load-theme 'modus-vivendi t)
            ;; Warn if org files look encrypted (git-crypt not unlocked)
            (let* ((repo-dir (or (and my/config-org-path
                                      (file-name-directory my/config-org-path))
                                 (expand-file-name "~/emacs-config/")))
                   (org-dir (expand-file-name "org/" repo-dir))
                   (first-org (car (and (file-directory-p org-dir)
                                        (directory-files org-dir t "\\.org$")))))
              (when (and first-org
                         (with-temp-buffer
                           (insert-file-contents-literally first-org nil 0 10)
                           (string-match-p "\x00" (buffer-string))))
                (display-warning
                 'emacs-setup
                 "Org files appear encrypted (git-crypt not unlocked).\nRun: bash ~/unlock-git-crypt.sh"
                 :warning)))))

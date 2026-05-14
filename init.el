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

;; Locate config directory: prefer the fixed symlink (native setup always creates
;; ~/emacs-config → iCloud repo), fall back to ~/GH_REPO for Docker/OrbStack installs
;; where GH_REPO is injected as an environment variable by the setup script
;; (docker run -e GH_REPO=... / OrbStack VM shell profile).
(defvar my/config-dir
  (let ((symlink  (expand-file-name "~/emacs-config/"))
        (from-env (when (getenv "GH_REPO")
                    (expand-file-name (concat "~/" (getenv "GH_REPO") "/")))))
    (cond
     ((file-directory-p symlink)                 symlink)
     ((and from-env (file-directory-p from-env)) from-env)
     (t nil)))
  "Directory containing the Emacs config org files.")

;; Warn after init if org files look encrypted (git-crypt not unlocked).
(add-hook 'after-init-hook
          (lambda ()
            (let* ((repo-dir (or my/config-dir
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

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

;; Load config last — config.org bootstraps and loads the split files.
(if my/config-dir
    (let ((path (expand-file-name "config.org" my/config-dir)))
      (if (file-exists-p path)
          (condition-case err
              (org-babel-load-file path)
            (error (message "CONFIG LOAD ERROR: %s" err)))
        (message "CONFIG NOT FOUND: %s" path)))
  (message "CONFIG DIR NOT FOUND: ~/emacs-config/ not found and GH_REPO env var not set"))

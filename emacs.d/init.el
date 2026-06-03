;;; init.el --- Emacs-for-Mac distro entry point  -*- lexical-binding: t; -*-
;;
;; This file is a thin loader. The real config is the literate
;; org-babel file at config/config.org (which in turn loads the
;; split files: core, org-setup, gptel-setup, wiki-setup, ...).
;;
;; Owned by the distro at https://github.com/deno1011/emacs-mac-setup
;; — your ~/.emacs.d is a symlink to the distro's emacs.d/ directory.
;; To customize without editing distro files, put your overrides in
;; secrets.el (next to this file). To roll the distro back or forward,
;; `git -C ~/emacs-mac-setup-src pull` (or use install.sh).
;;
;; Init-phase GC tuning is in early-init.el (Emacs 27+).

;; Personal data root. The distro never writes here after first install.
;; If you symlink ~/emacs to iCloud Drive / Syncthing / a private git
;; repo, cross-Mac sync is your concern, not the distro's.
(defvar my/data-dir (expand-file-name "~/emacs/")
  "Root directory for the user's personal data (org files, wiki, notes).")

(defvar my/config-dir (expand-file-name "config/" user-emacs-directory)
  "Directory containing the literate config (config.org, core.org, ...).")

;; Make literate config files reachable from `load-path' / `org-babel'.
(add-to-list 'load-path my/config-dir)

;; Package archives + use-package
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

;; Secrets — load if present. Per-Mac, never tracked in git.
(let ((secrets (expand-file-name "secrets.el" user-emacs-directory)))
  (when (file-exists-p secrets)
    (load secrets nil 'nomessage)))

;; Literate config
(let ((config-org (expand-file-name "config.org" my/config-dir)))
  (when (file-exists-p config-org)
    (require 'org)
    (org-babel-load-file config-org)))

;; First-install tour: open TOUR.org once, then remove the marker.
(let ((marker (expand-file-name ".first-install" user-emacs-directory))
      (tour   (expand-file-name "TOUR.org" my/data-dir)))
  (when (and (file-exists-p marker) (file-exists-p tour))
    (add-hook 'emacs-startup-hook
              (lambda ()
                (find-file tour)
                (delete-file marker)))))

;; custom.el lives next to this file (so customize doesn't pollute init.el)
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))

(provide 'init)
;;; init.el ends here

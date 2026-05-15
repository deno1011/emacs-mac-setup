;; Entry point → ~/emacs-data/config/config.org

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

;; Locate config directory: prefer ~/emacs-data/config/ (iCloud repo, config subfolder).
;; Falls back to ~/.emacs.d/config-readonly/ (local copy kept by startup-sync).
(defvar my/config-dir
  (let ((primary  (expand-file-name "~/emacs-data/config/"))
        (fallback (expand-file-name "~/.emacs.d/config-readonly/")))
    (cond
     ((file-directory-p primary)  primary)
     ((file-directory-p fallback) fallback)
     (t nil)))
  "Directory containing the Emacs config org files.")

(add-hook 'after-init-hook
          (lambda ()
            (let* ((org-dir  (expand-file-name "~/emacs-data/data/org/"))
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
  (message "CONFIG DIR NOT FOUND: ~/emacs-data/config/ not found and ~/.emacs.d/config-readonly/ not found"))

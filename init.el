;; Entry point — loads config from ~/GH_REPO/config/config.org

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

;; Read GH_REPO from ~/setup-emacs-mac.conf to locate the data repo.
;; Falls back to "emacs-data" if conf is missing or GH_REPO is unset.
(defvar my/data-dir
  (let* ((conf (expand-file-name "~/setup-emacs-mac.conf"))
         (repo (when (file-exists-p conf)
                 (with-temp-buffer
                   (insert-file-contents conf)
                   (goto-char (point-min))
                   (when (re-search-forward "^GH_REPO=[\"']?\\([^\"'\n]+\\)[\"']?" nil t)
                     (string-trim (match-string 1)))))))
    (expand-file-name (concat "~/" (or repo "emacs-data") "/")))
  "Root of the personal data repo symlink (e.g. ~/emacs-data/).")

;; Locate config directory: prefer live iCloud repo, fall back to local copy.
(defvar my/config-dir
  (let ((primary  (expand-file-name "config/" my/data-dir))
        (fallback (expand-file-name "~/.emacs.d/config-readonly/")))
    (cond
     ((file-directory-p primary)  primary)
     ((file-directory-p fallback) fallback)
     (t nil)))
  "Directory containing the Emacs config org files.")

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

;; Load config last — config.org bootstraps and loads the split files.
(if my/config-dir
    (let ((path (expand-file-name "config.org" my/config-dir)))
      (if (file-exists-p path)
          (condition-case err
              (org-babel-load-file path)
            (error (message "CONFIG LOAD ERROR: %s" err)))
        (message "CONFIG NOT FOUND: %s" path)))
  (message "CONFIG DIR NOT FOUND: %s not found and ~/.emacs.d/config-readonly/ not found"
           (expand-file-name "config/" my/data-dir)))

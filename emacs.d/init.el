;;; init.el --- Emacs-for-Mac distro entry point  -*- lexical-binding: t; -*-
;;
;; Thin loader. Knows only:
;;
;;   - WHERE the user's data lives (`my/data-dir', overridable via
;;     EMACS_DATA_DIR or generated data-dir.el; default ~/emacs/).
;;   - WHERE the literate config lives (`my/private-config-dir' =
;;     <my/data-dir>/config/).
;;   - The ENTRY POINT FILENAME inside that directory (`config.org', or a
;;     pre-tangled `config.el' if present).
;;   - A distro seed config fallback, used only when the selected private
;;     repo folder is missing so bootstrap can clone/restore it.
;;
;; Nothing else. No module list, no seeding logic, no per-feature flags.
;; install.sh places the seed config files into my/config-dir on first
;; install. config.org discovers and loads modules. Each layer below this
;; one is responsible for its own contents; init.el does not know what's
;; in them.
;;
;; Init-phase GC tuning lives in early-init.el (Emacs 27+).

;; 1. Where data and config live ------------------------------------------
(let ((generated-data-dir (expand-file-name "data-dir.el" user-emacs-directory)))
  (when (file-exists-p generated-data-dir)
    (load generated-data-dir nil 'nomessage)))

(when (getenv "EMACS_DATA_DIR")
  (setq my/data-dir
        (expand-file-name
         (file-name-as-directory (getenv "EMACS_DATA_DIR")))))

(defvar my/data-dir
  (expand-file-name
   (file-name-as-directory
    (or (getenv "EMACS_DATA_DIR") "~/emacs/")))
  "Root directory for the user's personal data + literate config.
Override per-Mac with EMACS_DATA_DIR, or let bootstrap generate
data-dir.el from the selected private repo name.")

(defvar my/private-config-dir
  (expand-file-name "config/" my/data-dir)
  "Directory containing the literate config. Lives INSIDE the user's
private repo so edits sync across Macs via git.")

(defvar my/seed-config-dir
  (expand-file-name
   "seed-config/"
   (or (getenv "EMACS_MAC_SRC_DIR")
       (expand-file-name "~/emacs-mac-setup-src/")))
  "Distro seed config used only as a rescue loader for bootstrap.")

(defvar my/config-dir my/private-config-dir
  "Config directory loaded for this startup.
Normally this is `my/private-config-dir'. If the selected private repo
folder is missing locally, this temporarily points at
`my/seed-config-dir' so bootstrap can clone/restore the GitHub repo into
`my/data-dir'.")

(add-to-list 'load-path my/config-dir)

;; 2. Package archives + use-package --------------------------------------
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

;; Self-heal: if `package-install' fails with "Package not found in any
;; archive" (because elpa/archives/ is missing or stale — typical after
;; restoring ~/.emacs.d/ from a partial backup, or after the symlink
;; collapse we fixed in install.sh), refresh archives ONCE per session
;; and retry. Without this, every `:ensure t' on a not-yet-cached
;; package would error out and load the rest of the literate config
;; with broken pieces.
(defvar my/-package-archives-refreshed nil
  "t after `package-refresh-contents' has been called in this session.")
(defun my/-package-install-with-refresh-once (orig-fn &rest args)
  (condition-case err
      (apply orig-fn args)
    ((file-missing error)
     (cond
      (my/-package-archives-refreshed
       (signal (car err) (cdr err)))
      (t
       (setq my/-package-archives-refreshed t)
       (message "init.el: package-install failed for %S; refreshing archives and retrying once."
                (car args))
       (package-refresh-contents)
       (apply orig-fn args))))))
(advice-add 'package-install :around #'my/-package-install-with-refresh-once)

;; 3. Secrets — per-Mac, never tracked in git ------------------------------
(let ((secrets (expand-file-name "secrets.el" user-emacs-directory)))
  (when (file-exists-p secrets)
    (load secrets nil 'nomessage)))

;; 4. Entry point — config.org (or pre-tangled config.el if present) ------
(let* ((private-org (expand-file-name "config.org" my/private-config-dir))
       (private-el  (expand-file-name "config.el"  my/private-config-dir))
       (seed-org    (expand-file-name "config.org" my/seed-config-dir))
       (seed-el     (expand-file-name "config.el"  my/seed-config-dir))
       (rescue-bootstrap nil)
       (entry-dir
        (cond
         ((or (file-exists-p private-el) (file-exists-p private-org))
          my/private-config-dir)
         ((or (file-exists-p seed-el) (file-exists-p seed-org))
          (setq rescue-bootstrap t)
          (display-warning
           'emacs-setup
           (format "Private config missing at %s; loading seed bootstrap so %s can be restored from GitHub."
                   my/private-config-dir my/data-dir)
           :warning)
          my/seed-config-dir)
         (t my/private-config-dir)))
       (config-org (expand-file-name "config.org" entry-dir))
       (config-el  (expand-file-name "config.el"  entry-dir)))
  (setq my/config-dir entry-dir)
  (add-to-list 'load-path my/config-dir)
  (cond
   (rescue-bootstrap
    (require 'org)
    ;; Load only the task runner and bootstrap. Loading the full seed
    ;; config would create starter data under `my/data-dir' before the
    ;; GitHub repo can be cloned/restored.
    (dolist (module '("05-tasks.org" "10-bootstrap.org"))
      (let ((path (expand-file-name module
                                    (expand-file-name "modules/" my/seed-config-dir))))
        (when (file-exists-p path)
          (condition-case err
              (org-babel-load-file path)
            (error
             (display-warning
              'emacs-setup
              (format "Rescue bootstrap module %s failed: %s"
                      module err)
              :warning))))))
    (when (fboundp 'my/bootstrap)
      (add-hook 'emacs-startup-hook #'my/bootstrap)))
   ((file-exists-p config-el)
    (load config-el nil 'nomessage))
   ((file-exists-p config-org)
    (require 'org)
    (org-babel-load-file config-org))
   (t
    (display-warning
     'emacs-setup
     (format "No private config at %s and no seed config at %s."
             my/private-config-dir my/seed-config-dir)
     :error))))

;; 5. custom.el — keep customize out of init.el ---------------------------
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))

(provide 'init)
;;; init.el ends here

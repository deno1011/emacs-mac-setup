;;; init.el --- Emacs-for-Mac distro entry point  -*- lexical-binding: t; -*-
;;
;; Thin loader. Knows only:
;;
;;   - WHERE the user's data lives (`my/data-dir', overridable via
;;     EMACS_DATA_DIR; default ~/emacs/).
;;   - WHERE the literate config lives (`my/config-dir' =
;;     <my/data-dir>/config/).
;;   - The ENTRY POINT FILENAME inside that directory (`config.org', or a
;;     pre-tangled `config.el' if present).
;;
;; Nothing else. No module list, no seeding logic, no per-feature flags.
;; install.sh places the seed config files into my/config-dir on first
;; install. config.org discovers and loads modules. Each layer below this
;; one is responsible for its own contents; init.el does not know what's
;; in them.
;;
;; Init-phase GC tuning lives in early-init.el (Emacs 27+).

;; 1. Where data and config live ------------------------------------------
(defvar my/data-dir
  (expand-file-name
   (file-name-as-directory
    (or (getenv "EMACS_DATA_DIR") "~/emacs/")))
  "Root directory for the user's personal data + literate config.
Override per-Mac with EMACS_DATA_DIR (and `launchctl setenv' for GUI
Emacs).")

(defvar my/config-dir
  (expand-file-name "config/" my/data-dir)
  "Directory containing the literate config. Lives INSIDE the user's
private repo so edits sync across Macs via git.")

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

;; 3. Secrets — per-Mac, never tracked in git ------------------------------
(let ((secrets (expand-file-name "secrets.el" user-emacs-directory)))
  (when (file-exists-p secrets)
    (load secrets nil 'nomessage)))

;; 4. Entry point — config.org (or pre-tangled config.el if present) ------
(let ((config-org (expand-file-name "config.org" my/config-dir))
      (config-el  (expand-file-name "config.el"  my/config-dir)))
  (cond
   ((file-exists-p config-el)
    (load config-el nil 'nomessage))
   ((file-exists-p config-org)
    (require 'org)
    (org-babel-load-file config-org))
   (t
    (display-warning
     'emacs-setup
     (format "No config.org or config.el at %s — run install.sh to seed
the distro into ~/emacs/config/, or copy your config there manually."
             my/config-dir)
     :error))))

;; 5. custom.el — keep customize out of init.el ---------------------------
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))

(provide 'init)
;;; init.el ends here

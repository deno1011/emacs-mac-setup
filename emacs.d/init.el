;;; init.el --- Emacs-for-Mac distro entry point  -*- lexical-binding: t; -*-
;;
;; Thin loader. Knows:
;;
;;   - WHERE the literate config lives (`my/config-dir' = ~/.emacs.d/config/).
;;     Config is distro-managed: seeded by install.sh from the
;;     emacs-mac-setup repo, updated by the bootstrap's
;;     `distro-config-update' task. Never lives in the user's data folder.
;;
;;   - WHERE the user's DATA lives (`my/data-dir', settled at runtime by
;;     the bootstrap orchestrator from Keychain.GitHubRepo / BW.Repo /
;;     setup-form Save; overridable per-Mac via the EMACS_DATA_DIR env
;;     var). Data = org files, wiki, agenda, etc. Per-Mac, may differ
;;     between machines. Switching data-dir does NOT affect config —
;;     config is at ~/.emacs.d/config/ regardless.
;;
;; Nothing else. No rescue mode, no per-feature flags, no module list.
;; install.sh places the seed config into ~/.emacs.d/config/ on every run;
;; ~/.emacs.d/config/config.org discovers and loads modules.

;; 0. User override — escape hatch for a fully custom init ---------------
;;
;; If `~/.emacs.d/override_init.el' exists, load THAT file and skip the
;; rest of THIS file. install.sh overwrites init.el on every run (so
;; distro fixes reach the user automatically); override_init.el is never
;; touched, so the user can keep a private setup that survives updates.
;;
;; Enable:  create `~/.emacs.d/override_init.el' with your own init.
;; Disable: rename / delete it — the default init below takes over.
;;
;; A non-nil return from the catch body means the override loaded and
;; everything after it in this file is skipped. The `provide' at the
;; bottom still runs so `(require 'init)' elsewhere keeps working.
(catch 'my/init-handed-off
  (let ((override (expand-file-name "override_init.el" user-emacs-directory)))
    (when (file-exists-p override)
      (message "init.el: loading %s and skipping default init." override)
      (load override nil 'nomessage)
      (throw 'my/init-handed-off t)))

;; 1. Where data lives -----------------------------------------------------
(defvar my/data-dir
  (let ((env (getenv "EMACS_DATA_DIR")))
    (if env
        (expand-file-name (file-name-as-directory env))
      user-emacs-directory))
  "Root directory for the user's PERSONAL DATA — org files, wiki content,
agenda files, GTD content, etc. NOT the literate config (that lives at
`my/config-dir' = ~/.emacs.d/config/, regardless of which data-dir is
selected).

Default is `user-emacs-directory' (`~/.emacs.d/'). The choice matters
because third-party packages — gptel-agent-runtime is one — read this
variable AT LOAD TIME via byte-compiled code like
`(directory-file-name my/data-dir)'. A nil value crashes them with
\"Wrong type argument: stringp, nil\". The same packages typically
ship a `(defvar my/data-dir user-emacs-directory …)' as a hint, but
`defvar' is a no-op once the variable is bound, so init.el's binding
wins.

The bootstrap orchestrator overwrites this with the chosen folder
(from Keychain.GitHubRepo / BW.Repo / setup-form Save) on first run
and on every subsequent launch. Override per-Mac via `EMACS_DATA_DIR'
(escape hatch for testing / scripted installs).")

;; 2. Where the literate config lives ------------------------------------
(defvar my/config-dir (expand-file-name "config/" user-emacs-directory)
  "Distro-managed literate config (config.org + modules/*.org). Always
~/.emacs.d/config/. Seeded by install.sh; refreshed by the bootstrap's
`distro-config-update' task. Independent of `my/data-dir' — switching
the data folder doesn't affect where config loads from.")

(add-to-list 'load-path my/config-dir)

;; 3. Package manager: elpaca --------------------------------------------
;;
;; Moved out of this file. The elpaca + elpaca-use-package bootstrap
;; now lives at `~/.emacs.d/config/modules/!00_startfirst.el' — a
;; SOURCE-LOADED module (no byte-compile). The `!' name prefix sorts
;; ahead of every numbered module in `string<' order, so config.org's
;; discovery loop runs it first. It is source-loaded specifically
;; because the `elpaca' macro is defined and used in the same file —
;; a pattern that breaks when byte-compiled (the macro call freezes
;; as a function call against an unknown symbol, then funcall fails
;; at runtime). `my/-load-module' in config.org recognizes the `!'
;; prefix and skips byte-compile for those files.
;;
;; Nothing here in init.el needs elpaca; the first call to
;; `(use-package … :ensure …)' lands in `30-core.org', well after the
;; `!00_startfirst.el' bootstrap and `(elpaca-wait)' have completed.

;; 4. Secrets — per-Mac, never tracked in git ----------------------------
(let ((secrets (expand-file-name "secrets.el" user-emacs-directory)))
  (when (file-exists-p secrets)
    (load secrets nil 'nomessage)))

;; 5. Entry point — config.org (or pre-tangled config.el if present) -----
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
     (format "No config at %s. Run install.sh to seed it." my/config-dir)
     :error))))

;; 6. custom.el — keep customize out of init.el --------------------------
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file)))
;; ^ closes the `catch' opened in section 0.

(provide 'init)
;;; init.el ends here

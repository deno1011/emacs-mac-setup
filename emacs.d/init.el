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
    (and env (expand-file-name (file-name-as-directory env))))
  "Root directory for the user's PERSONAL DATA — org files, wiki content,
agenda files, GTD content, etc. NOT the literate config (that lives at
`my/config-dir' = ~/.emacs.d/config/, regardless of which data-dir is
selected). nil during the brief window between init.el and the
10-bootstrap module load; the bootstrap orchestrator settles it from
Keychain.GitHubRepo / BW.Repo / setup-form Save before any other module
tangles. Set explicitly only when EMACS_DATA_DIR is in the environment
(escape hatch for testing / scripted installs).")

;; 2. Where the literate config lives ------------------------------------
(defvar my/config-dir (expand-file-name "config/" user-emacs-directory)
  "Distro-managed literate config (config.org + modules/*.org). Always
~/.emacs.d/config/. Seeded by install.sh; refreshed by the bootstrap's
`distro-config-update' task. Independent of `my/data-dir' — switching
the data folder doesn't affect where config loads from.")

(add-to-list 'load-path my/config-dir)

;; 3. Package manager: elpaca ---------------------------------------------
(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca-activate)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-sources-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (<= emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
                                                      (list (format "--depth=%d" depth) "--no-single-branch"))
                                                  ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                        "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

(elpaca elpaca-use-package
  (require 'elpaca-use-package)
  (elpaca-use-package-mode))
(elpaca-wait)
(setq use-package-always-ensure t)

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

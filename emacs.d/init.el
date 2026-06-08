;;; init.el --- Emacs-for-Mac distro entry point  -*- lexical-binding: t; -*-
;;
;; Thin loader. Knows:
;;
;;   - WHERE the literate config lives (`my/config-dir' = ~/.emacs.d/config/).
;;     Config is distro-managed: seeded by install.sh from the
;;     emacs-mac-setup repo, updated by the bootstrap's
;;     `distro-config-update' task. Never lives in the user's data folder.
;;
;;   - WHERE the user's DATA lives (`my/data-dir' = ~/emacs/, overridable via
;;     EMACS_DATA_DIR env var or by a generated ~/.emacs.d/data-dir.el).
;;     Data = org files, wiki, agenda, etc. Per-Mac, may differ between
;;     machines (driven by BW.Repo on first launch). Switching data-dir
;;     does NOT affect config — config is at ~/.emacs.d/config/ regardless.
;;
;; Nothing else. No rescue mode, no per-feature flags, no module list.
;; install.sh places the seed config into ~/.emacs.d/config/ on every run;
;; ~/.emacs.d/config/config.org discovers and loads modules.

;; 1. Where data lives -----------------------------------------------------
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
  "Root directory for the user's PERSONAL DATA — org files, wiki content,
agenda files, GTD content, etc. NOT the literate config (that lives at
`my/config-dir' = ~/.emacs.d/config/, regardless of which data-dir is
selected). Override per-Mac via EMACS_DATA_DIR or let bootstrap derive
it from the BW.Repo field and write data-dir.el.")

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
(when (file-exists-p custom-file) (load custom-file))

(provide 'init)
;;; init.el ends here

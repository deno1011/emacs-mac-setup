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

;; 2. Package manager: elpaca ---------------------------------------------
;;
;; We use elpaca (https://github.com/progfolio/elpaca) instead of the built-in
;; package.el. Elpaca clones each package from git into ~/.emacs.d/elpaca/
;; (one tree per package), generates autoloads, byte-compiles selectively
;; (no test/scripts/docs noise), and ships a built-in lockfile for
;; reproducibility. This replaces ~400 lines of custom Layer 1+2+3 code
;; (test/script strip, packages.lock, validation) we previously built on
;; top of package.el.
;;
;; The bootstrap snippet below is the exact upstream recommended form
;; (per elpaca's README); we keep it close to upstream so updates from
;; the elpaca repo apply cleanly.
(defvar elpaca-installer-version 0.8)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-repos-directory (expand-file-name "repos/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca--activate-package)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-repos-directory))
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
    (load "./elpaca-autoloads")))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;; Install use-package and route `:ensure t' through elpaca, so existing
;; (use-package X :ensure t) forms in the modules install via elpaca
;; without source changes. Modules that already had `:ensure nil' to skip
;; install continue to work as before.
(elpaca elpaca-use-package
  (require 'elpaca-use-package)
  (elpaca-use-package-mode))
(elpaca-wait)
(setq use-package-always-ensure t)

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

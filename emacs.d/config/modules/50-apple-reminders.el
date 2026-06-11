;;; 50-apple-reminders.el --- Apple Reminders bridge -*- lexical-binding: t; -*-

(defvar my/data-dir)
(defvar org-apple-reminders-sync-file)
(defvar org-apple-reminders-auto-sync-interval)
(defvar org-apple-reminders-included-lists)

(declare-function org-apple-reminders-setup "org-apple-reminders")

;; Installation handled by the use-package form below via elpaca's
;; recipe syntax. Updates: `M-x elpaca-fetch org-apple-reminders'
;; (or `M-x elpaca-fetch-all' for everything).

;; No data-dir.el gate. The 20-bootstrap module runs the orchestrator
;; synchronously at the END of its own tangled load — see Step 9 of
;; modules/20-bootstrap.org — so by the time this module tangles,
;; `my/data-dir' has its final value (Keychain.GitHubRepo, BW.Repo,
;; or the form's typed value, whichever the probe settled). The
;; `:config' setq below resolves directly to ~/CHOSEN-REPO/data/org/
;; reminders.org without any restart dance.
(when (eq system-type 'darwin)
  (use-package org-apple-reminders
    :ensure (org-apple-reminders
             :host github
             :repo "deno1011/org-apple-reminders"
             :branch "main")
    :config
    (setq org-apple-reminders-sync-file
          (expand-file-name "data/org/reminders.org" my/data-dir))

    ;; nil = sync all Apple Reminders lists (the default — not restricted).
    ;; Set to a list of names to restrict, or pick interactively with `C-c r i'.
    (setq org-apple-reminders-included-lists nil)

    ;; New unlinked TODOs in known reminder files use the nearest level-1
    ;; heading as the Apple list name. TODOs outside a list section use the
    ;; configured/default Apple Reminders list.

    (org-apple-reminders-setup)))

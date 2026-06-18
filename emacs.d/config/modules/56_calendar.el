;;; 56_calendar.el --- EventKit calendar read + ingest -*- lexical-binding: t; -*-

(defvar my/data-dir)
(declare-function my/bootstrap-ready-p "20.03.01_bootstrap")
(defvar org-apple-calendar-ingest-file)
(defvar org-apple-calendar-source-file)
(defvar org-apple-calendar-overrides-file)
(defvar org-apple-calendar-classification-file)
(defvar org-apple-calendar-auto-refresh-interval)
(declare-function org-apple-calendar-setup-auto-refresh "org-apple-calendar")
(declare-function org-apple-calendar-override-role "org-apple-calendar")
(declare-function org-apple-calendar-init-classification "org-apple-calendar")
(declare-function org-apple-calendar-show-calendars "org-apple-calendar")
(declare-function org-apple-calendar-upcoming "org-apple-calendar")
(declare-function org-apple-calendar-show-free-slots "org-apple-calendar")
(declare-function org-apple-calendar-refresh-mirror "org-apple-calendar")
(declare-function org-apple-calendar-ingest-deadlines "org-apple-calendar")
(declare-function org-apple-calendar-push-appointments "org-apple-calendar")
(declare-function org-apple-calendar-sync-appointments "org-apple-calendar")
(declare-function org-apple-calendar-adopt-event-at-point "org-apple-calendar")

(when (and (eq system-type 'darwin)
           (my/bootstrap-ready-p))
  (use-package org-apple-calendar
    :ensure (org-apple-calendar
             :host github
             :repo "deno1011/org-apple-calendar"
             :branch "main"
             :depth nil)
    :defer t
    :commands (org-apple-calendar-show-calendars
               org-apple-calendar-upcoming
               org-apple-calendar-show-free-slots
               org-apple-calendar-refresh-mirror
               org-apple-calendar-ingest-deadlines
               org-apple-calendar-push-appointments
               org-apple-calendar-sync-appointments
               org-apple-calendar-adopt-event-at-point)
    :init
    (define-prefix-command 'my/calendar-map)
    (global-set-key (kbd "C-c k") 'my/calendar-map)
    (define-key my/calendar-map (kbd "l") #'org-apple-calendar-show-calendars)
    (define-key my/calendar-map (kbd "u") #'org-apple-calendar-upcoming)
    (define-key my/calendar-map (kbd "f") #'org-apple-calendar-show-free-slots)
    (define-key my/calendar-map (kbd "m") #'org-apple-calendar-refresh-mirror)
    (define-key my/calendar-map (kbd "i") #'org-apple-calendar-ingest-deadlines)
    (define-key my/calendar-map (kbd "p") #'org-apple-calendar-push-appointments)
    (define-key my/calendar-map (kbd "s") #'org-apple-calendar-sync-appointments)
    (define-key my/calendar-map (kbd "a") #'org-apple-calendar-adopt-event-at-point)
    (define-key my/calendar-map (kbd "o") #'org-apple-calendar-override-role)
    (define-key my/calendar-map (kbd "c") #'org-apple-calendar-init-classification)
    :config
    ;; All personal paths live under the (git-crypt) data repo — encrypted,
    ;; reinstall-safe, and out of this shared config. The per-calendar
    ;; busy/info/ignore policy is the user's own data: it lives in
    ;; calendar-classification.eld, auto-created listing ALL calendars on first
    ;; access (or M-x org-apple-calendar-init-classification / C-c k c).
    ;; No real calendar names in this public module.
    (setq org-apple-calendar-ingest-file
          (expand-file-name "data/org/gtd/next.org" my/data-dir)
          org-apple-calendar-source-file
          (expand-file-name "data/org/calendar.org" my/data-dir)
          org-apple-calendar-overrides-file
          (expand-file-name "data/org/calendar-overrides.eld" my/data-dir)
          org-apple-calendar-classification-file
          (expand-file-name "data/org/calendar-classification.eld" my/data-dir))
    ;; Idle auto-refresh of the read-only mirror (15 min idle). The two-way
    ;; write sync (C-c k s) stays manual on purpose.
    (setq org-apple-calendar-auto-refresh-interval 900)
    (org-apple-calendar-setup-auto-refresh)))

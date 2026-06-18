;;; 55_calendar.el --- Apple Calendar (iCloud) sync via org-caldav -*- lexical-binding: t; -*-

(defvar my/data-dir)
(declare-function my/bootstrap-ready-p "20.03.01_bootstrap")
(defvar org-caldav-url)
(defvar org-caldav-calendar-id)
(defvar org-caldav-files)
(defvar org-caldav-inbox)
(defvar org-caldav-save-directory)
(defvar org-icalendar-timezone)
(declare-function org-caldav-sync "org-caldav")
(declare-function my/keychain-set-internet "20.01.01_bootstrap_keychain")
(declare-function my/keychain-get-internet "20.01.01_bootstrap_keychain")
(declare-function my/keychain-set "20.01.01_bootstrap_keychain")
(declare-function my/keychain-get "20.01.01_bootstrap_keychain")

(when (and (eq system-type 'darwin)
           (my/bootstrap-ready-p))
  (use-package org-caldav
    :ensure t
    :defer t
    :commands (org-caldav-sync)
    :init
    ;; Read the iCloud app-specific password from the macOS Keychain first,
    ;; then ~/.authinfo.gpg. The password is never stored in this config.
    (require 'auth-source)
    (add-to-list 'auth-sources 'macos-keychain-internet)
    :config
    (setq org-caldav-files
          (list (expand-file-name "data/org/calendar.org" my/data-dir))
          org-caldav-inbox
          (expand-file-name "data/org/calendar-inbox.org" my/data-dir)
          org-caldav-save-directory
          (expand-file-name "org-caldav/" user-emacs-directory))
    ;; Only org entries with an active timestamp become calendar events;
    ;; SCHEDULED/DEADLINE tasks belong to org-apple-reminders, not here.
    (setq org-caldav-sync-todo nil)
    ;; Account-specific values come from the macOS Keychain (generic passwords
    ;; under service "emacs-icloud-caldav"), never from a file. org-caldav-sync
    ;; stays inert until url + calendar-id are present. Set via M-x my/caldav-setup.
    (when (fboundp 'my/keychain-get)
      (let ((url (my/keychain-get "emacs-icloud-caldav" "url"))
            (cid (my/keychain-get "emacs-icloud-caldav" "calendar-id"))
            (tz  (my/keychain-get "emacs-icloud-caldav" "timezone")))
        (when url (setq org-caldav-url url))
        (when cid (setq org-caldav-calendar-id cid))
        (when tz  (setq org-icalendar-timezone tz))))
    (let ((d org-caldav-save-directory))
      (unless (file-directory-p d) (make-directory d t)))
    ;; iCloud needs preemptive Basic auth + no keep-alive (see section above).
    (require 'url-http)
    (advice-add 'url-http-create-request :filter-return
                #'my/caldav--preemptive-basic-auth)
    (advice-add 'org-caldav-sync :around #'my/caldav--no-keepalive)
    (advice-add 'org-caldav-url-dav-get-properties :filter-return
                #'my/caldav--coerce-dav-status)))

(defvar my/caldav-apple-id nil
  "Apple ID (email) for iCloud CalDAV. nil ⇒ prompt with `user-mail-address'.
Normally read from the Keychain (service \"emacs-icloud-caldav\", account
\"apple-id\") by `my/caldav-setup'.")

(defun my/caldav--store-password (account pass &optional url)
  "Store iCloud app-specific PASS for ACCOUNT as Internet passwords in Keychain.
Writes the entry for `caldav.icloud.com' and, when URL (default
`org-caldav-url') names an iCloud host, for that host too — both with port 443
so url.el's port-qualified auth-source lookup matches. Validates the Apple
`xxxx-xxxx-xxxx-xxxx' password shape (with an override prompt). Returns the
list of hosts written."
  (unless (fboundp 'my/keychain-set-internet)
    (user-error "Keychain primitive unavailable (bootstrap not loaded)"))
  (when (string-empty-p (string-trim account))
    (user-error "Apple ID must not be empty"))
  (when (string-empty-p (string-trim pass))
    (user-error "Password must not be empty"))
  ;; Apple app-specific passwords are `xxxx-xxxx-xxxx-xxxx' (16 lowercase
  ;; letters in four dash-separated groups). Warn early on anything else —
  ;; a stray character here surfaces only later as an opaque 401.
  (when (and (not (string-match-p
                   "\\`[a-z]\\{4\\}-[a-z]\\{4\\}-[a-z]\\{4\\}-[a-z]\\{4\\}\\'" pass))
             (not (yes-or-no-p
                   (format "That is %d chars, not the xxxx-xxxx-xxxx-xxxx app-password format. Store anyway? "
                           (length pass)))))
    (user-error "Aborted — re-run and paste the app-specific password exactly"))
  (let* ((src (or url (and (boundp 'org-caldav-url) org-caldav-url)))
         (hosts (delete-dups
                 (cons "caldav.icloud.com"
                       (when (and (stringp src) (string-match-p "icloud" src))
                         (let ((h (url-host (url-generic-parse-url src))))
                           (and h (list h))))))))
    (dolist (host hosts)
      (let ((res (my/keychain-set-internet host account pass 443)))
        (unless (eq res :ok)
          (user-error "Keychain write failed for %s: %s" host (cadr res)))))
    hosts))

(defun my/caldav-set-password ()
  "Prompt for the iCloud Apple ID + app-specific password; store in Keychain.
Run this when the doctor reports only the *password* missing; for the full
account wiring use `my/caldav-setup'."
  (interactive)
  (let* ((account (read-string
                   "Apple ID (email): "
                   (or (and (fboundp 'my/keychain-get)
                            (my/keychain-get "emacs-icloud-caldav" "apple-id"))
                       my/caldav-apple-id user-mail-address)))
         (pass    (string-trim (read-passwd "iCloud app-specific password: ")))
         (hosts   (my/caldav--store-password account pass)))
    (message "iCloud CalDAV password stored for %s (%s)"
             account (string-join hosts ", "))))

(defun my/caldav-setup ()
  "Wire iCloud CalDAV entirely through the macOS Keychain — no config file.
Prompts for Apple ID, CalDAV URL (with DSID), the \"Org\" calendar UUID, the
timezone, and the app-specific password; stores url/calendar-id/apple-id/
timezone as generic passwords under service \"emacs-icloud-caldav\" plus the
Internet password, and applies them to the running session. Re-run anytime to
update."
  (interactive)
  (unless (fboundp 'my/keychain-set)
    (user-error "Keychain primitive unavailable (bootstrap not loaded)"))
  (let* ((apple-id (string-trim
                    (read-string
                     "Apple ID (email): "
                     (or (my/keychain-get "emacs-icloud-caldav" "apple-id")
                         my/caldav-apple-id user-mail-address))))
         (url (string-trim
               (read-string
                "CalDAV URL (https://pNN-caldav.icloud.com/DSID/calendars): "
                (or (my/keychain-get "emacs-icloud-caldav" "url")
                    (and (boundp 'org-caldav-url) (stringp org-caldav-url)
                         org-caldav-url)))))
         (cid (string-trim
               (read-string
                "\"Org\" calendar UUID: "
                (or (my/keychain-get "emacs-icloud-caldav" "calendar-id")
                    (and (boundp 'org-caldav-calendar-id)
                         (stringp org-caldav-calendar-id)
                         org-caldav-calendar-id)))))
         (tz (string-trim
              (read-string
               "Calendar timezone: "
               (or (my/keychain-get "emacs-icloud-caldav" "timezone")
                   (and (boundp 'org-icalendar-timezone)
                        (stringp org-icalendar-timezone)
                        org-icalendar-timezone)
                   "Europe/Berlin"))))
         (pass (string-trim (read-passwd "iCloud app-specific password: "))))
    (when (string-empty-p apple-id) (user-error "Apple ID must not be empty"))
    (when (string-empty-p url) (user-error "CalDAV URL must not be empty"))
    (when (string-empty-p cid) (user-error "Calendar UUID must not be empty"))
    (dolist (pair (list (cons "apple-id" apple-id) (cons "url" url)
                        (cons "calendar-id" cid) (cons "timezone" tz)))
      (let ((res (my/keychain-set "emacs-icloud-caldav" (car pair) (cdr pair))))
        (unless (eq res :ok)
          (user-error "Keychain write failed for %s: %s" (car pair) (cadr res)))))
    ;; Password (Internet password, both hosts) — derives the host from URL.
    (my/caldav--store-password apple-id pass url)
    ;; Apply to the running session immediately.
    (setq my/caldav-apple-id apple-id
          org-caldav-url url
          org-caldav-calendar-id cid)
    (when (boundp 'org-icalendar-timezone) (setq org-icalendar-timezone tz))
    (message "iCloud CalDAV wired via Keychain for %s — now M-x org-caldav-sync"
             apple-id)))

(defun my/caldav--preemptive-basic-auth (request)
  "Add a preemptive Basic `Authorization' header to REQUEST for iCloud hosts.
REQUEST is the raw HTTP request string built by `url-http-create-request';
`url-http-target-url' is the buffer-local target. No-op for other hosts or
when an Authorization header is already present."
  (if (and (boundp 'url-http-target-url) url-http-target-url
           (let ((h (url-host url-http-target-url)))
             (and h (string-match-p "caldav\\.icloud\\.com" h)))
           (let ((case-fold-search t))
             (not (string-match-p "^authorization:" request))))
      (let* ((found (car (auth-source-search :host "caldav.icloud.com" :port 443
                                             :max 1 :require '(:user :secret))))
             (user (and found (plist-get found :user)))
             (secret (and found (plist-get found :secret)))
             (pass (and secret (if (functionp secret) (funcall secret) secret))))
        (if (and user pass (string-match "\r\n" request))
            (concat (substring request 0 (match-end 0))
                    "Authorization: Basic "
                    (base64-encode-string (concat user ":" pass) t) "\r\n"
                    (substring request (match-end 0)))
          request))
    request))

(defun my/caldav--no-keepalive (orig &rest args)
  "Run ORIG (a sync command) with url.el keep-alive disabled.
iCloud's chunked responses confuse url.el's keep-alive reuse."
  (let ((url-http-attempt-keepalives nil))
    (apply orig args)))

(defun my/caldav--coerce-dav-status (output)
  "Coerce non-numeric `DAV:status' values in OUTPUT to HTTP codes.
`org-caldav-check-connection' does `(/ status 100)'; against iCloud the parsed
status comes back as the empty string, raising `number-or-marker-p \"\"'. Pull
the numeric code out of strings like \"HTTP/1.1 200 OK\"; if none is present but
a response was returned, assume 200 (we got properties back). Returns OUTPUT."
  (dolist (entry output output)
    (when (consp entry)
      (let* ((props (cdr entry))
             (st (and (listp props) (plist-get props 'DAV:status))))
        (when (and st (not (numberp st)))
          (setcdr entry
                  (plist-put props 'DAV:status
                             (if (and (stringp st)
                                      (string-match "\\([0-9]\\{3\\}\\)" st))
                                 (string-to-number (match-string 1 st))
                               200))))))))

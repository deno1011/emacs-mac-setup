;;; 90_doctor.el --- Health check command -*- lexical-binding: t; -*-

(require 'subr-x)
(require 'cl-lib)

;; Forward declarations for symbols owned by bootstrap. Doctor uses
;; them defensively via `fboundp' / `boundp' so it works even when
;; bootstrap halted on a required-step failure (which is the case
;; where the user most needs the doctor).
(defvar my/data-dir)
(declare-function my/bootstrap-ready-p             "20.03.01_bootstrap")
(declare-function my/bootstrap--all-credential-descriptors "20.03.01_bootstrap")
(declare-function my/keychain-get                  "20.01.01_bootstrap_keychain")
(declare-function my/keychain-get-internet         "20.01.01_bootstrap_keychain")
(declare-function my/keychain-get                  "20.01.01_bootstrap_keychain")
(declare-function my/git-remote-url                "20.01.02_bootstrap_git")
(declare-function my/gh-auth-status                "20.01.03_bootstrap_gh")
(defvar my/emacs-agent-runtime-source)
(defvar my/emacs-agent-runtime-dir)
(defvar my/emacs-agent-runtime-elpaca-repo)
(defvar my/emacs-agent-runtime-qmd-command)
(defvar my/emacs-agent-runtime-qmd-package-manager)
(defvar my/emacs-agent-runtime-qmd-projection-directory)
(declare-function my/emacs-agent-runtime-qmd-install-command
                  "60_emacs-agent-runtime")
(declare-function ear-list-tools "ear-core")
(declare-function messenger-bridge--subdir "messenger-bridge")

;;; Public API (callable from M-x or feature modules):
;;;
;;;   (my/doctor)          → interactive; renders *Doctor* buffer
;;;   (my/doctor-rerun)    → interactive; recomputes if buffer is open
;;;
;;; Internal (DO NOT call from other files):
;;;
;;;   my/doctor--checks    → list of check thunks
;;;   my/doctor--run-check → invoke one thunk with error catching
;;;   my/doctor--render    → format the result list into the buffer

(defvar my/doctor--checks nil
  "List of check thunks. Each returns a plist; see `my/doctor--render'.")

;; Reset on every file load. Each `my/doctor-define-check' below `push'es
;; to this list, so reloading the file (manually via M-x load-file, or
;; via `my/-load-module' on a stale .elc rebuild) would otherwise leave
;; the previous registration in place AND add the new one — every check
;; would run twice (or N times after N reloads), with the older closure
;; capturing the old code. Force-reset here so the list always matches
;; exactly the defcheck calls that follow.
(setq my/doctor--checks nil)

(defmacro my/doctor-define-check (label-string &rest body)
  "Register a doctor check that displays as LABEL-STRING.
BODY runs every time the user invokes `my/doctor' and must return
a plist with :status (:ok / :warn / :fail), optionally :detail
and :fix. The :label is supplied by this macro."
  (declare (indent 1))
  `(push (lambda ()
           (condition-case err
               (let ((result (progn ,@body)))
                 (plist-put result :label ,label-string))
             (error
              (list :label ,label-string
                    :status :fail
                    :detail (format "check signalled: %S" err)))))
         my/doctor--checks))

(my/doctor-define-check "Homebrew on PATH"
  (cond
   ((executable-find "brew")
    (list :status :ok :detail (executable-find "brew")))
   (t
    (list :status :fail
          :detail "brew not in PATH"
          :fix "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""))))

(my/doctor-define-check "gcc-15 (for libgccjit)"
  (let ((gcc (executable-find "gcc-15")))
    (cond
     (gcc (list :status :ok :detail gcc))
     (t   (list :status :fail
                :detail "gcc-15 not in PATH"
                :fix "brew install gcc")))))

(my/doctor-define-check "libgccjit installed"
  (let ((lib "/opt/homebrew/lib/gcc/current/libgccjit.dylib"))
    (cond
     ((file-exists-p lib) (list :status :ok :detail lib))
     (t (list :status :fail
              :detail "libgccjit.dylib not present at the standard brew path"
              :fix "brew install libgccjit")))))

(my/doctor-define-check "native-compilation available"
  (cond
   ((and (fboundp 'native-comp-available-p) (native-comp-available-p))
    (list :status :ok :detail "native-comp-available-p returned t"))
   (t (list :status :fail
            :detail "native-comp not available in this Emacs build"
            :fix "Reinstall emacs-plus@30: brew reinstall d12frosted/emacs-plus/emacs-plus@30 --with-xwidgets"))))

(my/doctor-define-check "LIBRARY_PATH for libgccjit"
  (let ((lp (getenv "LIBRARY_PATH")))
    (cond
     ((null lp)
      (list :status :fail
            :detail "LIBRARY_PATH not set; libgccjit will not find gcc helpers"
            :fix "Re-run install.sh to regenerate ~/.emacs.d/env-snapshot.el"))
     ((string-match-p "gcc" lp)
      (list :status :ok :detail lp))
     (t
      (list :status :warn
            :detail (format "LIBRARY_PATH set but no gcc path inside: %s" lp)
            :fix "Re-run install.sh to regenerate ~/.emacs.d/env-snapshot.el")))))

(my/doctor-define-check "eln-cache writable"
  (let ((cache (expand-file-name "eln-cache" user-emacs-directory)))
    (cond
     ((and (file-directory-p cache) (file-writable-p cache))
      (list :status :ok :detail cache))
     ((not (file-directory-p cache))
      (list :status :warn
            :detail "eln-cache directory does not exist (it will be created on first JIT compile)"))
     (t (list :status :fail
              :detail (format "eln-cache exists but is not writable: %s" cache)
              :fix (format "chmod -R u+w %s" cache))))))

(my/doctor-define-check "module .elc files consistent with .el"
  ;; mtime-based: every .elc under modules/ should be at-or-after its
  ;; sibling .el. When the .el is newer than .elc, the loader's
  ;; tier-1 path is still safe (the new tier-1 check requires .elc
  ;; newer than BOTH .org and .el), but the stale .elc means each
  ;; next launch pays a re-compile cost. Flagging it here lets the
  ;; user clean up proactively.
  (let* ((dir (expand-file-name "config/modules/" user-emacs-directory))
         (els (and (file-directory-p dir)
                   (directory-files-recursively dir "\\.el\\'")))
         (stale '()))
    (dolist (el els)
      (let ((elc (concat el "c")))
        (when (and (file-exists-p elc)
                   (file-newer-than-file-p el elc))
          (push (file-relative-name el dir) stale))))
    (cond
     ((null els)
      (list :status :warn :detail "no .el files found under modules/"))
     ((null stale)
      (list :status :ok :detail (format "%d .el ≥ .elc" (length els))))
     (t (list :status :warn
              :detail (format "%d stale .elc found: %s"
                              (length stale)
                              (mapconcat #'identity (cl-subseq stale 0 (min 3 (length stale))) ", "))
              :fix (concat "find " dir " -name '*.elc' -delete  "
                           "&& restart Emacs (the loader will recompile fresh)"))))))

(my/doctor-define-check "Bootstrap converged (my/bootstrap-ready-p)"
  (cond
   ((not (fboundp 'my/bootstrap-ready-p))
    (list :status :fail
          :detail "my/bootstrap-ready-p is not defined — bootstrap module did not load"
          :fix "Check ~/.emacs.d/config/modules/20_bootstrap/ for missing files; re-run install.sh"))
   ((not (my/bootstrap-ready-p))
    (list :status :fail
          :detail "my/bootstrap-ready-p returned nil — a required step failed"
          :fix "M-x my/bootstrap to re-run and inspect the *Warnings* buffer for the failed step"))
   (t (list :status :ok :detail "my/bootstrap-ready-p = t"))))

(my/doctor-define-check "my/data-dir is a real path"
  (cond
   ((not (boundp 'my/data-dir))
    (list :status :fail :detail "my/data-dir is unbound"))
   ((not (stringp my/data-dir))
    (list :status :fail
          :detail (format "my/data-dir = %S (still the not-resolved sentinel)" my/data-dir)
          :fix "Set Keychain entry GitHubRepo, then M-x my/bootstrap"))
   ((not (file-directory-p my/data-dir))
    (list :status :fail
          :detail (format "%s does not exist on disk" my/data-dir)
          :fix "M-x my/bootstrap will clone it once GitHubRepo and GitHubUsername are set"))
   (t (list :status :ok :detail my/data-dir))))

(my/doctor-define-check "data folder is a git clone of the expected repo"
  (cond
   ((not (and (boundp 'my/data-dir) (stringp my/data-dir) (file-directory-p my/data-dir)))
    (list :status :warn :detail "skipped — my/data-dir not ready"))
   ((not (file-directory-p (expand-file-name ".git" my/data-dir)))
    (list :status :fail
          :detail (format "%s is not a git repo" my/data-dir)
          :fix "M-x my/bootstrap will clone if the folder is empty; otherwise rename it manually"))
   ((not (fboundp 'my/git-remote-url))
    (list :status :warn :detail "skipped — bootstrap git Layer 1 not loaded"))
   (t (let ((origin (my/git-remote-url my/data-dir)))
        (cond
         (origin (list :status :ok :detail origin))
         (t (list :status :warn
                  :detail "could not read .git/config origin")))))))

(my/doctor-define-check "Keychain credentials configured"
  (cond
   ((not (fboundp 'my/bootstrap--all-credential-descriptors))
    (list :status :warn :detail "skipped — credential registry not loaded"))
   (t
    (let* ((descs (my/bootstrap--all-credential-descriptors))
           (rows (mapcar
                  (lambda (d)
                    (let* ((acct (plist-get d :account))
                           ;; Each descriptor may carry its own Keychain
                           ;; service via :service. Default to
                           ;; emacs_credentials. Git-crypt keys live in
                           ;; their own service per
                           ;; `20.02.05_bootstrap_git_crypt'.
                           (svc  (or (plist-get d :service) "emacs_credentials"))
                           (val  (when (fboundp 'my/keychain-get)
                                   (my/keychain-get svc acct)))
                           (skipped? (and (stringp val)
                                          (string= val "__SKIPPED__")))
                           (required? (not (plist-get d :allow-skip))))
                      (cons acct (cond
                                  ((and (null val) required?) :missing-required)
                                  ((null val)                 :missing-optional)
                                  (skipped?                    :skipped)
                                  (t                           :set)))))
                  descs))
           (missing-req (cl-count :missing-required rows :key #'cdr))
           (missing-opt (cl-count :missing-optional rows :key #'cdr))
           (skipped     (cl-count :skipped rows :key #'cdr))
           (set-count   (cl-count :set rows :key #'cdr))
           (detail (format "set=%d  skipped=%d  missing-optional=%d  missing-required=%d"
                           set-count skipped missing-opt missing-req)))
      (cond
       ((> missing-req 0)
        (list :status :fail
              :detail (concat detail " — required entries missing: "
                              (mapconcat #'identity
                                         (mapcar #'car
                                                 (cl-remove-if-not
                                                  (lambda (r) (eq (cdr r) :missing-required))
                                                  rows))
                                         ", "))
              :fix "M-x my/credential-set"))
       ((> missing-opt 0)
        (list :status :warn
              :detail (concat detail " — optional entries missing: "
                              (mapconcat #'identity
                                         (mapcar #'car
                                                 (cl-remove-if-not
                                                  (lambda (r) (eq (cdr r) :missing-optional))
                                                  rows))
                                         ", "))))
       (t (list :status :ok :detail detail)))))))

(my/doctor-define-check "iCloud CalDAV wiring (Keychain)"
  (let* ((kc  (fboundp 'my/keychain-get))
         (url (or (and kc (my/keychain-get "emacs-icloud-caldav" "url"))
                  (and (boundp 'org-caldav-url) (stringp org-caldav-url)
                       (string-match-p "icloud" org-caldav-url) org-caldav-url)))
         (cid (and kc (my/keychain-get "emacs-icloud-caldav" "calendar-id")))
         (aid (and kc (my/keychain-get "emacs-icloud-caldav" "apple-id")))
         (pw  (and (fboundp 'my/keychain-get-internet)
                   (my/keychain-get-internet "caldav.icloud.com"))))
    (cond
     ((not (eq system-type 'darwin))
      (list :status :ok :detail "not macOS — skipped"))
     ((not (or url cid aid pw))
      (list :status :ok :detail "iCloud calendar sync not configured — skipped"))
     (t
      (let ((missing (delq nil (list (unless url "url")
                                     (unless cid "calendar-id")
                                     (unless aid "apple-id")
                                     (unless pw  "password")))))
        (if missing
            (list :status :warn
                  :detail (format "iCloud CalDAV Keychain incomplete — missing: %s"
                                  (string-join missing ", "))
                  :fix "M-x my/caldav-setup")
          (list :status :ok
                :detail "fully wired in Keychain (url, calendar-id, apple-id, password)")))))))

(my/doctor-define-check "Apple Calendar integration (org-apple-calendar)"
  (cond
   ((not (eq system-type 'darwin))
    (list :status :ok :detail "not macOS — skipped"))
   ((fboundp 'org-apple-calendar-list-calendars)
    (list :status :ok
          :detail "installed — first C-c k use prompts once for macOS Calendar access"))
   (t
    (list :status :warn
          :detail "org-apple-calendar not loaded (EventKit calendar read/ingest)"
          :fix "check modules/56_calendar; elpaca installs deno1011/org-apple-calendar"))))

(my/doctor-define-check "GTD Apple environment (lists + Org calendar)"
  (cond
   ((not (eq system-type 'darwin))
    (list :status :ok :detail "not macOS — skipped"))
   ((and (boundp 'my/gtd--provision-marker)
         (file-exists-p my/gtd--provision-marker))
    (list :status :ok :detail "provisioned (lists, Org calendar)"))
   (t
    (list :status :warn
          :detail "GTD Apple environment not yet provisioned"
          :fix "M-x my/gtd-provision-apple"))))

(my/doctor-define-check "Messenger bridge"
  (cond
   ((not (featurep 'messenger-bridge))
    (list :status :ok :detail "not loaded (messaging optional) — skipped"))
   ((and (boundp 'messenger-bridge--watch) messenger-bridge--watch
         (fboundp 'file-notify-valid-p)
         (file-notify-valid-p messenger-bridge--watch))
    (list :status :ok
          :detail (format "watching %s"
                          (ignore-errors (messenger-bridge--subdir "inbox")))))
   ((and (boundp 'messenger-bridge--timer) messenger-bridge--timer)
    (list :status :ok :detail "poll-watching (file-notify re-arming)"))
   (t
    (list :status :warn
          :detail "loaded but not started"
          :fix "M-x messenger-bridge-start"))))

(defvar my/whatsapp-adapter-dir (expand-file-name "~/whatsapp-bridge-adapter")
  "Local clone of the WhatsApp bridge adapter (for this onboarding check).")

;; Onboarding guide for the WhatsApp channel. The QR scan is inherently
;; interactive (you scan with your phone) + a secondary-number/ToS decision, so
;; it is never auto-run — the doctor instead detects how far setup got and
;; prints the exact next command, walking a new user through to the QR.
(my/doctor-define-check "WhatsApp adapter (optional messaging channel)"
  (let* ((dir my/whatsapp-adapter-dir)
         (nm (expand-file-name "node_modules" dir))
         (auth (expand-file-name "auth" dir)))
    (cond
     ((not (eq system-type 'darwin))
      (list :status :ok :detail "not macOS — skipped"))
     ((not (file-directory-p dir))
      (list :status :ok
            :detail "not installed — WhatsApp messaging is optional"
            :fix "git clone https://github.com/deno1011/whatsapp-bridge-adapter.git ~/whatsapp-bridge-adapter && cd ~/whatsapp-bridge-adapter && npm install && cp .env.example .env"))
     ((not (file-directory-p nm))
      (list :status :warn
            :detail "adapter cloned but dependencies missing"
            :fix "cd ~/whatsapp-bridge-adapter && npm install"))
     ((not (file-directory-p auth))
      (list :status :warn
            :detail "adapter ready but WhatsApp NOT linked (no QR scanned yet)"
            :fix "M-x my/whatsapp-adapter-link — scan the QR in WhatsApp > Linked Devices (use a SECONDARY number); then whitelist your JID per the README"))
     (t
      (list :status :ok
            :detail "linked (auth present) — M-x my/whatsapp-adapter-install-service for persistence")))))

(my/doctor-define-check "Signal adapter (optional messaging channel)"
  (let* ((dir (expand-file-name "~/signal-bridge-adapter"))
         (nm (expand-file-name "node_modules" dir))
         (cli (executable-find "signal-cli")))
    (cond
     ((not (eq system-type 'darwin))
      (list :status :ok :detail "not macOS — skipped"))
     ((not (file-directory-p dir))
      (list :status :ok
            :detail "not installed — Signal messaging is optional"
            :fix "brew install signal-cli && git clone https://github.com/deno1011/signal-bridge-adapter.git ~/signal-bridge-adapter && cd ~/signal-bridge-adapter && npm install && cp .env.example .env"))
     ((not cli)
      (list :status :warn
            :detail "adapter cloned but signal-cli missing"
            :fix "brew install signal-cli"))
     ((not (file-directory-p nm))
      (list :status :warn
            :detail "adapter cloned but dependencies missing"
            :fix "cd ~/signal-bridge-adapter && npm install"))
     (t
      (list :status :ok
            :detail "ready — M-x my/signal-adapter-link (scan QR in Signal > Linked Devices), set SIGNAL_ACCOUNT, then M-x my/signal-adapter-install-service")))))

(my/doctor-define-check "Email (mu4e) — optional"
  (let* ((mu (executable-find "mu"))
         (mbsync (executable-find "mbsync"))
         (accts (and (boundp 'my/mail-accounts) my/mail-accounts))
         (rc (file-exists-p (expand-file-name "~/.mbsyncrc"))))
    (cond
     ((not (eq system-type 'darwin))
      (list :status :ok :detail "not macOS — skipped"))
     ((not (and mu mbsync))
      (list :status :ok
            :detail "not installed — email is optional"
            :fix "brew install mu isync"))
     ((not accts)
      (list :status :warn
            :detail "mu/isync installed but no accounts configured"
            :fix "M-x my/mail-add-account (stored in Keychain), then M-x my/mail-setup"))
     ((not rc)
      (list :status :warn
            :detail (format "%d mail account(s) defined but ~/.mbsyncrc missing"
                            (length accts))
            :fix "M-x my/mail-setup"))
     (t
      (list :status :ok
            :detail (format "%d account(s), ~/.mbsyncrc present — then M-x my/mail-store-password, `mbsync -a', `mu index', M-x mu4e"
                            (length accts)))))))

(my/doctor-define-check "DavMail (Outlook/Office365 gateway) — optional"
  (let* ((acct (and (boundp 'my/mail-accounts)
                    (seq-find (lambda (a) (eq (plist-get a :provider) 'davmail))
                              my/mail-accounts)))
         (installed (executable-find "davmail"))
         (svc (file-exists-p
               (expand-file-name
                "Library/LaunchAgents/org.davmail.gateway.plist" "~"))))
    (cond
     ((not (eq system-type 'darwin))
      (list :status :ok :detail "not macOS — skipped"))
     ((not acct)
      (list :status :ok :detail "no Outlook/Office365 (davmail) account — not needed"))
     ((not installed)
      (list :status :warn
            :detail "davmail account configured but DavMail not installed"
            :fix "M-x my/mail-davmail-setup (auto-installs DavMail + service)"))
     ((not svc)
      (list :status :warn
            :detail "DavMail installed but its service is not set up"
            :fix "M-x my/mail-davmail-setup"))
     (t
      (list :status :ok
            :detail "DavMail installed + service present (localhost:1143 for Outlook)")))))

(my/doctor-define-check "Outlook XOAUTH2 (direct, no proxy) — optional"
  (let* ((acct (and (boundp 'my/mail-accounts) (fboundp 'my/mail--oauth-p)
                    (seq-find #'my/mail--oauth-p my/mail-accounts)))
         (plugin (and (fboundp 'my/mail--xoauth2-installed-p)
                      (my/mail--xoauth2-installed-p)))
         (helper (and (fboundp 'my/mail-oauth--helper-file)
                      (file-exists-p (my/mail-oauth--helper-file))))
         (token (and acct
                     (zerop (call-process
                             "security" nil nil nil "find-generic-password"
                             "-s" "emacs-mail-oauth"
                             "-a" (plist-get acct :id) "-w")))))
    (cond
     ((not (eq system-type 'darwin))
      (list :status :ok :detail "not macOS — skipped"))
     ((not acct)
      (list :status :ok :detail "no XOAUTH2 (office365) account — not needed"))
     ((not helper)
      (list :status :warn
            :detail "XOAUTH2 account set but token helper missing"
            :fix "M-x my/mail-oauth-setup (installs helper + builds SASL plugin)"))
     ((not plugin)
      (list :status :warn
            :detail "token helper present but cyrus-sasl XOAUTH2 plugin not built"
            :fix "M-x my/mail-xoauth2-ensure (builds the SASL plugin)"))
     ((not token)
      (list :status :warn
            :detail (format "XOAUTH2 ready but %s not authorized yet"
                            (plist-get acct :id))
            :fix (format "M-x my/mail-oauth-authorize RET %s (device-code sign-in)"
                         (plist-get acct :id))))
     (t
      (list :status :ok
            :detail "XOAUTH2 plugin built, helper + refresh token present (direct office365 sync)")))))

(my/doctor-define-check "EAR source mode"
  (let ((source (and (boundp 'my/emacs-agent-runtime-source)
                     my/emacs-agent-runtime-source)))
    (cond
     ((eq source 'local)
      (let ((dir (and (boundp 'my/emacs-agent-runtime-dir)
                      (expand-file-name my/emacs-agent-runtime-dir))))
        (cond
         ((and dir (file-directory-p dir) (file-readable-p dir))
          (list :status :ok
                :detail (format "local checkout: %s%s"
                                dir
                                (if (featurep 'emacs-agent-runtime)
                                    " (loaded)"
                                  " (not loaded yet)"))))
         (t
          (list :status :fail
                :detail (format "local checkout missing: %S" dir)
                :fix "bash ~/emacs-mac-setup-src/install.sh")))))
     ((eq source 'elpaca)
      (cond
       ((featurep 'emacs-agent-runtime)
        (list :status :ok :detail "elpaca source selected; EAR is loaded"))
       ((locate-library "emacs-agent-runtime")
        (list :status :ok
              :detail (format "elpaca source selected; package is loadable at %s"
                              (locate-library "emacs-agent-runtime"))))
       (t
        (list :status :warn
              :detail (format "elpaca source selected but EAR is not loadable yet%s"
                              (if (and (boundp 'my/emacs-agent-runtime-elpaca-repo)
                                       (stringp my/emacs-agent-runtime-elpaca-repo))
                                  (format " (repo %s)" my/emacs-agent-runtime-elpaca-repo)
                                ""))
              :fix "M-x elpaca-fetch emacs-agent-runtime, then M-x elpaca-merge emacs-agent-runtime and restart"))))
     (t
      (list :status :warn
            :detail (format "unknown or unset source mode: %S" source)
            :fix "Customize my/emacs-agent-runtime-source to local or elpaca")))))

(my/doctor-define-check "EAR runtime loaded"
  (cond
   ((featurep 'emacs-agent-runtime)
    (list :status :ok
          :detail (format "loaded%s"
                          (if (fboundp 'ear-list-tools)
                              (format ", tools=%d" (length (ear-list-tools)))
                            ""))))
   ((locate-library "emacs-agent-runtime")
    (list :status :warn
          :detail "emacs-agent-runtime is loadable but not loaded yet"
          :fix "restart Emacs or evaluate (my/emacs-agent-runtime-load)"))
   (t
    (list :status :fail
          :detail "emacs-agent-runtime is not on load-path"
          :fix "Check my/emacs-agent-runtime-source and my/emacs-agent-runtime-dir"))))

(my/doctor-define-check "EAR fresh-user package assets"
  (let* ((source (and (boundp 'my/emacs-agent-runtime-source)
                      my/emacs-agent-runtime-source))
         (local-dir (and (boundp 'my/emacs-agent-runtime-dir)
                         (stringp my/emacs-agent-runtime-dir)
                         (expand-file-name my/emacs-agent-runtime-dir)))
         (library-file (locate-library "emacs-agent-runtime"))
         (local-root (and local-dir
                          (file-directory-p local-dir)
                          (file-name-as-directory local-dir)))
         (library-root (and library-file
                            (file-name-directory library-file)))
         (root (cond
                ((eq source 'elpaca) library-root)
                ((eq source 'local) local-root)
                (local-root local-root)
                (library-root library-root)))
         (required
         '(("starter pack" . "packs/starter/manifest.org")
            ("starter knowledge" . "knowledge/starter-coaching.org")
            ("starter workflows" . "workflows/daily-gtd-coach.org")
            ("starter sessions" . "sessions/defaults.org")
            ("qmd retrieval pack" . "packs/qmd-retrieval/manifest.org")
            ("qmd retrieval knowledge" . "packs/qmd-retrieval/knowledge/qmd-retrieval.org")
            ("qmd retrieval workflows" . "packs/qmd-retrieval/workflows/qmd-retrieval.org")))
         missing)
    (if (not root)
        (list :status :fail
              :detail "EAR root not found; cannot verify reusable package assets"
              :fix "Check my/emacs-agent-runtime-source and my/emacs-agent-runtime-dir")
      (dolist (asset required)
        (unless (file-exists-p (expand-file-name (cdr asset) root))
          (push (car asset) missing)))
      (if missing
          (list :status :fail
                :detail (format "missing reusable assets under %s: %s"
                                root
                                (string-join (nreverse missing) ", "))
                :fix "Update the emacs-agent-runtime checkout/package and rerun M-x my/doctor")
        (list :status :ok
              :detail (format "starter assets and optional qmd-retrieval pack present under %s"
                              root))))))

(my/doctor-define-check "QMD optional retrieval CLI"
  (let* ((cmd (if (and (boundp 'my/emacs-agent-runtime-qmd-command)
                       (stringp my/emacs-agent-runtime-qmd-command))
                  my/emacs-agent-runtime-qmd-command
                "qmd"))
         (path (executable-find cmd))
         (install (when (fboundp 'my/emacs-agent-runtime-qmd-install-command)
                    (my/emacs-agent-runtime-qmd-install-command))))
    (cond
     (path
      (list :status :ok
            :detail (format "%s at %s" cmd path)))
     (t
      (list :status :warn
            :detail (format "%s not found; QMD retrieval remains unavailable" cmd)
            :fix (or install "M-x my/emacs-agent-runtime-qmd-install"))))))

(my/doctor-define-check "QMD install package manager"
  (let* ((manager (if (and (boundp 'my/emacs-agent-runtime-qmd-package-manager)
                           (symbolp my/emacs-agent-runtime-qmd-package-manager))
                      (symbol-name my/emacs-agent-runtime-qmd-package-manager)
                    "npm"))
         (path (executable-find manager)))
    (cond
     (path
      (list :status :ok :detail (format "%s at %s" manager path)))
     (t
      (list :status :warn
            :detail (format "%s not on exec-path; QMD install command cannot run yet"
                            manager)
            :fix (if (string= manager "bun")
                     "brew install bun"
                   "brew install node"))))))

(my/doctor-define-check "QMD projection directory"
  (let ((dir (and (boundp 'my/emacs-agent-runtime-qmd-projection-directory)
                  my/emacs-agent-runtime-qmd-projection-directory)))
    (cond
     ((not (stringp dir))
      (list :status :warn
            :detail "QMD projection directory is not configured"))
     ((file-directory-p dir)
      (list :status :ok :detail dir))
     ((file-directory-p (file-name-directory (directory-file-name dir)))
      (list :status :warn
            :detail (format "projection directory not created yet: %s" dir)
            :fix "Run qmd_projection_export only after reviewing qmd_projection_plan"))
     (t
      (list :status :warn
            :detail (format "projection parent missing: %s" dir)
            :fix "Check my/data-dir and my/emacs-agent-runtime-qmd-projection-directory")))))

(my/doctor-define-check "gh CLI authenticated"
  (cond
   ((not (fboundp 'my/gh-auth-status))
    (list :status :warn :detail "skipped — gh Layer 1 not loaded"))
   (t (let ((status (my/gh-auth-status)))
        (cond
         ((eq status :ok)
          (list :status :ok :detail "gh auth status returned :ok"))
         ((eq status :no-gh)
          (list :status :fail
                :detail "gh CLI not installed"
                :fix "brew install gh"))
         ((eq status :not-authenticated)
          (list :status :fail
                :detail "gh is installed but no user is logged in"
                :fix "M-x my/bootstrap (will use Keychain GitHubToken automatically) — or run: gh auth login"))
         (t (list :status :warn
                  :detail (format "unexpected gh-auth-status result: %S" status))))))))

(defun my/doctor--run-check (thunk)
  "Invoke THUNK and return its result. The thunk itself wraps in
condition-case (see `my/doctor-define-check'), so signalled errors
become (:status :fail :detail …) entries rather than propagating."
  (funcall thunk))

(defun my/doctor--status-glyph (status)
  "Return the leading glyph for STATUS."
  (cond ((eq status :ok)   "✓")
        ((eq status :warn) "⚠")
        ((eq status :fail) "✗")
        (t                  "?")))

(defun my/doctor--render (results)
  "Render RESULTS into the *Doctor* buffer and pop to it."
  (let ((buf (get-buffer-create "*Doctor*"))
        (ok    (cl-count :ok    results :key (lambda (r) (plist-get r :status))))
        (warn  (cl-count :warn  results :key (lambda (r) (plist-get r :status))))
        (fail  (cl-count :fail  results :key (lambda (r) (plist-get r :status)))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Emacs Doctor — %s\n" (format-time-string "%Y-%m-%d %H:%M")))
        (insert "================\n\n")
        (insert (format "Summary: %d OK · %d warnings · %d failures\n\n" ok warn fail))
        (dolist (r results)
          (insert (format "%s  %s"
                          (my/doctor--status-glyph (plist-get r :status))
                          (plist-get r :label)))
          (let ((detail (plist-get r :detail)))
            (when (and detail (not (string-empty-p detail)))
              (insert (format "  —  %s" detail))))
          (insert "\n")
          (let ((fix (plist-get r :fix)))
            (when fix
              (insert (format "       FIX:  %s\n" fix)))))
        (insert "\n")
        (insert (substitute-command-keys
                 "Re-run with `\\[my/doctor-rerun]'.  Set credentials with `M-x my/credential-set'.\n")))
      (read-only-mode 1)
      (goto-char (point-min)))
    (display-buffer buf '((display-buffer-pop-up-window)))))

(defun my/doctor ()
  "Run every registered health check and render *Doctor*."
  (interactive)
  (let ((results (mapcar #'my/doctor--run-check
                         (reverse my/doctor--checks))))
    (my/doctor--render results)
    ;; Explicit nil return so M-x echo area shows nothing instead of
    ;; the display-buffer's window object (`#<window 11 on *Doctor*>`).
    nil))

(defun my/doctor-rerun ()
  "Re-run the doctor in the currently displayed *Doctor* buffer."
  (interactive)
  (my/doctor))

(provide '90_doctor)
;;; 90_doctor.el ends here

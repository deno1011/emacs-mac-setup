;;; 65_messenger.el --- channel-agnostic message bridge -*- lexical-binding: t; -*-

(require 'subr-x)
(require 'json)

(declare-function messenger-bridge-start "messenger-bridge")
(declare-function messenger-bridge-stop "messenger-bridge")
(declare-function messenger-send "messenger-bridge")
(declare-function my/launchd-service-register "62_launchd_services" (service))
(declare-function my/launchd-services-launchctl "62_launchd_services" ())
(declare-function my/emacs-agent-runtime-private-adapters-root-directory
                  "60_emacs-agent-runtime" ())
(defvar messenger-bridge-directory)

(defvar my/messenger-autostart nil
  "When non-nil, start the legacy messenger bridge inbound watcher on load.

Keep this nil when the EAR scheduler job `messenger.bridge.listener' owns
inbound polling for the same bridge directory.")

(defun my/messenger--launchctl ()
  "Return launchctl executable for messenger service management."
  (if (fboundp 'my/launchd-services-launchctl)
      (my/launchd-services-launchctl)
    (or (and (file-executable-p "/bin/launchctl") "/bin/launchctl")
        (executable-find "launchctl")
        "launchctl")))

(when (not noninteractive)
  (use-package messenger-bridge
    :ensure (messenger-bridge
             :host github
             :repo "deno1011/emacs-messenger-bridge"
             :branch "main"
             :depth nil)
    :demand t
    :commands (messenger-send messenger-bridge-start messenger-bridge-stop)
    :config
    ;; messenger-bridge-directory defaults to ~/.emacs.d/messenger-bridge/.
    ;; The WhatsApp adapter's MESSENGER_BRIDGE_DIR must point at the same path.
    (when my/messenger-autostart
      (messenger-bridge-start))))

(defcustom my/whatsapp-adapter-dir
  (expand-file-name
   "whatsapp-bridge-adapter/"
   (my/emacs-agent-runtime-private-adapters-root-directory))
  "Private deployed checkout of the WhatsApp bridge adapter."
  :type 'directory
  :group 'emacs-agent-runtime)

(defvar my/whatsapp-adapter-node nil
  "Path to the node binary for the service; nil = auto-detect.")

(defun my/whatsapp-adapter--node ()
  "Best-effort path to a node binary."
  (or my/whatsapp-adapter-node
      (executable-find "node")
      (seq-find #'file-executable-p
                '("/opt/homebrew/opt/node/bin/node"
                  "/opt/homebrew/bin/node"
                  "/usr/local/bin/node"))
      "node"))

(defconst my/whatsapp-adapter--service-label "com.deno1011.whatsapp-bridge")
(defconst my/whatsapp-business-adapter--service-label
  "com.deno1011.whatsapp-business-bridge")
(defconst my/whatsapp-business-adapter--qr-image
  "/tmp/whatsapp-business-login-qr.png")

(defun my/whatsapp-adapter--status-file (channel)
  "Return the runtime status JSON path for WhatsApp CHANNEL."
  (expand-file-name
   (format "messenger-bridge/status/%s.json" channel)
   user-emacs-directory))

(defun my/whatsapp-adapter--runtime-status (channel)
  "Return the adapter runtime status alist for CHANNEL, or nil."
  (let ((file (my/whatsapp-adapter--status-file channel)))
    (when (file-readable-p file)
      (cond
       ((fboundp 'json-parse-file)
        (json-parse-file file :object-type 'alist :array-type 'list
                         :null-object nil :false-object nil))
       ((fboundp 'json-read-file)
        (let ((json-object-type 'alist)
              (json-array-type 'list)
              (json-false nil)
              (json-null nil))
          (json-read-file file)))))))

(defun my/whatsapp-adapter-install-service ()
  "Generate and (re)load a launchd service for the WhatsApp bridge adapter.
Writes ~/Library/LaunchAgents/<label>.plist with the detected node binary and
`my/whatsapp-adapter-dir', then reloads it.  Requires the adapter cloned and
QR-linked (auth/ present)."
  (interactive)
  (unless (eq system-type 'darwin) (user-error "macOS only"))
  (let* ((dir (expand-file-name my/whatsapp-adapter-dir))
         (entrypoint (expand-file-name "index.js" dir))
         (node (my/whatsapp-adapter--node))
         (plist (expand-file-name
                 (format "Library/LaunchAgents/%s.plist"
                         my/whatsapp-adapter--service-label)
                 "~")))
    (unless (file-directory-p dir)
      (user-error "Adapter not found at %s — clone it first" dir))
    (unless (file-directory-p (expand-file-name "auth" dir))
      (user-error "Not QR-linked yet (no auth/) — run `node index.js' and scan the QR first"))
    (make-directory (file-name-directory plist) t)
    (with-temp-file plist
      (insert (format "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\"
  \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>Label</key><string>%s</string>
  <key>ProgramArguments</key>
  <array><string>%s</string><string>%s</string></array>
  <key>WorkingDirectory</key><string>%s</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/whatsapp-bridge.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/whatsapp-bridge.err.log</string>
</dict>
</plist>
" my/whatsapp-adapter--service-label node entrypoint dir)))
    (ignore-errors (call-process (my/messenger--launchctl)
                                 nil nil nil "unload" plist))
    (if (zerop (call-process (my/messenger--launchctl)
                             nil nil nil "load" plist))
        (message "WhatsApp adapter service loaded: %s" plist)
      (user-error "launchctl load failed for %s" plist))))

(defun my/whatsapp-adapter-uninstall-service ()
  "Unload and remove the WhatsApp adapter launchd service."
  (interactive)
  (let ((plist (expand-file-name
                (format "Library/LaunchAgents/%s.plist"
                        my/whatsapp-adapter--service-label)
                "~")))
    (ignore-errors (call-process (my/messenger--launchctl)
                                 nil nil nil "unload" plist))
    (when (file-exists-p plist) (delete-file plist))
    (message "WhatsApp adapter service removed")))

(defcustom my/signal-adapter-dir
  (expand-file-name
   "signal-bridge-adapter/"
   (my/emacs-agent-runtime-private-adapters-root-directory))
  "Private deployed checkout of the Signal bridge adapter."
  :type 'directory
  :group 'emacs-agent-runtime)

(defun my/messenger--link-term (name dir command)
  "Run COMMAND in DIR inside an ansi-term buffer NAME so a login QR renders
in Emacs.  Prepends the detected node bin dir to PATH (Homebrew node is
keg-only and not on the login PATH), so node/npm resolve."
  (let ((dir (expand-file-name dir)))
    (unless (file-directory-p dir)
      (user-error "Adapter not installed: %s — clone it first" dir))
    (require 'term)
    (let* ((default-directory (file-name-as-directory dir))
           (shell (or (getenv "SHELL") "/bin/zsh"))
           (nodebin (let ((n (or (executable-find "node")
                                  (seq-find #'file-executable-p
                                            '("/opt/homebrew/opt/node/bin/node"
                                              "/opt/homebrew/bin/node"
                                              "/usr/local/bin/node")))))
                      (and n (directory-file-name (file-name-directory n)))))
           (full (format "%scd %s && %s"
                         (if nodebin
                             (format "export PATH=%s:$PATH; "
                                     (shell-quote-argument nodebin))
                           "")
                         (shell-quote-argument dir) command))
           (bufname (format "*%s*" name)))
      (when (get-buffer bufname)
        (let ((kill-buffer-query-functions nil)) (kill-buffer bufname)))
      (let ((buf (make-term name shell nil "-lc" full)))
        (with-current-buffer buf (term-mode) (term-char-mode))
        (switch-to-buffer buf)
        (message "Scan the QR shown in *%s*; close the buffer when linked" name)
        buf))))

(defun my/whatsapp-adapter--registered-p ()
  "Return non-nil if the WhatsApp adapter auth store is fully registered."
  (let ((creds (expand-file-name "auth/creds.json" my/whatsapp-adapter-dir)))
    (when (file-readable-p creds)
      (with-temp-buffer
        (insert-file-contents creds)
        (goto-char (point-min))
        (re-search-forward "\"registered\"[[:space:]]*:[[:space:]]*true" nil t)))))

(defun my/whatsapp-adapter-archive-auth ()
  "Archive the WhatsApp adapter auth directory before a fresh link attempt."
  (interactive)
  (let ((auth (expand-file-name "auth" my/whatsapp-adapter-dir)))
    (when (file-directory-p auth)
      (rename-file
       auth
       (expand-file-name
        (format "auth-stale-%s" (format-time-string "%Y%m%d-%H%M%S"))
        my/whatsapp-adapter-dir)
       t))
    (make-directory auth t)
    (message "WhatsApp adapter auth archived; fresh auth/ created")))

(defun my/whatsapp-adapter--prepare-fresh-link ()
  "Archive incomplete WhatsApp auth before an interactive link command."
  (let ((creds (expand-file-name "auth/creds.json" my/whatsapp-adapter-dir)))
    (when (and (file-exists-p creds)
               (not (my/whatsapp-adapter--registered-p)))
      (my/whatsapp-adapter-archive-auth))))

(defun my/whatsapp-adapter-link ()
  "Open a terminal buffer running the WhatsApp adapter so its login QR
renders in Emacs.  Scan it in WhatsApp > Linked Devices (use a SECONDARY
number).  Stop the launchd service first if running; delete auth/ to force a
fresh QR when re-linking (an already-linked adapter shows no QR)."
  (interactive)
  (my/whatsapp-adapter--prepare-fresh-link)
  (my/messenger--link-term "whatsapp-link" my/whatsapp-adapter-dir
                           "exec npm start"))

(defun my/whatsapp-adapter-link-debug ()
  "Open the WhatsApp adapter link terminal with verbose Baileys diagnostics."
  (interactive)
  (my/whatsapp-adapter--prepare-fresh-link)
  (my/messenger--link-term
   "whatsapp-link-debug" my/whatsapp-adapter-dir
   "WA_DEBUG=1 WA_LOG_LEVEL=debug exec npm start"))

(defun my/whatsapp-adapter--default-phone ()
  "Return the first phone-like JID from the WhatsApp adapter .env file."
  (let ((env-file (expand-file-name ".env" my/whatsapp-adapter-dir))
        (found nil))
    (when (file-readable-p env-file)
      (with-temp-buffer
        (insert-file-contents env-file)
        (goto-char (point-min))
        (when (re-search-forward "^WA_ALLOWED_JIDS=\\([^,\n]+\\)" nil t)
          (setq found
                (replace-regexp-in-string
                 "[^0-9]" "" (match-string 1))))))
    (when (and found (> (length found) 0))
      found)))

(defun my/whatsapp-adapter-link-pairing-code (phone)
  "Open WhatsApp adapter login using a phone-number pairing code.
PHONE must include the country code.  Punctuation and spaces are ignored."
  (interactive
   (list (read-string "WhatsApp phone with country code: "
                      (my/whatsapp-adapter--default-phone))))
  (let ((digits (replace-regexp-in-string "[^0-9]" "" phone)))
    (unless (string-match-p "\\`[0-9]+\\'" digits)
      (user-error "Phone number must contain digits"))
    (my/whatsapp-adapter--prepare-fresh-link)
    (my/messenger--link-term
     "whatsapp-link-pairing" my/whatsapp-adapter-dir
     (format "WA_DEBUG=1 WA_LOG_LEVEL=debug WA_PAIRING_PHONE=%s exec npm start"
             (shell-quote-argument digits)))))

(defun my/whatsapp-adapter--registered-auth-p (auth-dir)
  "Return non-nil when AUTH-DIR contains registered Baileys credentials."
  (let ((creds (expand-file-name "creds.json" auth-dir)))
    (when (file-readable-p creds)
      (with-temp-buffer
        (insert-file-contents creds)
        (goto-char (point-min))
        (re-search-forward "\"registered\"[[:space:]]*:[[:space:]]*true" nil t)))))

(defun my/whatsapp-adapter--usable-auth-p (auth-dir)
  "Return non-nil when AUTH-DIR contains credentials that can reconnect.

Baileys v7/WhatsApp Business can persist `registered=false' even after a
successful Business link.  Treat a saved self identity plus account sync as
usable auth instead of archiving it as half-created QR state."
  (let ((creds (expand-file-name "creds.json" auth-dir)))
    (when (file-readable-p creds)
      (with-temp-buffer
        (insert-file-contents creds)
        (or (progn
              (goto-char (point-min))
              (re-search-forward "\"registered\"[[:space:]]*:[[:space:]]*true" nil t))
            (and (progn
                   (goto-char (point-min))
                   (re-search-forward "\"me\"[[:space:]]*:" nil t))
                 (progn
                   (goto-char (point-min))
                   (re-search-forward "\"lastAccountSyncTimestamp\"[[:space:]]*:" nil t))))))))

(defun my/whatsapp-business-adapter--prepare-fresh-link ()
  "Archive incomplete WhatsApp Business auth before an interactive link command."
  (let* ((auth (expand-file-name "auth-business" my/whatsapp-adapter-dir))
         (creds (expand-file-name "creds.json" auth)))
    (when (and (file-exists-p creds)
               (not (my/whatsapp-adapter--usable-auth-p auth)))
      (rename-file
       auth
       (expand-file-name
        (format "auth-business-stale-%s" (format-time-string "%Y%m%d-%H%M%S"))
        my/whatsapp-adapter-dir)
       t)
      (make-directory auth t)
      (message "WhatsApp Business adapter auth archived; fresh auth-business/ created"))))

(defun my/whatsapp-business-adapter--stop-link-processes ()
  "Stop interactive WhatsApp Business link processes that share auth-business/."
  (dolist (bufname '("*whatsapp-business-link*" "*whatsapp-business-link-debug*"
                     "*whatsapp-business-link-pairing*"))
    (let ((proc (get-buffer-process bufname)))
      (when proc (delete-process proc)))))

(defun my/whatsapp-business-adapter-open-qr-image ()
  "Open the latest WhatsApp Business login QR PNG, when the adapter wrote it."
  (interactive)
  (if (file-readable-p my/whatsapp-business-adapter--qr-image)
      (find-file-other-window my/whatsapp-business-adapter--qr-image)
    (message "No QR image yet at %s; wait a moment and retry"
             my/whatsapp-business-adapter--qr-image)))

(defun my/whatsapp-business-adapter--open-qr-image-soon ()
  "Open the WhatsApp Business QR PNG shortly after the adapter starts."
  (run-at-time
   2 nil
   (lambda ()
     (when (file-readable-p my/whatsapp-business-adapter--qr-image)
       (find-file-other-window my/whatsapp-business-adapter--qr-image)))))

(defun my/whatsapp-business-adapter--env-command (&optional extra-env)
  "Return shell command for the secondary WhatsApp Business adapter.
EXTRA-ENV is a shell fragment prepended to the command."
  (string-join
   (delq nil
         (list
          "MESSENGER_BRIDGE_DIR=/Users/denisbutic/.emacs.d/messenger-bridge"
          "WA_AUTH_DIR=./auth-business"
          "WA_CHANNEL_ID=whatsapp-business"
          "WA_RELAY_MODE=allowlist"
          "WA_ALLOWED_JIDS=4917625546460@s.whatsapp.net,15900103164007@lid"
          "WA_EXPORT_CONTACTS=true"
          (format "WA_QR_IMAGE_PATH=%s"
                  (shell-quote-argument my/whatsapp-business-adapter--qr-image))
          extra-env
          "exec npm start"))
   " "))

(defun my/whatsapp-business-adapter-link ()
  "Open the secondary WhatsApp Business adapter so its login QR renders in Emacs.
Scan it in the WhatsApp Business app for the secondary number.  This uses
auth-business/ and channel id whatsapp-business, leaving the primary adapter
untouched."
  (interactive)
  (my/whatsapp-business-adapter--stop-link-processes)
  (my/whatsapp-business-adapter--prepare-fresh-link)
  (my/messenger--link-term
   "whatsapp-business-link" my/whatsapp-adapter-dir
   (my/whatsapp-business-adapter--env-command))
  (my/whatsapp-business-adapter--open-qr-image-soon))

(defun my/whatsapp-business-adapter-link-debug ()
  "Open the secondary WhatsApp Business adapter link terminal with diagnostics."
  (interactive)
  (my/whatsapp-business-adapter--stop-link-processes)
  (my/whatsapp-business-adapter--prepare-fresh-link)
  (my/messenger--link-term
   "whatsapp-business-link-debug" my/whatsapp-adapter-dir
   (my/whatsapp-business-adapter--env-command
    "WA_DEBUG=1 WA_LOG_LEVEL=debug"))
  (my/whatsapp-business-adapter--open-qr-image-soon))

(defun my/whatsapp-business-adapter-link-pairing-code (phone)
  "Open secondary WhatsApp Business login using a phone-number pairing code.
PHONE must include the country code.  Punctuation and spaces are ignored."
  (interactive "sWhatsApp Business phone with country code: ")
  (let ((digits (replace-regexp-in-string "[^0-9]" "" phone)))
    (unless (string-match-p "\\`[0-9]+\\'" digits)
      (user-error "Phone number must contain digits"))
    (my/whatsapp-business-adapter--stop-link-processes)
    (my/whatsapp-business-adapter--prepare-fresh-link)
    (my/messenger--link-term
     "whatsapp-business-link-pairing" my/whatsapp-adapter-dir
     (my/whatsapp-business-adapter--env-command
      (format "WA_DEBUG=1 WA_LOG_LEVEL=debug WA_PAIRING_PHONE=%s"
              (shell-quote-argument digits))))))

(defun my/whatsapp-business-adapter-install-service ()
  "Generate and load a launchd service for the secondary WhatsApp Business adapter.
Requires auth-business/ to contain usable credentials from a prior QR or
pairing-code login."
  (interactive)
  (unless (eq system-type 'darwin) (user-error "macOS only"))
  (let* ((dir (expand-file-name my/whatsapp-adapter-dir))
         (auth (expand-file-name "auth-business" dir))
         (entrypoint (expand-file-name "index.js" dir))
         (node (my/whatsapp-adapter--node))
         (plist (expand-file-name
                 (format "Library/LaunchAgents/%s.plist"
                         my/whatsapp-business-adapter--service-label)
                 "~")))
    (unless (file-directory-p dir)
      (user-error "Adapter not found at %s — clone it first" dir))
    (unless (my/whatsapp-adapter--usable-auth-p auth)
      (user-error "Not QR-linked yet (no usable auth-business/creds.json) — run M-x my/whatsapp-business-adapter-link first"))
    (make-directory (file-name-directory plist) t)
    (with-temp-file plist
      (insert (format "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\"
  \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>Label</key><string>%s</string>
  <key>ProgramArguments</key>
  <array><string>%s</string><string>%s</string></array>
  <key>WorkingDirectory</key><string>%s</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>MESSENGER_BRIDGE_DIR</key><string>/Users/denisbutic/.emacs.d/messenger-bridge</string>
    <key>WA_AUTH_DIR</key><string>./auth-business</string>
    <key>WA_CHANNEL_ID</key><string>whatsapp-business</string>
    <key>WA_RELAY_MODE</key><string>allowlist</string>
    <key>WA_ALLOWED_JIDS</key><string>4917625546460@s.whatsapp.net,15900103164007@lid</string>
    <key>WA_EXPORT_CONTACTS</key><string>true</string>
    <key>WA_BROWSER</key><string>macos-chrome</string>
    <key>WA_QR_IMAGE_PATH</key><string>/tmp/whatsapp-business-login-qr.png</string>
    <key>WA_POLL_MS</key><string>500</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/whatsapp-business-bridge.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/whatsapp-business-bridge.err.log</string>
</dict>
</plist>
" my/whatsapp-business-adapter--service-label node entrypoint dir)))
    (ignore-errors (call-process (my/messenger--launchctl)
                                 nil nil nil "unload" plist))
    (if (zerop (call-process (my/messenger--launchctl)
                             nil nil nil "load" plist))
        (message "WhatsApp Business adapter service loaded: %s" plist)
      (user-error "launchctl load failed for %s" plist))))

(defun my/whatsapp-business-adapter-uninstall-service ()
  "Unload and remove the secondary WhatsApp Business adapter launchd service."
  (interactive)
  (let ((plist (expand-file-name
                (format "Library/LaunchAgents/%s.plist"
                        my/whatsapp-business-adapter--service-label)
                "~")))
    (ignore-errors (call-process (my/messenger--launchctl)
                                 nil nil nil "unload" plist))
    (when (file-exists-p plist) (delete-file plist))
    (message "WhatsApp Business adapter service removed")))

(defun my/signal-adapter-link ()
  "Open a terminal buffer running `npm run link' for the Signal adapter so
its device-link QR renders in Emacs.  Scan it in Signal > Settings > Linked
Devices > Link New Device.  Links as a SECONDARY device (no new number)."
  (interactive)
  (my/messenger--link-term "signal-link" my/signal-adapter-dir
                           "exec npm run link"))

(defconst my/signal-adapter--service-label "com.deno1011.signal-bridge")

(defun my/signal-adapter--signal-cli ()
  "Best-effort path to a signal-cli binary."
  (or (executable-find "signal-cli")
      (seq-find #'file-executable-p
                '("/opt/homebrew/bin/signal-cli"
                  "/usr/local/bin/signal-cli"
                  "/usr/bin/signal-cli"))))

(defun my/signal-adapter--configured-p ()
  "Return non-nil when the Signal adapter has a usable local config."
  (let ((env-file (expand-file-name ".env" my/signal-adapter-dir)))
    (when (file-readable-p env-file)
      (with-temp-buffer
        (insert-file-contents env-file)
        (goto-char (point-min))
        (re-search-forward
         "^SIGNAL_ACCOUNT=[[:space:]]*[^#[:space:]].*$" nil t)))))

(defun my/signal-adapter-install-service ()
  "Generate and (re)load a launchd service for the Signal bridge adapter.
Writes ~/Library/LaunchAgents/<label>.plist with the detected node binary and
`my/signal-adapter-dir', then reloads it.  Requires the adapter cloned, deps
installed, signal-cli linked (=M-x my/signal-adapter-link=) and SIGNAL_ACCOUNT
set in .env."
  (interactive)
  (unless (eq system-type 'darwin) (user-error "macOS only"))
  (let* ((dir (expand-file-name my/signal-adapter-dir))
         (entrypoint (expand-file-name "index.js" dir))
         (node (or (executable-find "node")
                   (seq-find #'file-executable-p
                             '("/opt/homebrew/opt/node/bin/node"
                               "/opt/homebrew/bin/node"
                               "/usr/local/bin/node"))
                   "node"))
         (signal-cli (my/signal-adapter--signal-cli))
         (plist (expand-file-name
                 (format "Library/LaunchAgents/%s.plist"
                         my/signal-adapter--service-label)
                 "~"))
         ;; launchd has a minimal PATH; the adapter spawns signal-cli by name,
         ;; so bake a PATH (node + signal-cli dirs + standard) into the plist.
         (path (mapconcat
                #'identity
                (delete-dups
                 (append
                  (list (directory-file-name (file-name-directory node)))
                  (let ((s signal-cli))
                    (and s (list (directory-file-name (file-name-directory s)))))
                  '("/opt/homebrew/bin" "/usr/local/bin" "/usr/bin" "/bin")))
                ":")))
    (unless (file-directory-p dir)
      (user-error "Adapter not found at %s — clone it first" dir))
    (unless signal-cli
      (user-error "signal-cli not found — `brew install signal-cli', then link"))
    (make-directory (file-name-directory plist) t)
    (with-temp-file plist
      (insert (format "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\"
  \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>Label</key><string>%s</string>
  <key>ProgramArguments</key>
  <array><string>%s</string><string>%s</string></array>
  <key>WorkingDirectory</key><string>%s</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>%s</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/signal-bridge.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/signal-bridge.err.log</string>
</dict>
</plist>
" my/signal-adapter--service-label node entrypoint dir path)))
    (ignore-errors (call-process (my/messenger--launchctl)
                                 nil nil nil "unload" plist))
    (if (zerop (call-process (my/messenger--launchctl)
                             nil nil nil "load" plist))
        (message "Signal adapter service loaded: %s" plist)
      (user-error "launchctl load failed for %s" plist))))

(defun my/signal-adapter-uninstall-service ()
  "Unload and remove the Signal adapter launchd service."
  (interactive)
  (let ((plist (expand-file-name
                (format "Library/LaunchAgents/%s.plist"
                        my/signal-adapter--service-label)
                "~")))
    (ignore-errors (call-process (my/messenger--launchctl)
                                 nil nil nil "unload" plist))
    (when (file-exists-p plist) (delete-file plist))
    (message "Signal adapter service removed")))

(defun my/messenger-register-launchd-services ()
  "Register messenger adapter launchd services for startup self-healing."
  (when (fboundp 'my/launchd-service-register)
    (my/launchd-service-register
     (list
      :label my/whatsapp-adapter--service-label
      :name "WhatsApp bridge adapter"
      :plist (expand-file-name
              (format "Library/LaunchAgents/%s.plist"
                      my/whatsapp-adapter--service-label)
              "~")
      :install-function #'my/whatsapp-adapter-install-service
      :ready
      (lambda (_service)
        (let* ((dir (expand-file-name my/whatsapp-adapter-dir))
               (auth (expand-file-name "auth" dir)))
          (cond
           ((not (file-directory-p dir))
            (format "adapter not cloned at %s" dir))
           ((not (my/whatsapp-adapter--usable-auth-p auth))
            "WhatsApp not linked yet; run M-x my/whatsapp-adapter-link")
           (t t))))))
    (my/launchd-service-register
     (list
      :label my/whatsapp-business-adapter--service-label
      :name "WhatsApp Business bridge adapter"
      :plist (expand-file-name
              (format "Library/LaunchAgents/%s.plist"
                      my/whatsapp-business-adapter--service-label)
              "~")
      :install-function #'my/whatsapp-business-adapter-install-service
      :ready
      (lambda (_service)
        (let* ((dir (expand-file-name my/whatsapp-adapter-dir))
               (auth (expand-file-name "auth-business" dir)))
          (cond
           ((not (file-directory-p dir))
            (format "adapter not cloned at %s" dir))
           ((not (my/whatsapp-adapter--usable-auth-p auth))
            "WhatsApp Business not linked yet; run M-x my/whatsapp-business-adapter-link")
           (t t))))))
    (my/launchd-service-register
     (list
      :label my/signal-adapter--service-label
      :name "Signal bridge adapter"
      :plist (expand-file-name
              (format "Library/LaunchAgents/%s.plist"
                      my/signal-adapter--service-label)
              "~")
      :install-function #'my/signal-adapter-install-service
      :ready
      (lambda (_service)
        (let ((dir (expand-file-name my/signal-adapter-dir)))
          (cond
           ((not (file-directory-p dir))
            (format "adapter not cloned at %s" dir))
           ((not (my/signal-adapter--signal-cli))
            "signal-cli missing; run brew install signal-cli")
           ((not (my/signal-adapter--configured-p))
            "Signal .env missing SIGNAL_ACCOUNT; run M-x my/signal-adapter-link and configure .env")
           (t t))))))))

(my/messenger-register-launchd-services)

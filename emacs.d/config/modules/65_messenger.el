;;; 65_messenger.el --- channel-agnostic message bridge -*- lexical-binding: t; -*-

(declare-function messenger-bridge-start "messenger-bridge")
(declare-function messenger-bridge-stop "messenger-bridge")
(declare-function messenger-send "messenger-bridge")
(defvar messenger-bridge-directory)

(defvar my/messenger-autostart t
  "When non-nil, start the messenger bridge automatically on load.")

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

(defvar my/whatsapp-adapter-dir (expand-file-name "~/whatsapp-bridge-adapter")
  "Local clone of the WhatsApp bridge adapter.")

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

(defun my/whatsapp-adapter-install-service ()
  "Generate and (re)load a launchd service for the WhatsApp bridge adapter.
Writes ~/Library/LaunchAgents/<label>.plist with the detected node binary and
`my/whatsapp-adapter-dir', then reloads it.  Requires the adapter cloned and
QR-linked (auth/ present)."
  (interactive)
  (unless (eq system-type 'darwin) (user-error "macOS only"))
  (let* ((dir (expand-file-name my/whatsapp-adapter-dir))
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
  <array><string>%s</string><string>%s/index.js</string></array>
  <key>WorkingDirectory</key><string>%s</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/whatsapp-bridge.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/whatsapp-bridge.err.log</string>
</dict>
</plist>
" my/whatsapp-adapter--service-label node dir dir)))
    (ignore-errors (call-process "launchctl" nil nil nil "unload" plist))
    (if (zerop (call-process "launchctl" nil nil nil "load" plist))
        (message "WhatsApp adapter service loaded: %s" plist)
      (user-error "launchctl load failed for %s" plist))))

(defun my/whatsapp-adapter-uninstall-service ()
  "Unload and remove the WhatsApp adapter launchd service."
  (interactive)
  (let ((plist (expand-file-name
                (format "Library/LaunchAgents/%s.plist"
                        my/whatsapp-adapter--service-label)
                "~")))
    (ignore-errors (call-process "launchctl" nil nil nil "unload" plist))
    (when (file-exists-p plist) (delete-file plist))
    (message "WhatsApp adapter service removed")))

(defvar my/signal-adapter-dir (expand-file-name "~/signal-bridge-adapter")
  "Local clone of the Signal bridge adapter.")

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

(defun my/whatsapp-adapter-link ()
  "Open a terminal buffer running the WhatsApp adapter so its login QR
renders in Emacs.  Scan it in WhatsApp > Linked Devices (use a SECONDARY
number).  Stop the launchd service first if running; delete auth/ to force a
fresh QR when re-linking (an already-linked adapter shows no QR)."
  (interactive)
  (my/messenger--link-term "whatsapp-link" my/whatsapp-adapter-dir
                           "exec node index.js"))

(defun my/signal-adapter-link ()
  "Open a terminal buffer running `npm run link' for the Signal adapter so
its device-link QR renders in Emacs.  Scan it in Signal > Settings > Linked
Devices > Link New Device.  Links as a SECONDARY device (no new number)."
  (interactive)
  (my/messenger--link-term "signal-link" my/signal-adapter-dir
                           "exec npm run link"))

(defconst my/signal-adapter--service-label "com.deno1011.signal-bridge")

(defun my/signal-adapter-install-service ()
  "Generate and (re)load a launchd service for the Signal bridge adapter.
Writes ~/Library/LaunchAgents/<label>.plist with the detected node binary and
`my/signal-adapter-dir', then reloads it.  Requires the adapter cloned, deps
installed, signal-cli linked (=M-x my/signal-adapter-link=) and SIGNAL_ACCOUNT
set in .env."
  (interactive)
  (unless (eq system-type 'darwin) (user-error "macOS only"))
  (let* ((dir (expand-file-name my/signal-adapter-dir))
         (node (or (executable-find "node")
                   (seq-find #'file-executable-p
                             '("/opt/homebrew/opt/node/bin/node"
                               "/opt/homebrew/bin/node"
                               "/usr/local/bin/node"))
                   "node"))
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
                  (let ((s (executable-find "signal-cli")))
                    (and s (list (directory-file-name (file-name-directory s)))))
                  '("/opt/homebrew/bin" "/usr/local/bin" "/usr/bin" "/bin")))
                ":")))
    (unless (file-directory-p dir)
      (user-error "Adapter not found at %s — clone it first" dir))
    (unless (executable-find "signal-cli")
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
  <array><string>%s</string><string>%s/index.js</string></array>
  <key>WorkingDirectory</key><string>%s</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>%s</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/signal-bridge.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/signal-bridge.err.log</string>
</dict>
</plist>
" my/signal-adapter--service-label node dir dir path)))
    (ignore-errors (call-process "launchctl" nil nil nil "unload" plist))
    (if (zerop (call-process "launchctl" nil nil nil "load" plist))
        (message "Signal adapter service loaded: %s" plist)
      (user-error "launchctl load failed for %s" plist))))

(defun my/signal-adapter-uninstall-service ()
  "Unload and remove the Signal adapter launchd service."
  (interactive)
  (let ((plist (expand-file-name
                (format "Library/LaunchAgents/%s.plist"
                        my/signal-adapter--service-label)
                "~")))
    (ignore-errors (call-process "launchctl" nil nil nil "unload" plist))
    (when (file-exists-p plist) (delete-file plist))
    (message "Signal adapter service removed")))

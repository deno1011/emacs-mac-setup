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

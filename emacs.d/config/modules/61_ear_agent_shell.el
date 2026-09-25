;;; 61_ear_agent_shell.el --- Agent Shell client for EAR -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'cl-lib)
(require 'subr-x)

(defvar agent-shell-agent-configs)
(defvar agent-shell-preferred-agent-config)
(defvar agent-shell-show-welcome-message)
(defvar agent-shell-text-file-capabilities)
(defvar agent-shell-thought-process-expand-by-default)
(defvar agent-shell-tool-use-expand-by-default)
(defvar agent-shell-activity-group-expand-by-default)
(defvar agent-shell-session-restore-verbosity)
(defvar ear-session-open-function)
(defvar my/emacs-agent-runtime-dir)

(declare-function acp-make-client "acp" (&rest args))
(declare-function agent-shell "agent-shell" (&optional arg))
(declare-function agent-shell-make-agent-config "agent-shell" (&rest args))
(declare-function agent-shell-start "agent-shell" (&rest args))
(declare-function ear-session-launch-agent-ids
                  "ear-session-launch" (&optional runtime-id))
(declare-function ear-session-launch-base-agent-id
                  "ear-session-launch" (agent-id &optional session-id))
(declare-function ear-session-row "ear-session" (session-id))
(declare-function ear-sessions-list "ear-session" (&optional limit))
(declare-function my/emacs-agent-runtime-load "60_emacs-agent-runtime" ())

(defvar my/ear-agent-shell-selected-agent "system.godmode"
  "EAR agent profile selected for the next Agent Shell session.")

(defun my/ear-agent-shell-command ()
  "Return the EAR ACP server executable."
  (expand-file-name "bin/ear-acp" my/emacs-agent-runtime-dir))

(defun my/ear-agent-shell-make-client (buffer &optional agent-id)
  "Create a public ACP client for BUFFER and EAR AGENT-ID."
  (acp-make-client
   :command (my/ear-agent-shell-command)
   :command-params
   (list "--agent" (or agent-id my/ear-agent-shell-selected-agent))
   :context-buffer buffer))

(defun my/ear-agent-shell-make-config (&optional selected-agent-id)
  "Return an Agent Shell configuration for SELECTED-AGENT-ID."
  (let ((agent-id (or selected-agent-id
                      my/ear-agent-shell-selected-agent)))
    (agent-shell-make-agent-config
     :identifier (intern (format "ear-%s" agent-id))
     :mode-line-name (format "EAR %s" agent-id)
     :buffer-name (format "EAR %s" agent-id)
     :shell-prompt "EAR> "
     :shell-prompt-regexp "EAR> "
     :session-meta `((earAgentId . ,agent-id))
     :client-maker
     (lambda (buffer)
       (my/ear-agent-shell-make-client buffer agent-id))
     :install-instructions
     (format "EAR ACP executable missing: %s"
             (my/ear-agent-shell-command)))))

;;;###autoload
(defun ear (&optional agent-id)
  "Start a new Agent Shell session for EAR AGENT-ID."
  (interactive)
  (my/emacs-agent-runtime-load)
  (let* ((agents (and (fboundp 'ear-session-launch-agent-ids)
                      (ear-session-launch-agent-ids)))
         (selected
          (or agent-id
              (if agents
                  (completing-read "EAR agent: " agents nil t nil nil
                                   my/ear-agent-shell-selected-agent)
                my/ear-agent-shell-selected-agent))))
    (setq my/ear-agent-shell-selected-agent selected)
    (agent-shell-start
     :config (my/ear-agent-shell-make-config selected))))

;;;###autoload
(defun ear-attach (session-id)
  "Continue durable EAR SESSION-ID in Agent Shell."
  (interactive
   (list
    (let ((ids (mapcar (lambda (row) (plist-get row :id))
                       (ear-sessions-list 200))))
      (completing-read "EAR session: " ids nil t))))
  (my/emacs-agent-runtime-load)
  (let* ((row (ear-session-row session-id))
         (agent-id (or (and row
                            (ear-session-launch-base-agent-id
                             (plist-get row :agent-id) session-id))
                       my/ear-agent-shell-selected-agent))
         (my/ear-agent-shell-selected-agent agent-id))
    (agent-shell-start
     :config (my/ear-agent-shell-make-config agent-id)
     :session-id session-id)))

(use-package agent-shell
  :ensure t
  :demand t
  :init
  (setq agent-shell-show-welcome-message nil
        agent-shell-text-file-capabilities nil
        agent-shell-thought-process-expand-by-default nil
        agent-shell-tool-use-expand-by-default nil
        agent-shell-activity-group-expand-by-default nil
        agent-shell-session-restore-verbosity 'last)
  :config
  (add-to-list 'agent-shell-agent-configs
               #'my/ear-agent-shell-make-config)
  (when (boundp 'ear-session-open-function)
    (setq ear-session-open-function #'ear-attach)))

(provide '61_ear_agent_shell)

;;; 61_ear_agent_shell.el ends here

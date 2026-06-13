;;; 20.01.01_bootstrap-keychain.el --- Bootstrap Layer 1 Keychain primitives -*- lexical-binding: t -*-
;;
;; Public API (callable from any Layer-2 file):
;;   (my/keychain-get SERVICE ACCOUNT)            → string value, or nil
;;   (my/keychain-set SERVICE ACCOUNT VALUE)      → :ok or (:error MSG)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   (none)
;;
;; Depends on:
;;   external binary `security' (preinstalled on macOS).

(defun my/keychain-get (service account)
  "Return the password stored under SERVICE/ACCOUNT in the macOS Keychain.

Returns the value as a string when the entry exists, or nil
when no such entry is configured (or the `security' subprocess
itself failed). Empty values are normalised to nil.

This is a thin wrapper around
  security find-generic-password -s SERVICE -a ACCOUNT -w
with both arguments shell-quoted. Errors from the subprocess
(missing entry, permissions, no `security' binary) all collapse
into nil — Layer 2 is responsible for translating the nil into
an actionable (:error MSG) result for the user."
  (let* ((cmd (format "security find-generic-password -s %s -a %s -w 2>/dev/null"
                      (shell-quote-argument service)
                      (shell-quote-argument account)))
         (out (with-output-to-string
                (with-current-buffer standard-output
                  (call-process-shell-command cmd nil t))))
         (trimmed (string-trim out)))
    (if (string-empty-p trimmed) nil trimmed)))

(defun my/keychain-set (service account value)
  "Store VALUE in macOS Keychain under SERVICE / ACCOUNT.

Uses `security add-generic-password -U' which creates the
entry when absent and overwrites it when present, atomically
in one subprocess call. Returns :ok on success, (:error MSG)
where MSG carries security's combined stdout+stderr on
non-zero exit.

VALUE is passed in argv. macOS's `security' supports this; the
trade-off is that the process listing briefly shows VALUE.
Acceptable on a single-user Mac for an interactive setup
command; not appropriate for high-frequency or remote use."
  (let ((buf (generate-new-buffer " *my/keychain-set*")))
    (unwind-protect
        (let ((exit (call-process "security" nil buf nil
                                  "add-generic-password" "-U"
                                  "-s" service
                                  "-a" account
                                  "-w" value)))
          (if (zerop exit)
              :ok
            `(:error ,(with-current-buffer buf
                        (string-trim (buffer-string))))))
      (kill-buffer buf))))

(provide 'my-bootstrap-keychain)
;;; 20.01.01_bootstrap-keychain.el ends here

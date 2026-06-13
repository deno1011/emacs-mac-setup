;;; 20.01.03_bootstrap_gh.el --- Bootstrap Layer 1 gh CLI primitives -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer 2):
;;   (my/gh-auth-status)                → :ok / :not-authenticated /
;;                                          :no-gh / (:error MSG)
;;   (my/gh-auth-login-with-token TOK)  → :ok / (:error STDERR)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   (none)
;;
;; Depends on:
;;   external binary `gh' (Homebrew: `brew install gh').

(defun my/gh-auth-status ()
  "Return the gh CLI's current authentication state.

Result tags:
  :ok                — gh is on PATH and reports an active login
  :not-authenticated — gh runs but says no user is logged in
  :no-gh             — `gh' binary is not on PATH
  (:error MSG)       — gh ran but failed in a way the predicate
                       does not recognise; MSG is gh's combined output

Wraps `gh auth status' (exit 0 = authenticated, exit 1 + output
containing \"not logged\" = not authenticated, anything else =
opaque error). stdout and stderr are captured into a single
buffer because gh emits its status banner on stderr even on
success."
  (cond
   ((not (executable-find "gh")) :no-gh)
   (t
    (let ((buf (generate-new-buffer " *my/gh-auth-status*")))
      (unwind-protect
          (let ((exit (call-process "gh" nil buf nil "auth" "status")))
            (cond
             ((zerop exit) :ok)
             ((= exit 1)
              (let ((msg (with-current-buffer buf (buffer-string))))
                (if (string-match-p "not logged" msg)
                    :not-authenticated
                  `(:error ,(string-trim msg)))))
             (t `(:error ,(with-current-buffer buf
                            (string-trim (buffer-string)))))))
        (kill-buffer buf))))))

(defun my/gh-auth-login-with-token (token)
  "Authenticate the gh CLI with TOKEN.

Wraps `gh auth login --with-token' with TOKEN fed via stdin
through a temp file so it never appears in process listings or
shell history.

Returns :ok on success, (:error MSG) on non-zero exit. The
temp file is wiped via `unwind-protect' even on failure."
  (let ((stdin-tmp (make-temp-file "gh-token-"))
        (buf (generate-new-buffer " *my/gh-auth-login-with-token*")))
    (unwind-protect
        (progn
          (with-temp-file stdin-tmp (insert token))
          (let ((exit (call-process "gh" stdin-tmp buf nil
                                    "auth" "login" "--with-token")))
            (if (zerop exit)
                :ok
              `(:error ,(with-current-buffer buf
                          (string-trim (buffer-string)))))))
      (when (file-exists-p stdin-tmp) (delete-file stdin-tmp))
      (kill-buffer buf))))

(provide 'my-bootstrap-gh)
;;; 20.01.03_bootstrap_gh.el ends here

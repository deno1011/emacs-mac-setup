;;; 20.02.04_bootstrap-identity.el --- Bootstrap Layer 2 identity -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer 3):
;;   (my/identity-ensure-loaded)        → :done / :skip / (:error MSG)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/identity--service
;;   my/identity--account-fullname
;;   my/identity--account-email
;;   my/identity--account-token
;;   my/identity--ensure-git-config
;;   my/identity--ensure-gh-auth
;;
;; Depends on (Layer 1):
;;   my/keychain-get              ← 20.01.01_bootstrap-keychain
;;   my/git-config-get            ← 20.01.02_bootstrap-git
;;   my/git-config-set            ← 20.01.02_bootstrap-git
;;   my/gh-auth-status            ← 20.01.03_bootstrap-gh
;;   my/gh-auth-login-with-token  ← 20.01.03_bootstrap-gh

(declare-function my/keychain-get             "20.01.01_bootstrap-keychain")
(declare-function my/git-config-get           "20.01.02_bootstrap-git")
(declare-function my/git-config-set           "20.01.02_bootstrap-git")
(declare-function my/gh-auth-status           "20.01.03_bootstrap-gh")
(declare-function my/gh-auth-login-with-token "20.01.03_bootstrap-gh")

(defconst my/identity--service "emacs_credentials"
  "macOS Keychain service for bootstrap credentials.")

(defconst my/identity--account-fullname "GitHubFullname"
  "Keychain account holding the user's full name for git config.")

(defconst my/identity--account-email "GitHubEmail"
  "Keychain account holding the user's email for git config.")

(defconst my/identity--account-token "GitHubToken"
  "Keychain account holding the gh CLI PAT.")

(defun my/identity--ensure-git-config (config-name account)
  "Set the global git config CONFIG-NAME from Keychain ACCOUNT.

Reads `emacs_credentials/ACCOUNT'. If the Keychain value is nil
or empty the function does nothing and returns :skip — the user
has not configured it, leave git's existing value alone.

If the Keychain value already matches the current git config,
returns :skip. If it differs, writes via `my/git-config-set' and
returns :done on success, (:error MSG) on failure."
  (let ((wanted (my/keychain-get my/identity--service account)))
    (cond
     ((or (null wanted) (string-empty-p wanted)) :skip)
     ((equal (my/git-config-get config-name) wanted) :skip)
     (t (let ((r (my/git-config-set config-name wanted)))
          (cond
           ((eq r :ok) :done)
           (t `(:error ,(format "git config --global %s: %s"
                                config-name (cadr r))))))))))

(defun my/identity--ensure-gh-auth ()
  "Ensure gh CLI is authenticated.

Decision table:
  gh missing                    → (:error \"install gh\")
  gh authenticated              → :skip
  not authenticated + token set → gh auth login → :done / (:error)
  not authenticated + no token  → (:error \"set GitHubToken\")
  gh ran but opaque error       → (:error <stderr>)"
  (let ((status (my/gh-auth-status)))
    (cond
     ((eq status :no-gh)
      `(:error "gh CLI not installed.

FIX: brew install gh"))
     ((eq status :ok) :skip)
     ((eq status :not-authenticated)
      (let ((token (my/keychain-get my/identity--service
                                    my/identity--account-token)))
        (cond
         ((or (null token) (string-empty-p token))
          `(:error
            ,(format "gh CLI is installed but not authenticated, and \
no token is stored in Keychain.

FIX: security add-generic-password \\
       -s %s -a %s \\
       -w \"<gh_pat_xxx>\"

Then run M-x my/bootstrap."
                     my/identity--service
                     my/identity--account-token)))
         (t (let ((r (my/gh-auth-login-with-token token)))
              (cond
               ((eq r :ok) :done)
               (t `(:error ,(format "gh auth login --with-token failed: %s"
                                    (cadr r))))))))))
     (t `(:error ,(format "gh auth status returned %S" status))))))

(defun my/identity-ensure-loaded ()
  "Reconcile git config user.name/user.email and gh CLI auth with
the credentials in Keychain.

Runs three independent sub-steps:
  - git config user.name  from Keychain GitHubFullname
  - git config user.email from Keychain GitHubEmail
  - gh CLI auth           from Keychain GitHubToken

Each sub-step returns :done / :skip / (:error MSG). The
aggregate result is:
  :done         — at least one sub-step did real work, no errors
  :skip         — every sub-step was already up to date
  (:error MSG)  — at least one sub-step failed; MSG is a
                  semicolon-joined list of the sub-step messages

OPT step in the orchestrator: failure does not halt bootstrap.
Git commits without configured identity will prompt; magit
operations against private repos will prompt if gh auth is
absent. Both surface as concrete shell repair commands."
  (let* ((sub
          (list (cons "git user.name"
                      (my/identity--ensure-git-config
                       "user.name" my/identity--account-fullname))
                (cons "git user.email"
                      (my/identity--ensure-git-config
                       "user.email" my/identity--account-email))
                (cons "gh auth"
                      (my/identity--ensure-gh-auth))))
         (errors (seq-filter
                  (lambda (cell) (and (consp (cdr cell))
                                      (eq (car (cdr cell)) :error)))
                  sub))
         (done (seq-some
                (lambda (cell) (eq (cdr cell) :done))
                sub)))
    (cond
     (errors `(:error
               ,(mapconcat
                 (lambda (cell)
                   (format "%s: %s" (car cell) (cadr (cdr cell))))
                 errors
                 ";\n\n")))
     (done :done)
     (t :skip))))

(provide 'my-bootstrap-identity)
;;; 20.02.04_bootstrap-identity.el ends here

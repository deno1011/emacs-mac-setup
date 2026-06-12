;;; 20.02.02_bootstrap-repo-clone.el --- Bootstrap Layer 2 repo clone -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer 3):
;;   (my/repo-ensure-cloned)            → :done / :skip / (:error MSG)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/repo-ensure-cloned--url-matches-p
;;   my/repo-ensure-cloned--folder-has-content-p
;;   my/repo-ensure-cloned--do-clone
;;   my/repo-ensure-cloned--strip-token-from-remote
;;
;; Depends on (Layer 1):
;;   my/keychain-get        ← 20.01.01_bootstrap-keychain
;;   my/git-clone           ← 20.01.02_bootstrap-git
;;   my/git-remote-url      ← 20.01.02_bootstrap-git
;;   my/git-remote-set-url  ← 20.01.02_bootstrap-git
;;
;; Forward-declared variables (owned by Layer 3):
;;   my/data-dir            ← 20.03.01_bootstrap

(defvar my/data-dir)
(declare-function my/keychain-get        "20.01.01_bootstrap-keychain")
(declare-function my/git-clone           "20.01.02_bootstrap-git")
(declare-function my/git-remote-url      "20.01.02_bootstrap-git")
(declare-function my/git-remote-set-url  "20.01.02_bootstrap-git")

(defconst my/repo-ensure-cloned--service "emacs_credentials"
  "macOS Keychain service holding bootstrap credentials.")

(defconst my/repo-ensure-cloned--account-user "GitHubUsername"
  "Keychain account for the GitHub login used in the clone URL.")

(defconst my/repo-ensure-cloned--account-token "GitHubToken"
  "Keychain account for the GitHub PAT used to authenticate
the clone of private repositories. Optional.")

(defun my/repo-ensure-cloned--url-matches-p (actual expected)
  "Return t when ACTUAL equals EXPECTED, tolerating .git suffix.
Both arguments may be nil; the predicate returns nil in that case."
  (and actual expected
       (let ((bare (replace-regexp-in-string "\\.git\\'" "" expected)))
         (or (string= actual expected)
             (string= actual bare)))))

(defun my/repo-ensure-cloned--folder-has-content-p (dir)
  "Return t when DIR exists AND contains at least one non-dot entry.
nil when DIR is missing or empty (apart from `.' / `..')."
  (and (file-directory-p dir)
       (directory-files dir nil "\\`[^.]" t)
       t))

(defun my/repo-ensure-cloned--strip-token-from-remote (dir plain-url)
  "Reset DIR's origin remote to PLAIN-URL.
Failure is logged via `message' but does not turn the clone
result into an error — the clone itself succeeded, the
sanitisation is best-effort."
  (let ((result (my/git-remote-set-url dir plain-url)))
    (when (and (consp result) (eq (car result) :error))
      (message "my/repo-ensure-cloned: could not strip token from origin: %s"
               (cadr result)))))

(defun my/repo-ensure-cloned--do-clone (user repo plain-url)
  "Perform the clone of USER/REPO into `my/data-dir'.
PLAIN-URL is the canonical https URL. If a GitHubToken entry is
in the Keychain, build a token-bearing clone URL, clone, then
rewrite the remote back to PLAIN-URL via
`my/repo-ensure-cloned--strip-token-from-remote'."
  (let* ((token (my/keychain-get my/repo-ensure-cloned--service
                                 my/repo-ensure-cloned--account-token))
         (token? (and token (not (string-empty-p token))))
         (clone-url (if token?
                        (format "https://x-access-token:%s@github.com/%s/%s.git"
                                token user repo)
                      plain-url))
         (result (my/git-clone clone-url my/data-dir)))
    (cond
     ((eq result :ok)
      (when token?
        (my/repo-ensure-cloned--strip-token-from-remote my/data-dir plain-url))
      :done)
     ((and (consp result) (eq (car result) :error))
      `(:error
        ,(format "git clone failed: %s

FIX: review git's stderr above. For a private repo, store a
     personal access token in Keychain so the clone can authenticate:

     security add-generic-password \\
       -s %s -a %s \\
       -w \"<gh_pat_xxx>\""
                 (cadr result)
                 my/repo-ensure-cloned--service
                 my/repo-ensure-cloned--account-token)))
     (t
      `(:error ,(format "my/git-clone returned unexpected value: %S" result))))))

(defun my/repo-ensure-cloned ()
  "Ensure `my/data-dir' is a clone of the user's GitHub repository.

The repository name is taken from the last path segment of
`my/data-dir' (set by `my/data-dir-resolve' in the previous step).
The GitHub user comes from the Keychain account
`emacs_credentials/GitHubUsername'.

Idempotent: returns `:skip' when the folder already contains a
clone whose origin matches the expected URL. Returns `:done'
after a successful fresh clone. Returns `(:error MSG)' for
every reproducible failure (missing credential, conflicting
on-disk state, network failure, etc.) and carries a verbatim
shell command for the user to fix it.

Never overwrites existing files — folders with content but the
wrong origin (or no .git) require manual resolution."
  (cond
   ((not (stringp my/data-dir))
    `(:error ,(format "my/data-dir is not a string (%S). \
This step requires my/data-dir-resolve to have succeeded first."
                      my/data-dir)))
   (t
    (let ((user (my/keychain-get my/repo-ensure-cloned--service
                                 my/repo-ensure-cloned--account-user)))
      (cond
       ((null user)
        `(:error
          ,(format "Keychain entry %s/%s is missing.

FIX: security add-generic-password \\
       -s %s -a %s \\
       -w \"<github-login>\""
                   my/repo-ensure-cloned--service
                   my/repo-ensure-cloned--account-user
                   my/repo-ensure-cloned--service
                   my/repo-ensure-cloned--account-user)))
       ((string-empty-p user)
        `(:error
          ,(format "Keychain entry %s/%s exists but is empty.

FIX: security delete-generic-password -s %s -a %s
     security add-generic-password    -s %s -a %s -w \"<github-login>\""
                   my/repo-ensure-cloned--service
                   my/repo-ensure-cloned--account-user
                   my/repo-ensure-cloned--service
                   my/repo-ensure-cloned--account-user
                   my/repo-ensure-cloned--service
                   my/repo-ensure-cloned--account-user)))
       (t
        (let* ((repo (file-name-nondirectory (directory-file-name my/data-dir)))
               (expected-url (format "https://github.com/%s/%s.git" user repo))
               (dot-git (expand-file-name ".git" my/data-dir)))
          (cond
           ;; Already a clone with matching origin
           ((and (file-directory-p dot-git)
                 (my/repo-ensure-cloned--url-matches-p
                  (my/git-remote-url my/data-dir) expected-url))
            :skip)
           ;; Has .git but origin differs — refuse to touch
           ((file-directory-p dot-git)
            `(:error
              ,(format "Folder %s is a git repo but its origin
  %S
does not match the expected
  %S

FIX: inspect the folder, rename or remove it manually, then run
     M-x my/bootstrap to retry."
                       my/data-dir
                       (my/git-remote-url my/data-dir)
                       expected-url)))
           ;; Has content but no .git — refuse
           ((my/repo-ensure-cloned--folder-has-content-p my/data-dir)
            `(:error
              ,(format "Folder %s exists, contains files, and is not a git repo.

FIX: rename or remove %s manually, then run M-x my/bootstrap."
                       my/data-dir my/data-dir)))
           ;; Folder missing or empty — clone
           (t
            (my/repo-ensure-cloned--do-clone user repo expected-url))))))))))

(provide 'my-bootstrap-repo-clone)
;;; 20.02.02_bootstrap-repo-clone.el ends here

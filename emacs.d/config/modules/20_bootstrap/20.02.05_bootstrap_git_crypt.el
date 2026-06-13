;;; 20.02.05_bootstrap_git_crypt.el --- Bootstrap Layer 2 git-crypt -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer 3):
;;   (my/git-crypt-ensure-unlocked)               → :done / :skip / (:error MSG)
;;   (my/git-crypt-credential-descriptors)        → list of one descriptor (or nil)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/git-crypt-ensure-unlocked--service
;;   my/git-crypt-ensure-unlocked--account-for-repo
;;
;; Depends on (Layer 1):
;;   my/keychain-get                          ← 20.01.01_bootstrap_keychain
;;   my/git-crypt-installed-p                 ← 20.01.04_bootstrap_git_crypt
;;   my/git-crypt-repo-uses-encryption-p      ← 20.01.04_bootstrap_git_crypt
;;   my/git-crypt-repo-unlocked-p             ← 20.01.04_bootstrap_git_crypt
;;   my/git-crypt-unlock                      ← 20.01.04_bootstrap_git_crypt
;;
;; Forward-declared variables (owned by Layer 3):
;;   my/data-dir                              ← 20.03.01_bootstrap

(defvar my/data-dir)
(declare-function my/keychain-get                     "20.01.01_bootstrap_keychain")
(declare-function my/git-crypt-installed-p            "20.01.04_bootstrap_git_crypt")
(declare-function my/git-crypt-repo-uses-encryption-p "20.01.04_bootstrap_git_crypt")
(declare-function my/git-crypt-repo-unlocked-p        "20.01.04_bootstrap_git_crypt")
(declare-function my/git-crypt-unlock                 "20.01.04_bootstrap_git_crypt")

(defconst my/git-crypt-ensure-unlocked--service "emacs-git-crypt-key"
  "macOS Keychain service holding the per-repo git-crypt keys.

Separate from `emacs_credentials' (the service for everything
else) because the legacy bootstrap kept it that way and existing
installs already have keys under this name. Migrating them
would require user action with zero functional benefit; the
two-service split is contained inside this module and invisible
to feature modules.")

(defun my/git-crypt-ensure-unlocked--account-for-repo (dir)
  "Return the Keychain account name for the git-crypt key of repo at DIR.
Format: `GitCryptKey:<repo>' where repo is the last path segment
of DIR. Matches the schema the legacy bootstrap used."
  (concat "GitCryptKey:"
          (file-name-nondirectory (directory-file-name dir))))

(defun my/git-crypt-ensure-unlocked ()
  "Decrypt `my/data-dir' if it is a git-crypt repository.

Required step in the orchestrator only when the repo actually
opts into git-crypt. For non-encrypted repos this is a clean
:skip. See the decision table in this module's commentary for the
full set of paths."
  (cond
   ((not (stringp my/data-dir))
    '(:error "my/data-dir not resolved; this step needs step 1 (data-dir-resolve)"))
   ((not (file-directory-p (expand-file-name ".git" my/data-dir)))
    '(:error "data folder is not a git repo; this step needs step 2 (repo-ensure-cloned)"))
   ((not (my/git-crypt-repo-uses-encryption-p my/data-dir))
    :skip)
   ((my/git-crypt-repo-unlocked-p my/data-dir)
    :skip)
   ((not (my/git-crypt-installed-p))
    '(:error "Data repo uses git-crypt but the git-crypt binary is not installed.

FIX: brew install git-crypt
Then run M-x my/bootstrap."))
   (t
    (let* ((repo  (file-name-nondirectory (directory-file-name my/data-dir)))
           (acct  (my/git-crypt-ensure-unlocked--account-for-repo my/data-dir))
           (key   (my/keychain-get my/git-crypt-ensure-unlocked--service acct)))
      (cond
       ((or (null key) (string-empty-p key))
        `(:error
          ,(format "Repo %s uses git-crypt but no key is stored at
Keychain %s/%s.

If you have the keyfile on another machine:

  base64 < /path/to/keyfile | tr -d '\\n' | xargs -0 -I{} \\
    security add-generic-password \\
      -s %s -a '%s' -w '{}'

If you do NOT have the key, the encrypted files cannot be
recovered. Cloning the repo again will not help. See the
git-crypt docs on key management.

Then run M-x my/bootstrap."
                   repo
                   my/git-crypt-ensure-unlocked--service acct
                   my/git-crypt-ensure-unlocked--service acct)))
       (t
        (let ((result (my/git-crypt-unlock my/data-dir key)))
          (cond
           ((eq result :ok) :done)
           ((and (consp result) (eq (car result) :error))
            `(:error
              ,(format "git-crypt unlock failed: %s

The key at Keychain emacs_credentials/%s may be wrong or
corrupted. Re-add with the correct base64-encoded keyfile
content and run M-x my/bootstrap."
                       (cadr result) acct)))
           (t `(:error ,(format "my/git-crypt-unlock returned unexpected value: %S"
                                result)))))))))))

(defun my/git-crypt-credential-descriptors ()
  "Return descriptor plists for credentials this module owns.

One entry — the per-repo git-crypt key, allow-skip because most
users do not opt into git-crypt. Returns nil when `my/data-dir' is
still the `:not-resolved' sentinel; the descriptor cannot be
computed without a real repo name."
  (when (and (boundp 'my/data-dir) (stringp my/data-dir))
    (let* ((dir (file-name-as-directory my/data-dir))
           (acct (my/git-crypt-ensure-unlocked--account-for-repo dir)))
      (list (list :account acct
                  :service my/git-crypt-ensure-unlocked--service
                  :label (format "git-crypt key for %s (base64-encoded)"
                                 (file-name-nondirectory
                                  (directory-file-name dir)))
                  :secret t
                  :allow-skip t)))))

(provide 'my-bootstrap-git-crypt-domain)
;;; 20.02.05_bootstrap_git_crypt.el ends here

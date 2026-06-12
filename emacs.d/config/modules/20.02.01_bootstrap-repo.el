;;; 20.02.01_bootstrap-repo.el --- Bootstrap Layer 2 repo / data-dir -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer 3):
;;   (my/data-dir-resolve)                  → :done / :skip / (:error MSG)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/data-dir-resolve--build-path        ← helper: repo-name → absolute path
;;
;; Depends on (Layer 1):
;;   my/keychain-get                        ← 20.01.01_bootstrap-keychain
;;
;; Forward-declared variables (owned by Layer 3):
;;   my/data-dir                            ← 20.03.01_bootstrap

(defvar my/data-dir)
(declare-function my/keychain-get "20.01.01_bootstrap-keychain")

(defconst my/data-dir-resolve--keychain-service "emacs_credentials"
  "macOS Keychain service name for bootstrap credentials.")

(defconst my/data-dir-resolve--keychain-account "GitHubRepo"
  "macOS Keychain account name holding the data-folder repo name.")

(defun my/data-dir-resolve--build-path (repo)
  "Return the absolute data-folder path for REPO (the user-chosen
repo name like \"emacs\"). The folder lives directly under the
user's home directory."
  (file-name-as-directory (expand-file-name repo "~/")))

(defun my/data-dir-resolve ()
  "Resolve `my/data-dir' from the macOS Keychain.

Reads the Keychain entry SERVICE=`emacs_credentials' /
ACCOUNT=`GitHubRepo' (the user-chosen repo name), builds the
absolute data-folder path \"~/<repo>/\", and assigns it to the
Layer-3-owned variable `my/data-dir'.

Idempotent: when `my/data-dir' already equals the computed path,
returns `:skip' and does not write. When the value differs (a
fresh resolution or a repo-name change), returns `:done' after
the assignment.

Failure modes (no state mutation):
  - GitHubRepo entry missing in Keychain
  - GitHubRepo entry present but empty
Both surface as (:error MSG) carrying the exact `security'
command to add or rewrite the Keychain entry."
  (let ((repo (my/keychain-get my/data-dir-resolve--keychain-service
                               my/data-dir-resolve--keychain-account)))
    (cond
     ((null repo)
      `(:error
        ,(format
          "Keychain entry %s/%s is missing.\
\n\nFIX: security add-generic-password -s %s -a %s -w \"<repo-name>\""
          my/data-dir-resolve--keychain-service
          my/data-dir-resolve--keychain-account
          my/data-dir-resolve--keychain-service
          my/data-dir-resolve--keychain-account)))
     ((string-empty-p repo)
      `(:error
        ,(format
          "Keychain entry %s/%s exists but is empty.\
\n\nFIX: security delete-generic-password -s %s -a %s\
\n     security add-generic-password    -s %s -a %s -w \"<repo-name>\""
          my/data-dir-resolve--keychain-service
          my/data-dir-resolve--keychain-account
          my/data-dir-resolve--keychain-service
          my/data-dir-resolve--keychain-account
          my/data-dir-resolve--keychain-service
          my/data-dir-resolve--keychain-account)))
     (t
      (let ((path (my/data-dir-resolve--build-path repo)))
        (cond
         ((equal my/data-dir path) :skip)
         (t (setq my/data-dir path) :done)))))))

(provide 'my-bootstrap-repo)
;;; 20.02.01_bootstrap-repo.el ends here

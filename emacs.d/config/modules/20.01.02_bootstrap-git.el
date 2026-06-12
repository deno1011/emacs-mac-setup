;;; 20.01.02_bootstrap-git.el --- Bootstrap Layer 1 git primitives -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer 2):
;;   (my/git-clone URL DEST)            → :ok or (:error STDERR-STRING)
;;   (my/git-remote-url DIR)            → string URL, or nil
;;   (my/git-remote-set-url DIR URL)    → :ok or (:error STDERR-STRING)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   (none)
;;
;; Depends on:
;;   external binary `git' (typical macOS install via Xcode CLT or brew).

(defun my/git-clone (url dest)
  "Clone URL into DEST using `git clone'.

Returns :ok on success, or (:error STDERR-STRING) on failure
(non-zero exit). DEST must not exist or must be an empty
directory — git refuses otherwise. Caller is responsible for
making that determination."
  (let ((stderr-buf (generate-new-buffer " *my/git-clone stderr*")))
    (unwind-protect
        (let ((exit (call-process "git" nil (list nil stderr-buf) nil
                                  "clone" "--" url dest)))
          (if (zerop exit)
              :ok
            `(:error ,(with-current-buffer stderr-buf
                        (string-trim (buffer-string))))))
      (kill-buffer stderr-buf))))

(defun my/git-remote-url (dir)
  "Return the origin remote URL of the git repository at DIR.

Parses DIR/.git/config directly — no subprocess. Returns the
URL as a string when the [remote \"origin\"] section is present
with a `url' entry, otherwise nil.

Trimmed of surrounding whitespace; preserves any `.git' suffix
the URL carries on disk."
  (let ((cfg (expand-file-name ".git/config" dir)))
    (when (file-readable-p cfg)
      (with-temp-buffer
        (insert-file-contents cfg)
        (goto-char (point-min))
        (when (re-search-forward "^\\[remote \"origin\"\\]" nil t)
          (when (re-search-forward
                 "^[[:space:]]*url[[:space:]]*=[[:space:]]*\\(.*\\)$" nil t)
            (string-trim (match-string 1))))))))

(defun my/git-remote-set-url (dir url)
  "Set the origin remote of the git repo at DIR to URL.

Wraps `git -C DIR remote set-url origin URL'. Returns :ok on
success, (:error STDERR-STRING) on non-zero exit. Used by Layer 2
to strip a token from the clone URL after the initial clone
succeeded."
  (let ((stderr-buf (generate-new-buffer " *my/git-remote-set-url stderr*")))
    (unwind-protect
        (let ((exit (call-process "git" nil (list nil stderr-buf) nil
                                  "-C" dir "remote" "set-url" "origin" url)))
          (if (zerop exit)
              :ok
            `(:error ,(with-current-buffer stderr-buf
                        (string-trim (buffer-string))))))
      (kill-buffer stderr-buf))))

(provide 'my-bootstrap-git)
;;; 20.01.02_bootstrap-git.el ends here

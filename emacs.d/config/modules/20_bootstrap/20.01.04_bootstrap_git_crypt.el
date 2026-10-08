;;; 20.01.04_bootstrap_git_crypt.el --- Bootstrap Layer 1 git-crypt primitives -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer 2):
;;   (my/git-crypt-install)                 → :ok / (:error MSG)
;;   (my/git-crypt-installed-p)             → t / nil
;;   (my/git-crypt-repo-uses-encryption-p DIR) → t / nil
;;   (my/git-crypt-repo-unlocked-p DIR)     → t / nil
;;   (my/git-crypt-unlock DIR KEY-BASE64)   → :ok / (:error MSG)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   (none)
;;
;; Depends on:
;;   Homebrew (used to install git-crypt when needed)

(defun my/git-crypt-install ()
  "Install git-crypt with Homebrew when it is not already available.

Returns :ok when the executable is available, or (:error MSG) with
Homebrew output when installation fails. Handles launchd Emacs
processes whose PATH omits Homebrew's bin directory."
  (if (my/git-crypt-installed-p)
      :ok
    (let ((brew (or (executable-find "brew")
                    (and (file-executable-p "/opt/homebrew/bin/brew")
                         "/opt/homebrew/bin/brew")
                    (and (file-executable-p "/usr/local/bin/brew")
                         "/usr/local/bin/brew")))
          status output)
      (if (not brew)
          '(:error "Homebrew was not found; cannot install git-crypt automatically.")
        (let ((brew-bin (file-name-directory brew)))
          (let ((process-environment (copy-sequence process-environment))
                (exec-path (cons brew-bin exec-path)))
            (setenv "PATH" (concat brew-bin path-separator (getenv "PATH")))
            (setenv "NONINTERACTIVE" "1")
            (setenv "HOMEBREW_NO_AUTO_UPDATE" "1")
            (setenv "HOMEBREW_NO_INSTALL_CLEANUP" "1")
            (setenv "HOMEBREW_NO_ENV_HINTS" "1")
            (setenv "HOMEBREW_NO_ASK" "1")
            (message "Installing git-crypt with Homebrew…")
            (with-temp-buffer
              (setq status (call-process brew nil t t "install" "git-crypt")
                    output (string-trim (buffer-string)))))
          (if (and (integerp status) (= status 0))
              (progn
                (add-to-list 'exec-path brew-bin)
                (setenv "PATH" (concat brew-bin path-separator (getenv "PATH")))
                (if (my/git-crypt-installed-p)
                    :ok
                  `(:error ,(format "Homebrew finished, but git-crypt is still not on PATH.\n%s"
                                    output))))
            `(:error ,(format "Homebrew could not install git-crypt (exit %s).\n%s"
                              status output))))))))

(defun my/git-crypt-installed-p ()
  "Return t when the git-crypt binary is on PATH, nil otherwise."
  (and (executable-find "git-crypt") t))

(defun my/git-crypt-repo-uses-encryption-p (dir)
  "Return t when the git repository at DIR has git-crypt enabled.

Two signals are treated as positive:
  - `.git/git-crypt/' directory exists (set up by `git-crypt init'
    or `git-crypt unlock'; persists across both states)
  - `.gitattributes' contains a `filter=git-crypt' rule on at least
    one path

Either signal is enough. The function is read-only — does not
mutate DIR or look at the actual file contents."
  (or (file-directory-p (expand-file-name ".git/git-crypt" dir))
      (let ((attrs (expand-file-name ".gitattributes" dir)))
        (and (file-readable-p attrs)
             (with-temp-buffer
               (insert-file-contents attrs)
               (goto-char (point-min))
               (re-search-forward "filter=git-crypt" nil t))))))

(defun my/git-crypt-repo-unlocked-p (dir)
  "Return t when DIR's git-crypt is unlocked on this Mac.

`git-crypt unlock' writes the symmetric key into
`.git/git-crypt/keys/default'. Presence of that file is the
authoritative `we have decrypted files in the worktree' signal."
  (file-readable-p (expand-file-name ".git/git-crypt/keys/default" dir)))

(defun my/git-crypt-unlock (dir key-base64)
  "Unlock the git-crypt repository at DIR with KEY-BASE64.

KEY-BASE64 is a base64-encoded string (as stored in the macOS
Keychain). The function strips whitespace + newlines from the
base64 input (Keychain values come back with a trailing LF that
`base64-decode-string' rejects as invalid), decodes into a temp
file with mode 0600, shells out to `git-crypt unlock TEMPFILE'
from DIR, then wipes the temp file regardless of outcome.

Returns :ok on success, (:error MSG) on non-zero exit. MSG carries
git-crypt's combined stdout+stderr."
  (let ((keyfile (make-temp-file "git-crypt-key-"))
        ;; `base64-decode-string' is strict: rejects ANYTHING that is
        ;; not in the base64 alphabet `[A-Za-z0-9+/=]'. Real Keychain
        ;; values carry both LF and shell-prompt cruft — empirically
        ;; some legacy entries end in `==%' where the `%' is zsh's
        ;; "no trailing newline" indicator captured at store time by
        ;; an unattended pipeline. Strip everything outside the
        ;; alphabet rather than enumerate known offenders.
        (clean-b64 (replace-regexp-in-string "[^A-Za-z0-9+/=]+" ""
                                             (or key-base64 ""))))
    (unwind-protect
        (progn
          (let ((coding-system-for-write 'binary))
            (with-temp-file keyfile
              (set-buffer-multibyte nil)
              (insert (base64-decode-string clean-b64))))
          (let ((buf (generate-new-buffer " *my/git-crypt-unlock*")))
            (unwind-protect
                (let* ((default-directory (file-name-as-directory dir))
                       (exit (call-process "git-crypt" nil buf nil
                                           "unlock" keyfile)))
                  (if (zerop exit)
                      :ok
                    `(:error ,(with-current-buffer buf
                                (string-trim (buffer-string))))))
              (kill-buffer buf))))
      (when (file-exists-p keyfile)
        ;; Best-effort overwrite before delete; not a substitute for
        ;; full secure-erase but keeps the secret out of plain free
        ;; space for the common case.
        (ignore-errors
          (with-temp-file keyfile
            (insert (make-string 64 ?0))))
        (delete-file keyfile)))))

(provide 'my-bootstrap-git-crypt)
;;; 20.01.04_bootstrap_git_crypt.el ends here

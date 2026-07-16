;;; 66_fints_adapter.el --- FinTS adapter loader -*- lexical-binding: t; -*-

(require 'cl-lib)

;; Forward declarations for the byte-compiler (package loaded at runtime).
(defvar fints-bank-name)
(defvar fints-blz)
(defvar fints-server)
(defvar fints-product-id)
(defvar fints-user-account)
(defvar fints-pin-account)
(defvar fints-python)
(declare-function fints-balances "fints")
(declare-function fints-transfer "fints")

(defcustom my/fints-source 'elpaca
  "Where the FinTS adapter is loaded from.
`elpaca' installs it as a package from the private repo (needs git auth);
`local' loads a working checkout at `my/fints-local-dir'."
  :type '(choice (const :tag "Elpaca package" elpaca)
                 (const :tag "Local checkout" local))
  :group 'my/fints)

(defcustom my/fints-local-dir "~/emacs-fints-adapter"
  "Directory of a local emacs-fints-adapter checkout (when source is `local')."
  :type 'directory :group 'my/fints)

(defcustom my/fints-elpaca-repo "deno1011/emacs-fints-adapter"
  "GitHub repo used when the source is `elpaca' (private)."
  :type 'string :group 'my/fints)

(defcustom my/fints-elpaca-branch "main"
  "Git branch used when installing through Elpaca."
  :type 'string :group 'my/fints)

(defcustom my/fints-elpaca-files '("fints.el" "fints-helper.py")
  "Files pulled into the Elpaca build (the Elisp AND the Python helper)."
  :type '(repeat string) :group 'my/fints)

(defcustom my/fints-bank-name "comdirect"
  "Human-readable bank name (prompts/messages only)."
  :type 'string :group 'my/fints)

(defcustom my/fints-blz "20041144"
  "Bank code (Bankleitzahl)."
  :type 'string :group 'my/fints)

(defcustom my/fints-server "https://fints.comdirect.de/fints"
  "FinTS endpoint URL for the bank (verify the current value)."
  :type 'string :group 'my/fints)

(defcustom my/fints-product-id nil
  "Registered FinTS product id (mandatory, <= 25 chars).
Register free at https://www.hbci-zka.de/register/prod_register.htm and set it."
  :type '(choice (const :tag "Unset — register first" nil) string)
  :group 'my/fints)

(defcustom my/fints-user-account "COMDIRECT_FINTS_USER"
  "Keychain account name for the bank login."
  :type 'string :group 'my/fints)

(defcustom my/fints-pin-account "COMDIRECT_FINTS_PIN"
  "Keychain account name for the PIN."
  :type 'string :group 'my/fints)

(defcustom my/fints-python "/usr/bin/python3"
  "Python 3 interpreter with the `fints' package installed.
The system python is used by default because the Homebrew python is
externally-managed (PEP 668) and rejects a plain --user install."
  :type 'string :group 'my/fints)

(defun my/fints-apply-config ()
  "Push this module's bank settings into the loaded FinTS package."
  (dolist (pair `((fints-bank-name    . ,my/fints-bank-name)
                  (fints-blz          . ,my/fints-blz)
                  (fints-server       . ,my/fints-server)
                  (fints-product-id   . ,my/fints-product-id)
                  (fints-user-account . ,my/fints-user-account)
                  (fints-pin-account  . ,my/fints-pin-account)
                  (fints-python       . ,my/fints-python)))
    (when (boundp (car pair))
      (set (car pair) (cdr pair)))))

(defun my/fints-install-python-fints-command ()
  "Return the shell command that installs python-fints for `my/fints-python'."
  (format "%s -m pip install --user fints" (shell-quote-argument my/fints-python)))

;;;###autoload
(defun my/fints-install-python-fints ()
  "Install the `fints' Python package for `my/fints-python'."
  (interactive)
  (unless (executable-find my/fints-python)
    (user-error "Python interpreter not found: %s" my/fints-python))
  (compile (my/fints-install-python-fints-command)))

(defun my/fints-queue-elpaca ()
  "Load the FinTS adapter from a local checkout or queue it through Elpaca."
  (pcase my/fints-source
    ('local
     (let ((dir (expand-file-name my/fints-local-dir)))
       (when (file-directory-p dir)
         (add-to-list 'load-path dir)
         (when (require 'fints nil t)
           (my/fints-apply-config)))))
    ('elpaca
     (when (fboundp 'elpaca)
       (eval
        `(elpaca
           (fints
            :host github
            :repo ,my/fints-elpaca-repo
            :branch ,my/fints-elpaca-branch
            :files ,my/fints-elpaca-files)
           (require 'fints nil t)
           (my/fints-apply-config))
        t)
       (when (fboundp 'elpaca-wait) (elpaca-wait))))))

(my/fints-queue-elpaca)

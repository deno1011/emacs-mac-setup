;;; 66_comdirect_fints.el --- comdirect-fints loader -*- lexical-binding: t; -*-

(require 'cl-lib)

;; Forward declarations for the byte-compiler (package is loaded at runtime).
(defvar comdirect-fints-product-id)
(defvar comdirect-fints-server)
(defvar comdirect-fints-python)
(declare-function comdirect-fints-balances "comdirect-fints")
(declare-function comdirect-fints-transfer "comdirect-fints")

(defcustom my/comdirect-fints-source 'elpaca
  "Where comdirect-fints is loaded from.
`elpaca' installs and updates it as a package (default, for new users);
`local' loads a working checkout at `my/comdirect-fints-local-dir'."
  :type '(choice (const :tag "Elpaca package" elpaca)
                 (const :tag "Local checkout" local))
  :group 'my/comdirect-fints)

(defcustom my/comdirect-fints-local-dir "~/comdirect-fints"
  "Directory of a local comdirect-fints checkout (when source is `local')."
  :type 'directory :group 'my/comdirect-fints)

(defcustom my/comdirect-fints-elpaca-repo "deno1011/comdirect-fints"
  "GitHub repo used when the source is `elpaca'."
  :type 'string :group 'my/comdirect-fints)

(defcustom my/comdirect-fints-elpaca-branch "main"
  "Git branch used when installing through Elpaca."
  :type 'string :group 'my/comdirect-fints)

(defcustom my/comdirect-fints-elpaca-files
  '("comdirect-fints.el" "comdirect_fints_helper.py")
  "Files pulled into the Elpaca build (the Elisp AND the Python helper)."
  :type '(repeat string) :group 'my/comdirect-fints)

(defcustom my/comdirect-fints-product-id nil
  "Registered FinTS product id (mandatory).  Register free at hbci-zka.de."
  :type '(choice (const :tag "Unset — register first" nil) string)
  :group 'my/comdirect-fints)

(defcustom my/comdirect-fints-server "https://fints.comdirect.de/fints"
  "comdirect FinTS endpoint URL (verify the current value)."
  :type 'string :group 'my/comdirect-fints)

(defcustom my/comdirect-fints-python (or (executable-find "python3") "python3")
  "Python 3 interpreter used to run the FinTS helper."
  :type 'string :group 'my/comdirect-fints)

(defun my/comdirect-fints-apply-config ()
  "Push this module's settings into the loaded comdirect-fints package."
  (when (boundp 'comdirect-fints-product-id)
    (setq comdirect-fints-product-id my/comdirect-fints-product-id))
  (when (boundp 'comdirect-fints-server)
    (setq comdirect-fints-server my/comdirect-fints-server))
  (when (boundp 'comdirect-fints-python)
    (setq comdirect-fints-python my/comdirect-fints-python)))

(defun my/comdirect-fints-install-fints-command ()
  "Return the shell command that installs python-fints."
  (format "%s -m pip install --user fints"
          (shell-quote-argument my/comdirect-fints-python)))

;;;###autoload
(defun my/comdirect-fints-install-fints ()
  "Install the `fints' Python package for `my/comdirect-fints-python'."
  (interactive)
  (unless (executable-find my/comdirect-fints-python)
    (user-error "Python interpreter not found: %s" my/comdirect-fints-python))
  (compile (my/comdirect-fints-install-fints-command)))

(defun my/comdirect-fints-queue-elpaca ()
  "Load comdirect-fints from a local checkout or queue it through Elpaca."
  (pcase my/comdirect-fints-source
    ('local
     (let ((dir (expand-file-name my/comdirect-fints-local-dir)))
       (when (file-directory-p dir)
         (add-to-list 'load-path dir)
         (when (require 'comdirect-fints nil t)
           (my/comdirect-fints-apply-config)))))
    ('elpaca
     (when (fboundp 'elpaca)
       (eval
        `(elpaca
           (comdirect-fints
            :host github
            :repo ,my/comdirect-fints-elpaca-repo
            :branch ,my/comdirect-fints-elpaca-branch
            :files ,my/comdirect-fints-elpaca-files)
           (require 'comdirect-fints nil t)
           (my/comdirect-fints-apply-config))
        t)
       (when (fboundp 'elpaca-wait) (elpaca-wait))))))

(my/comdirect-fints-queue-elpaca)

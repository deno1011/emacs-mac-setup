;;; 67_comdirect_web.el --- comdirect-web loader -*- lexical-binding: t; -*-

(require 'cl-lib)

;; Forward declarations for the byte-compiler.
(defvar comdirect-web-banking-url)
(defvar comdirect-web-auto-submit)
(defvar comdirect-web-python)
(declare-function comdirect-web-open "comdirect-web")
(declare-function comdirect-web-transfer "comdirect-web")

(defcustom my/comdirect-web-source 'elpaca
  "Where comdirect-web is loaded from (`elpaca' private repo, or `local')."
  :type '(choice (const :tag "Elpaca package" elpaca)
                 (const :tag "Local checkout" local))
  :group 'my/comdirect-web)

(defcustom my/comdirect-web-local-dir "~/comdirect-web"
  "Directory of a local comdirect-web checkout (when source is `local')."
  :type 'directory :group 'my/comdirect-web)

(defcustom my/comdirect-web-elpaca-repo "deno1011/comdirect-web"
  "GitHub repo used when the source is `elpaca' (private)."
  :type 'string :group 'my/comdirect-web)

(defcustom my/comdirect-web-elpaca-branch "main"
  "Git branch used when installing through Elpaca."
  :type 'string :group 'my/comdirect-web)

(defcustom my/comdirect-web-elpaca-files
  '("comdirect-web.el" "comdirect_web_helper.py")
  "Files pulled into the Elpaca build (Elisp AND the Playwright helper)."
  :type '(repeat string) :group 'my/comdirect-web)

(defcustom my/comdirect-web-banking-url nil
  "URL of the comdirect banking / SEPA transfer page.
Set this to the real transfer page URL once you know it."
  :type '(choice (const :tag "Unset — set your transfer URL" nil) string)
  :group 'my/comdirect-web)

(defcustom my/comdirect-web-auto-submit nil
  "When non-nil, the helper clicks submit after filling (moves real money)."
  :type 'boolean :group 'my/comdirect-web)

(defcustom my/comdirect-web-python "/usr/bin/python3"
  "Python 3 interpreter with `playwright' installed."
  :type 'string :group 'my/comdirect-web)

(defun my/comdirect-web-apply-config ()
  "Push this module's settings into the loaded comdirect-web package."
  (dolist (pair `((comdirect-web-banking-url . ,my/comdirect-web-banking-url)
                  (comdirect-web-auto-submit . ,my/comdirect-web-auto-submit)
                  (comdirect-web-python      . ,my/comdirect-web-python)))
    (when (boundp (car pair))
      (set (car pair) (cdr pair)))))

(defun my/comdirect-web-install-playwright-command ()
  "Return the shell command that installs Playwright and its Chromium browser."
  (let ((py (shell-quote-argument my/comdirect-web-python)))
    (format "%s -m pip install --user playwright && %s -m playwright install chromium"
            py py)))

;;;###autoload
(defun my/comdirect-web-install-playwright ()
  "Install Playwright and the Chromium browser for `my/comdirect-web-python'."
  (interactive)
  (unless (executable-find my/comdirect-web-python)
    (user-error "Python interpreter not found: %s" my/comdirect-web-python))
  (compile (my/comdirect-web-install-playwright-command)))

(defun my/comdirect-web-queue-elpaca ()
  "Load comdirect-web from a local checkout or queue it through Elpaca."
  (pcase my/comdirect-web-source
    ('local
     (let ((dir (expand-file-name my/comdirect-web-local-dir)))
       (when (file-directory-p dir)
         (add-to-list 'load-path dir)
         (when (require 'comdirect-web nil t)
           (my/comdirect-web-apply-config)))))
    ('elpaca
     (when (fboundp 'elpaca)
       (eval
        `(elpaca
           (comdirect-web
            :host github
            :repo ,my/comdirect-web-elpaca-repo
            :branch ,my/comdirect-web-elpaca-branch
            :files ,my/comdirect-web-elpaca-files)
           (require 'comdirect-web nil t)
           (my/comdirect-web-apply-config))
        t)
       (when (fboundp 'elpaca-wait) (elpaca-wait))))))

(my/comdirect-web-queue-elpaca)

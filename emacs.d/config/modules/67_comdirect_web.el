;;; 67_comdirect_web.el --- comdirect-web loader -*- lexical-binding: t; -*-

(require 'cl-lib)

;; Forward declarations for the byte-compiler.
(defvar comdirect-web-banking-url)
(defvar comdirect-web-auto-submit)
(defvar comdirect-web-python)
(declare-function comdirect-web-open "comdirect-web")
(declare-function comdirect-web-transfer "comdirect-web")

(defcustom my/comdirect-web-source 'local
  "Where comdirect-web is loaded from (`elpaca' private repo, or `local').
Default `local' (~/comdirect-web) so the daemon always uses the current checkout
— the elpaca build lags behind pushes and would run stale transfer logic."
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

(defcustom my/comdirect-web-banking-url
  "https://kunde.comdirect.de/lp/wt/login?execution=e1s1&afterTimeout=true"
  "URL of the comdirect banking / login page."
  :type 'string :group 'my/comdirect-web)

(defcustom my/comdirect-web-contacts-url nil
  "Optional URL of the saved-contacts (Vorlagen) page."
  :type '(choice (const :tag "Unset" nil) string) :group 'my/comdirect-web)

(defcustom my/comdirect-web-user-account "COMDIRECT_FINTS_USER"
  "Keychain account for the web login (auto-login)."
  :type 'string :group 'my/comdirect-web)

(defcustom my/comdirect-web-pin-account "COMDIRECT_FINTS_PIN"
  "Keychain account for the web PIN (auto-login)."
  :type 'string :group 'my/comdirect-web)

(defcustom my/comdirect-web-auto-submit nil
  "When non-nil, the helper clicks submit after filling (moves real money)."
  :type 'boolean :group 'my/comdirect-web)

(defcustom my/comdirect-web-python "/usr/bin/python3"
  "Python 3 interpreter with `playwright' installed."
  :type 'string :group 'my/comdirect-web)

(defun my/comdirect-web-apply-config ()
  "Push this module's settings into the loaded comdirect-web package."
  (dolist (pair `((comdirect-web-banking-url . ,my/comdirect-web-banking-url)
                  (comdirect-web-contacts-url . ,my/comdirect-web-contacts-url)
                  (comdirect-web-user-account . ,my/comdirect-web-user-account)
                  (comdirect-web-pin-account  . ,my/comdirect-web-pin-account)
                  (comdirect-web-auto-submit  . ,my/comdirect-web-auto-submit)
                  (comdirect-web-python       . ,my/comdirect-web-python)))
    (when (boundp (car pair))
      (set (car pair) (cdr pair)))))

(defcustom my/comdirect-web-auto-install t
  "When non-nil, install Playwright + Chromium automatically if missing."
  :type 'boolean :group 'my/comdirect-web)

(defun my/comdirect-web-install-playwright-command ()
  "Return the shell command that installs Playwright and its Chromium browser."
  (let ((py (shell-quote-argument my/comdirect-web-python)))
    (format "%s -m pip install --user playwright && %s -m playwright install chromium"
            py py)))

(defun my/comdirect-web--playwright-ready-p ()
  "Return non-nil when Playwright AND a Chromium browser are installed."
  (and (executable-find my/comdirect-web-python)
       (eq 0 (call-process my/comdirect-web-python nil nil nil "-c" "import playwright"))
       (let ((dir (expand-file-name "~/Library/Caches/ms-playwright")))
         (and (file-directory-p dir)
              (seq-find (lambda (f) (string-prefix-p "chromium" f))
                        (directory-files dir))
              t))))

(defun my/comdirect-web-ensure-playwright ()
  "Idempotently install Playwright + Chromium (async) when missing."
  (when (and my/comdirect-web-auto-install
             (executable-find my/comdirect-web-python)
             (not (my/comdirect-web--playwright-ready-p)))
    (message "comdirect-web: installing Playwright + Chromium (async, one-time)…")
    (make-process
     :name "comdirect-web-playwright-install"
     :buffer (get-buffer-create "*comdirect-web playwright install*")
     :command (list "sh" "-c" (my/comdirect-web-install-playwright-command))
     :sentinel
     (lambda (p _e)
       (when (eq (process-status p) 'exit)
         (message "comdirect-web: Playwright install %s"
                  (if (eq 0 (process-exit-status p)) "done"
                    "FAILED — see *comdirect-web playwright install*")))))))

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
(my/comdirect-web-ensure-playwright)

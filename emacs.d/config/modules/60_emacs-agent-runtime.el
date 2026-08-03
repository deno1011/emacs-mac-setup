;;; 60_emacs-agent-runtime.el --- gptel and Emacs agent runtime loader -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar my/gptel-backends nil)
(defvar my/gptel-ollama-backend nil)
(defvar gptel-backend)
(defvar gptel-model)
(defvar gptel-default-mode)
(defvar gptel-directives)
(defvar gptel-tools)
(defvar gptel-use-tools)
(defvar my/data-dir)
(defvar ear-config-directory)
(defvar ear-config-extra-directories)
(defvar ear-config-authoring-directory)
(defvar ear-config-private-directory)
(defvar ear-config-extension-directories)
(defvar ear-source-overlay-core-directory)
(defvar ear-source-overlay-private-directory)
(defvar ear-config--loaded-directory)
(defvar my/emacs-agent-runtime-dir
  (expand-file-name "~/emacs-agent-runtime"))
(defvar my/gptel-ollama-host "localhost:11434")
(defvar my/gptel-default-local-model 'qwen2.5:14b-instruct)
(defvar my/gptel-default-local-model-label "Qwen 2.5 Instruct 14B (Ollama)")
(defvar my/gptel-high-fidelity-model nil)

(declare-function gptel-make-anthropic "gptel-anthropic")
(declare-function gptel-make-openai "gptel-openai")
(declare-function gptel-make-gemini "gptel-gemini")
(declare-function gptel-make-ollama "gptel-ollama")
(declare-function emacs-agent-runtime-mode "emacs-agent-runtime" (&optional arg))
(declare-function emacs-agent-runtime-gptel-install-read-tools
                  "ear-adapter-gptel" (&optional local))
(declare-function ear-adapter-gptel-runtime-directive
                  "ear-adapter-gptel" ())
(declare-function emacs-agent-runtime-show-cli-request-preview
                  "ear-adapter-cli" (agent prompt &optional continue context))
(declare-function emacs-agent-runtime-queue-cli-agent-launch
                  "ear-adapter-cli" (agent prompt &optional continue context))
(declare-function ear-adapter-cli--current-context-text
                  "ear-adapter-cli" ())
(declare-function ear-get-default-runtime "ear" ())
(declare-function ear-runtime-registry-create-runtime
                  "ear-runtime-registry" (id &rest props))
(declare-function ear-scheduler-auto-start-jobs
                  "ear-scheduler" (&optional runtime-fn))
(declare-function ear-scheduler-list "ear-scheduler" ())
(declare-function ear-scheduler-running-p "ear-scheduler" (id))
(declare-function ear-config-reload "ear-config" (&optional directory context))
(declare-function my/api-key-fetch "20.03.01_bootstrap" (key-name))
(declare-function my/api-key-store "20.02.03_bootstrap_secrets" (key-name value))

(defcustom my/emacs-agent-runtime-open-tool-policy t
  "When non-nil, allow EAR write tools without interactive approvals.
This personal setup switch is for logic testing during EAR development.  It only
changes EAR policy; it does not bypass macOS, Codex, or filesystem sandbox
permissions."
  :type 'boolean
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-god-mode t
  "When non-nil, enable EAR/Codex/GPTel God Mode for test users.
This intentionally opens the local AI runtime for coaching experiments:
registered EAR tools are allowed by policy, gptel may export write tools, Codex
CLI bypasses its approval/sandbox prompts, and the dangerous `emacs_command'
bridge becomes available. This is the current test-user posture; product-ready
installs should later lock this down with source-aware policies."
  :type 'boolean
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-jobs-store-file
  (expand-file-name
   "ear/jobs-store.el"
   (if (and (boundp 'my/data-dir)
            (stringp my/data-dir))
       my/data-dir
     user-emacs-directory))
  "Personal durable EAR jobs store file.
The reusable runtime defaults to in-memory jobs. This local setup enables a
durable store so Life Coach and other generic jobs survive Emacs restarts."
  :type 'file
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-use-api-key-fetch-resolver t
  "When non-nil, wire EAR's API credential resolver to `my/api-key-fetch'.
The reusable EAR package only exposes a generic resolver hook. This setup
module owns the personal macOS/Bitwarden/Keychain binding."
  :type 'boolean
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-workspace-directory
  (expand-file-name "declarations/workspace/" my/emacs-agent-runtime-dir)
  "Directory containing the active EAR workspace declarations.
Reusable shipped core/capability layers are selected by the EAR manifest.
This setup owns external overlay paths so private repositories never need to
be named inside reusable declarations.  Keeping this one entry point in setup
means a renamed or separately installed EAR checkout needs no path edits in
agent files."
  :type 'directory
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-personal-directory nil
  "User-owned EAR declaration overlay.
When nil, derive `ear-config/' below the private data repository selected by
the bootstrap subsystem.  The directory is loaded after the reusable workspace
layer and is the only default target for autonomous declaration authoring."
  :type '(choice (const :tag "Use <private-data-repo>/ear-config/" nil)
                 directory)
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-private-directory nil
  "User-owned repository root for writable EAR content.
When nil, use the private data repository selected by the bootstrap subsystem.
Normal agents may read reusable EAR Core, but their writable file boundary is
this directory.  Its `ear-config/' child contains declaration overlays and its
`ear-extensions/lisp/' child contains private executable extensions."
  :type '(choice (const :tag "Use the private data repository" nil)
                 directory)
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-source-overlay-directory nil
  "User-owned relative-path mirror of the complete EAR Core tree.
When nil, use `ear-overrides/' below
`my/emacs-agent-runtime-private-directory'.  A file in this directory shadows
the Core file with the same relative path; missing private files fall back to
Core.  This includes Lisp, declarations, tools, adapters, docs, and scripts."
  :type '(choice (const :tag "Use <private-data-repo>/ear-overrides/" nil)
                 directory)
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-extension-directories nil
  "Private Lisp directories added to EAR and process-worker load paths.
When nil, use `ear-extensions/lisp/' below
`my/emacs-agent-runtime-private-directory'."
  :type '(repeat directory)
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-core-adapters-directory nil
  "Root for reusable external adapter checkouts used with EAR Core.
When nil, derive `external/adapters/' below
`my/emacs-agent-runtime-dir'.  The adapter repositories remain independent
Git checkouts; this setting provides one stable location for loaders, Doctor
checks, and operator documentation."
  :type '(choice (const :tag "Use <EAR checkout>/external/adapters/" nil)
                 directory)
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-private-adapters-directory nil
  "Root for user-owned adapter checkouts and their local runtime state.
When nil, derive `ear-extensions/adapters/' below
`my/emacs-agent-runtime-private-directory'.  Put adapters with account
configuration, auth state, or private deployment data here."
  :type '(choice
          (const :tag "Use <private-data-repo>/ear-extensions/adapters/" nil)
          directory)
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-auto-start-scheduler-jobs t
  "When non-nil, start EAR scheduler jobs marked with `:auto-start'."
  :type 'boolean
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-scheduler-default-provider 'claude
  "Default provider runtime used for EAR scheduler auto-start jobs."
  :type '(choice (const :tag "Claude CLI" claude)
                 (const :tag "Codex CLI" codex)
                 (const :tag "Default EAR runtime" default))
  :group 'emacs-agent-runtime)

(defvar my/emacs-agent-runtime--startup-reconciled nil
  "Non-nil after this Emacs process loaded the configured EAR declarations.")

(defcustom my/emacs-agent-runtime-source 'local
  "Where this setup loads Emacs Agent Runtime from.
Use `local' for active development from `my/emacs-agent-runtime-dir'. Use
`elpaca' for normal user/product installs managed by the package manager."
  :type '(choice (const :tag "Local checkout" local)
                 (const :tag "Elpaca package" elpaca))
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-elpaca-repo "deno1011/emacs-agent-runtime"
  "GitHub repo used when `my/emacs-agent-runtime-source' is `elpaca'."
  :type 'string
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-elpaca-branch "main"
  "Git branch used when installing EAR through Elpaca."
  :type 'string
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-elpaca-files
  '("lisp/*.el"
    "*.el"
    "knowledge/*.org"
    "workflows/*.org"
    "sessions/*.org"
    "packs/*/*.org"
    "packs/*/*/*.org")
  "Files included in the Elpaca package recipe for EAR."
  :type '(repeat sexp)
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-context-directories
  (list
   (expand-file-name
    "ear/context/"
    (if (and (boundp 'my/data-dir)
             (stringp my/data-dir))
        my/data-dir
      user-emacs-directory)))
  "Setup/user-owned EAR context hint directories.
These directories can contain Org files with EAR_CONTEXT_* properties. They
are loaded in addition to context hints provided by runtime packs, so private
path routing does not need to live in EAR core or in reusable packs."
  :type '(repeat directory)
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-qmd-enabled t
  "When non-nil, enable the optional QMD retrieval backend in EAR metadata.
This setup switch only tells EAR that QMD is an available retrieval backend.
It does not install QMD, start a daemon, export projections, index Org files,
or download models."
  :type 'boolean
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-qmd-command "qmd"
  "QMD executable name used by EAR's optional QMD retrieval adapter."
  :type 'string
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-qmd-package "@tobilu/qmd"
  "QMD package name used by the setup-owned install command."
  :type 'string
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-qmd-version "2.6.3"
  "Reviewed QMD package version for this setup."
  :type 'string
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-qmd-package-manager 'npm
  "Package manager used by `my/emacs-agent-runtime-qmd-install'."
  :type '(choice (const :tag "npm" npm)
                 (const :tag "bun" bun))
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-qmd-projection-directory
  (expand-file-name
   "ear/qmd-projection/"
   (if (and (boundp 'my/data-dir)
            (stringp my/data-dir))
       my/data-dir
     user-emacs-directory))
  "Directory for generated QMD Markdown projections.
Org files remain the source of truth. QMD should index these projected files,
not raw personal Org files."
  :type 'directory
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-qmd-exclude-tags
  '("noexport" "private" "secret" "crypt")
  "Org tags excluded from QMD Markdown projection exports."
  :type '(repeat string)
  :group 'emacs-agent-runtime)

(defcustom my/emacs-agent-runtime-qmd-apple-silicon-environment
  '(("QMD_LLAMA_GPU" . "metal")
    ("QMD_EMBED_PARALLELISM" . "2"))
  "Conservative QMD environment hints for Apple Silicon machines."
  :type '(alist :key-type string :value-type string)
  :group 'emacs-agent-runtime)

(defun my/emacs-agent-runtime-apply-credential-resolver ()
  "Wire personal setup credentials into EAR's generic API resolver when possible."
  (when (and my/emacs-agent-runtime-use-api-key-fetch-resolver
             (fboundp 'my/api-key-fetch))
    (when (boundp 'ear-adapter-api-credential-resolver)
      (setq ear-adapter-api-credential-resolver #'my/api-key-fetch)
      (when (boundp 'ear-adapter-api-credential-resolver-name)
        (setq ear-adapter-api-credential-resolver-name 'setup-keychain))
      (when (boundp 'ear-adapter-api-prefer-credential-resolver)
        (setq ear-adapter-api-prefer-credential-resolver t)))
    ;; OpenRouter reads its key through its own hook; point it at the Keychain.
    ;; Independent of the generic resolver above (which EAR core may not expose).
    (when (boundp 'ear-adapter-openrouter-api-key-function)
      (setq ear-adapter-openrouter-api-key-function
            (lambda () (my/api-key-fetch "OPENROUTER_API_KEY"))))))

(defconst my/emacs-agent-runtime-subscription-token-key
  "ANTHROPIC_SUBSCRIPTION_API_KEY"
  "Keychain account (service `emacs_credentials') for the Claude subscription token.
Obtained via `claude setup-token'.  A subscription token is not an API key; it is
exported as CLAUDE_CODE_OAUTH_TOKEN so EAR's `claude -p' workers authenticate against
claude.ai instead of falling back to pay-per-use billing.")

(defun my/emacs-agent-runtime-apply-subscription-token ()
  "Export the stored Claude subscription token so `claude -p' uses claude.ai.
Reads the token from the Keychain and sets CLAUDE_CODE_OAUTH_TOKEN; ANTHROPIC_API_KEY
is cleared because a subscription token is not an API key.  Worker `claude -p' processes
inherit this from the daemon environment.  No-op when no token is configured."
  (when (fboundp 'my/api-key-fetch)
    (let ((token (my/api-key-fetch my/emacs-agent-runtime-subscription-token-key)))
      (when (and (stringp token) (not (string-empty-p token)))
        (setenv "ANTHROPIC_API_KEY" nil)
        (setenv "CLAUDE_CODE_OAUTH_TOKEN" token)
        t))))

(defun my/emacs-agent-runtime-set-subscription-token (token)
  "Store the Claude subscription TOKEN in the Keychain and apply it now.
Get the token first with `claude setup-token' (requires a Claude subscription).
Stored under account ANTHROPIC_SUBSCRIPTION_API_KEY (service `emacs_credentials') and
exported as CLAUDE_CODE_OAUTH_TOKEN so EAR's `claude -p' authenticates against claude.ai
instead of hitting \"Credit balance is too low\" via pay-per-use billing."
  (interactive
   (list (read-passwd "Claude subscription OAuth token (from `claude setup-token'): ")))
  (unless (fboundp 'my/api-key-store)
    (user-error "Secrets module not loaded; cannot store the token"))
  (when (or (null token) (string-empty-p token))
    (user-error "No token entered"))
  (let ((result (my/api-key-store my/emacs-agent-runtime-subscription-token-key token)))
    (if (eq result :ok)
        (progn
          (my/emacs-agent-runtime-apply-subscription-token)
          (message
           "Claude subscription token stored and applied (CLAUDE_CODE_OAUTH_TOKEN set)"))
      (user-error "Failed to store token: %S" result))))

(defun my/emacs-agent-runtime-config-directory ()
  "Return the configured EAR workspace declaration directory."
  (when (and (boundp 'my/emacs-agent-runtime-workspace-directory)
             (stringp my/emacs-agent-runtime-workspace-directory))
    (file-name-as-directory
     (expand-file-name my/emacs-agent-runtime-workspace-directory))))

(defun my/emacs-agent-runtime-personal-config-directory ()
  "Return the configured user-owned EAR declaration overlay."
  (let ((directory
         (or my/emacs-agent-runtime-personal-directory
             (when-let ((root
                         (my/emacs-agent-runtime-private-root-directory)))
               (expand-file-name "ear-config/" root)))))
    (when (stringp directory)
      (file-name-as-directory (expand-file-name directory)))))

(defun my/emacs-agent-runtime-private-root-directory ()
  "Return the configured user-owned EAR repository root."
  (let ((directory
         (or my/emacs-agent-runtime-private-directory
             (and (stringp my/data-dir) my/data-dir))))
    (when (stringp directory)
      (file-name-as-directory (expand-file-name directory)))))

(defun my/emacs-agent-runtime-private-extension-directories ()
  "Return configured private EAR Lisp extension directories."
  (let ((directories
         (or my/emacs-agent-runtime-extension-directories
             (when-let ((root
                         (my/emacs-agent-runtime-private-root-directory)))
               (list (expand-file-name "ear-extensions/lisp/" root))))))
    (mapcar (lambda (directory)
              (file-name-as-directory (expand-file-name directory)))
            directories)))

(defun my/emacs-agent-runtime-core-adapters-root-directory ()
  "Return the configured root for reusable external adapter checkouts."
  (file-name-as-directory
   (expand-file-name
    (or my/emacs-agent-runtime-core-adapters-directory
        (expand-file-name "external/adapters/"
                          my/emacs-agent-runtime-dir)))))

(defun my/emacs-agent-runtime-private-adapters-root-directory ()
  "Return the configured root for user-owned adapter checkouts."
  (let ((directory
         (or my/emacs-agent-runtime-private-adapters-directory
             (when-let ((root
                         (my/emacs-agent-runtime-private-root-directory)))
               (expand-file-name "ear-extensions/adapters/" root)))))
    (when (stringp directory)
      (file-name-as-directory (expand-file-name directory)))))

(defun my/emacs-agent-runtime-source-overlay-root-directory ()
  "Return the configured user-owned EAR source overlay root."
  (let ((directory
         (or my/emacs-agent-runtime-source-overlay-directory
             (when-let ((root
                         (my/emacs-agent-runtime-private-root-directory)))
               (expand-file-name "ear-overrides/" root)))))
    (when (stringp directory)
      (file-name-as-directory (expand-file-name directory)))))

(defun my/emacs-agent-runtime-core-root-directory (&optional load-directory)
  "Return EAR Core root inferred from LOAD-DIRECTORY or setup configuration."
  (let* ((candidate
          (or load-directory
              (and (eq my/emacs-agent-runtime-source 'local)
                   my/emacs-agent-runtime-dir)
              (when-let ((library
                          (locate-library "emacs-agent-runtime")))
                (file-name-directory library))))
         (directory
          (and (stringp candidate)
               (file-name-as-directory (expand-file-name candidate)))))
    (when directory
      (if (string= (file-name-nondirectory
                    (directory-file-name directory))
                   "lisp")
          (file-name-directory (directory-file-name directory))
        directory))))

(defun my/emacs-agent-runtime--lisp-directories (root)
  "Return ROOT and its Lisp subdirectories in stable order."
  (let (result)
    (cl-labels
        ((walk
          (directory)
          (when (file-directory-p directory)
            (push (file-name-as-directory directory) result)
            (dolist (entry
                     (directory-files
                      directory t directory-files-no-dot-files-regexp))
              (when (and (file-directory-p entry)
                         (not (member
                               (file-name-nondirectory
                                (directory-file-name entry))
                               '(".git" ".ear-overlay-meta"))))
                (walk entry))))))
      (when root
        (walk (expand-file-name "lisp/" root))))
    (sort (delete-dups result) #'string<)))

(defun my/emacs-agent-runtime-install-source-overlay-load-paths
    (&optional core-root)
  "Install private EAR Lisp paths ahead of CORE-ROOT before EAR is required."
  (let* ((core (my/emacs-agent-runtime-core-root-directory core-root))
         (private
          (my/emacs-agent-runtime-source-overlay-root-directory))
         (core-lisp (my/emacs-agent-runtime--lisp-directories core))
         (private-lisp
          (my/emacs-agent-runtime--lisp-directories private)))
    (setq ear-source-overlay-core-directory core
          ear-source-overlay-private-directory private)
    ;; Cons Core first and private last so every private directory ends up
    ;; before every Core directory in `load-path'.
    (dolist (directory (append core-lisp private-lisp))
      (setq load-path (cons directory (delete directory load-path))))
    (append private-lisp core-lisp)))

(defun my/emacs-agent-runtime-ensure-personal-overlay ()
  "Create the standard user-owned EAR layer and extension roots idempotently."
  (when-let ((directory
              (my/emacs-agent-runtime-personal-config-directory)))
    (dolist (relative '("agents" "shared" "state"))
      (make-directory (expand-file-name relative directory) t))
    (dolist (extension
             (my/emacs-agent-runtime-private-extension-directories))
      (make-directory extension t))
    (make-directory
     (my/emacs-agent-runtime-core-adapters-root-directory) t)
    (when-let ((private-adapters
                (my/emacs-agent-runtime-private-adapters-root-directory)))
      (make-directory private-adapters t))
    (when-let ((source-overlay
                (my/emacs-agent-runtime-source-overlay-root-directory)))
      (dolist (relative
               '("lisp" "lisp/adapters" "lisp/tools" "declarations"))
        (make-directory (expand-file-name relative source-overlay) t)))
    directory))

(defun my/emacs-agent-runtime-apply-overlay-config ()
  "Bind EAR to the declaration entry point chosen by this setup."
  (let ((directory (my/emacs-agent-runtime-config-directory))
        (private-directory
         (my/emacs-agent-runtime-private-root-directory))
        (personal-directory
         (my/emacs-agent-runtime-ensure-personal-overlay)))
    (when directory
      (setq ear-config-directory directory))
    (setq ear-config-extra-directories
          (if personal-directory
              (list personal-directory)
            nil)
          ear-config-authoring-directory personal-directory
          ear-config-private-directory private-directory
          ear-config-extension-directories
          (my/emacs-agent-runtime-private-extension-directories)
          ear-source-overlay-core-directory
          (my/emacs-agent-runtime-core-root-directory)
          ear-source-overlay-private-directory
          (my/emacs-agent-runtime-source-overlay-root-directory))))

(defun my/emacs-agent-runtime-reconcile-declarations (&optional force)
  "Load the configured EAR declaration graph once, or again when FORCE is non-nil.

This deliberately runs after `ear-config-directory' has been bound and before
the default runtime is created.  It repairs partial early loads caused by a
package requiring EAR before the main EAR setup block has run."
  (when (and (fboundp 'ear-config-reload)
             (or force (not my/emacs-agent-runtime--startup-reconciled)))
    (let* ((directory (my/emacs-agent-runtime-config-directory))
           (result
            (condition-case error
                (ear-config-reload directory)
              (error
               (list :status 'error
                     :reason (error-message-string error))))))
      (if (eq (plist-get result :status) 'ok)
          (setq my/emacs-agent-runtime--startup-reconciled t)
        (display-warning
         'emacs-agent-runtime
         (format "EAR declaration reconciliation failed: %s"
                 (or (plist-get result :reason) result))
         :error))
      result)))

(defun my/emacs-agent-runtime-apply-qmd-config ()
  "Apply setup-owned QMD defaults to EAR's optional retrieval boundary."
  (when (boundp 'ear-retrieval-enabled-backends)
    (setq ear-retrieval-enabled-backends
          (if my/emacs-agent-runtime-qmd-enabled
              (cl-union '(qmd) ear-retrieval-enabled-backends :test #'eq)
            (remove 'qmd ear-retrieval-enabled-backends))))
  (when (boundp 'ear-retrieval-qmd-command)
    (setq ear-retrieval-qmd-command
          my/emacs-agent-runtime-qmd-command))
  (when (boundp 'ear-retrieval-qmd-pinned-version)
    (setq ear-retrieval-qmd-pinned-version
          my/emacs-agent-runtime-qmd-version))
  (when (boundp 'ear-retrieval-qmd-projection-directory)
    (setq ear-retrieval-qmd-projection-directory
          my/emacs-agent-runtime-qmd-projection-directory))
  (when (boundp 'ear-retrieval-qmd-projection-exclude-tags)
    (setq ear-retrieval-qmd-projection-exclude-tags
          my/emacs-agent-runtime-qmd-exclude-tags))
  (when (boundp 'ear-retrieval-qmd-apple-silicon-environment)
    (setq ear-retrieval-qmd-apple-silicon-environment
          my/emacs-agent-runtime-qmd-apple-silicon-environment)))

(defun my/emacs-agent-runtime-apply-context-config ()
  "Apply setup-owned context hint directories to EAR."
  (when (boundp 'ear-context-extra-directories)
    (setq ear-context-extra-directories
          my/emacs-agent-runtime-context-directories)))

(defun my/emacs-agent-runtime-qmd-install-command ()
  "Return the configured shell command for installing QMD."
  (pcase my/emacs-agent-runtime-qmd-package-manager
    ('npm
     (format "npm install -g %s"
             (shell-quote-argument
              (format "%s@%s"
                      my/emacs-agent-runtime-qmd-package
                      my/emacs-agent-runtime-qmd-version))))
    ('bun
     (format "bun install -g %s"
             (shell-quote-argument
              (format "%s@%s"
                      my/emacs-agent-runtime-qmd-package
                      my/emacs-agent-runtime-qmd-version))))
    (_
     (user-error "Unsupported QMD package manager: %S"
                 my/emacs-agent-runtime-qmd-package-manager))))

(defun my/emacs-agent-runtime-qmd-install ()
  "Install the optional QMD CLI through the configured Emacs setup command.
This command only installs the CLI package. It does not start QMD, export
projections, index Org files, or download models intentionally."
  (interactive)
  (let* ((manager (symbol-name my/emacs-agent-runtime-qmd-package-manager))
         (cmd (my/emacs-agent-runtime-qmd-install-command)))
    (unless (executable-find manager)
      (user-error "%s is not on `exec-path`; install Node/npm or Bun first"
                  manager))
    (compile cmd)))

(defun my/emacs-agent-runtime-apply-open-tool-policy ()
  "Apply the current test-user open policy to the loaded EAR runtime."
  (when (and my/emacs-agent-runtime-jobs-store-file
             (boundp 'ear-jobs-store-file))
    (setq ear-jobs-store-file my/emacs-agent-runtime-jobs-store-file))
  (when (boundp 'ear-jobs-auto-save-store)
    (setq ear-jobs-auto-save-store t))
  (when (and my/emacs-agent-runtime-god-mode
             (boundp 'ear-god-mode))
    (setq ear-god-mode t))
  (when (and my/emacs-agent-runtime-open-tool-policy
             (boundp 'ear-policy-allow-write-tools))
    (setq ear-policy-allow-write-tools t))
  (when (and my/emacs-agent-runtime-open-tool-policy
             (boundp 'emacs-agent-runtime-codex-inline-execute-auto-approved-writes))
    (setq emacs-agent-runtime-codex-inline-execute-auto-approved-writes t))
  (when (and my/emacs-agent-runtime-god-mode
             (boundp 'emacs-agent-runtime-codex-inline-tool-request-max-rounds))
    (setq emacs-agent-runtime-codex-inline-tool-request-max-rounds nil))
  (when (and my/emacs-agent-runtime-god-mode
             (boundp 'emacs-agent-runtime-codex-inline-tool-request-confirm-after-rounds))
    (setq emacs-agent-runtime-codex-inline-tool-request-confirm-after-rounds 10))
  (when (and my/emacs-agent-runtime-god-mode
             (boundp 'ear-adapter-gptel-export-write-tools-in-god-mode))
    (setq ear-adapter-gptel-export-write-tools-in-god-mode t))
  (when (and my/emacs-agent-runtime-god-mode
             (boundp 'emacs-agent-runtime-codex-chat-sandbox))
    (setq emacs-agent-runtime-codex-chat-sandbox "danger-full-access"))
  (when (and my/emacs-agent-runtime-god-mode
             (boundp 'emacs-agent-runtime-codex-chat-bypass-approvals-and-sandbox))
    (setq emacs-agent-runtime-codex-chat-bypass-approvals-and-sandbox t)))

(defun my/emacs-agent-runtime-scheduler-runtime (job)
  "Return the runtime for scheduler JOB."
  (let ((runtime-id (or (plist-get job :runtime)
                        my/emacs-agent-runtime-scheduler-default-provider)))
    (cond
     ((fboundp 'ear-runtime-registry-create-runtime)
      (ear-runtime-registry-create-runtime runtime-id))
     ((and (eq runtime-id 'default)
           (fboundp 'ear-get-default-runtime))
      (ear-get-default-runtime))
     (t nil))))

(defun my/emacs-agent-runtime-start-scheduler-jobs ()
  "Start EAR scheduler jobs that opt into auto-start and report failures."
  (when (and my/emacs-agent-runtime-auto-start-scheduler-jobs
             (fboundp 'ear-scheduler-auto-start-jobs))
    (let* ((result
            (ear-scheduler-auto-start-jobs
             #'my/emacs-agent-runtime-scheduler-runtime))
           (missing
            (when (and (fboundp 'ear-scheduler-list)
                       (fboundp 'ear-scheduler-running-p))
              (delq
               nil
               (mapcar
                (lambda (job)
                  (let ((id (plist-get job :id)))
                    (when (and (plist-get job :auto-start)
                               (not (ear-scheduler-running-p id)))
                      id)))
                (ear-scheduler-list))))))
      (when missing
        (display-warning
         'emacs-agent-runtime
         (format "EAR auto-start jobs are not running: %s"
                 (string-join missing ", "))
         :warning))
      (append result (list :missing missing)))))

(defun my/emacs-agent-runtime-scheduler-health ()
  "Show whether every registered EAR auto-start job is running."
  (interactive)
  (unless (and (fboundp 'ear-scheduler-list)
               (fboundp 'ear-scheduler-running-p))
    (user-error "EAR scheduler is not loaded"))
  (let* ((jobs
          (seq-filter
           (lambda (job) (plist-get job :auto-start))
           (ear-scheduler-list)))
         (states
          (mapcar
           (lambda (job)
             (cons (plist-get job :id)
                   (and (ear-scheduler-running-p (plist-get job :id)) t)))
           jobs))
         (missing (mapcar #'car (seq-remove #'cdr states))))
    (when (called-interactively-p 'interactive)
      (message "EAR auto-start: %d/%d running%s"
               (- (length states) (length missing))
               (length states)
               (if missing
                   (format "; missing %s" (string-join missing ", "))
                 "")))
    (list :status (if missing 'error 'ok)
          :registered (length states)
          :running (- (length states) (length missing))
          :missing missing
          :jobs states)))

(defun my/emacs-agent-runtime--apply-loaded-config ()
  "Apply setup-owned defaults after EAR has loaded."
  (my/emacs-agent-runtime-apply-overlay-config)
  (my/emacs-agent-runtime-reconcile-declarations)
  (when (fboundp 'ear-get-default-runtime)
    (ear-get-default-runtime))
  (when (fboundp 'emacs-agent-runtime-mode)
    (emacs-agent-runtime-mode 1))
  (when (boundp 'emacs-agent-runtime-cli-default-agent)
    (setq emacs-agent-runtime-cli-default-agent "codex"))
  (my/emacs-agent-runtime-apply-credential-resolver)
  (my/emacs-agent-runtime-apply-subscription-token)
  (my/emacs-agent-runtime-apply-context-config)
  (my/emacs-agent-runtime-apply-qmd-config)
  (my/emacs-agent-runtime-apply-open-tool-policy)
  (my/emacs-agent-runtime-start-scheduler-jobs)
  t)

(defun my/emacs-agent-runtime-queue-elpaca ()
  "Queue EAR through Elpaca when the setup is in package mode."
  (when (and (eq my/emacs-agent-runtime-source 'elpaca)
             (fboundp 'elpaca))
    (eval
     `(elpaca
        (emacs-agent-runtime
         :host github
         :repo ,my/emacs-agent-runtime-elpaca-repo
         :branch ,my/emacs-agent-runtime-elpaca-branch
         :files ,my/emacs-agent-runtime-elpaca-files)
        (my/emacs-agent-runtime-apply-overlay-config)
        (my/emacs-agent-runtime-install-source-overlay-load-paths)
        (require 'emacs-agent-runtime nil t)))
    (when (fboundp 'elpaca-wait)
      (elpaca-wait))))

(my/emacs-agent-runtime-queue-elpaca)

(defun my/emacs-agent-runtime-load-path-directory ()
  "Return the load-path directory for the local EAR checkout."
  (let* ((root (file-name-as-directory
                (expand-file-name my/emacs-agent-runtime-dir)))
         (lisp (expand-file-name "lisp/" root)))
    (if (file-directory-p lisp) lisp root)))

(defun my/emacs-agent-runtime-load ()
  "Load Emacs Agent Runtime from the configured source."
  (my/emacs-agent-runtime-apply-overlay-config)
  (let* ((root (file-name-as-directory
                (expand-file-name my/emacs-agent-runtime-dir)))
         (load-dir (my/emacs-agent-runtime-load-path-directory)))
    (cond
     ((featurep 'emacs-agent-runtime)
      (my/emacs-agent-runtime--apply-loaded-config))
     ((eq my/emacs-agent-runtime-source 'elpaca)
      (my/emacs-agent-runtime-install-source-overlay-load-paths)
      (if (require 'emacs-agent-runtime nil t)
          (my/emacs-agent-runtime--apply-loaded-config)
        (message "emacs-agent-runtime not available from Elpaca package")
        nil))
     ((not (eq my/emacs-agent-runtime-source 'local))
      (message "Unknown my/emacs-agent-runtime-source: %S"
               my/emacs-agent-runtime-source)
      nil)
     ((not (file-directory-p root))
      (message "emacs-agent-runtime directory missing: %s" root)
      nil)
     (t
      (add-to-list 'load-path load-dir)
      (my/emacs-agent-runtime-install-source-overlay-load-paths root)
      (if (require 'emacs-agent-runtime nil t)
          (progn
            (my/emacs-agent-runtime--apply-loaded-config)
            (message "emacs-agent-runtime loaded from %s" load-dir)
            t)
        (message "emacs-agent-runtime not loadable from %s" load-dir)
        nil)))))

(defun my/emacs-agent-runtime-install-gptel-tools ()
  "Install EAR's read-only tools and directive into gptel."
  (when (my/emacs-agent-runtime-load)
    (when (boundp 'gptel-use-tools)
      (setq gptel-use-tools t))
    (when (and (boundp 'gptel-directives)
               (fboundp 'ear-adapter-gptel-runtime-directive))
      (setq gptel-directives
            (assq-delete-all 'emacs-agent-runtime gptel-directives))
      (add-to-list
       'gptel-directives
       `(emacs-agent-runtime . ,(ear-adapter-gptel-runtime-directive))))
    (when (fboundp 'emacs-agent-runtime-gptel-install-read-tools)
      (emacs-agent-runtime-gptel-install-read-tools))))

(defun my/emacs-agent-runtime-codex-preview (prompt)
  "Preview a Codex CLI request using current region or buffer context."
  (interactive (list (read-string "Codex prompt: " "Review this Emacs context.")))
  (unless (my/emacs-agent-runtime-load)
    (user-error "emacs-agent-runtime is not available"))
  (emacs-agent-runtime-show-cli-request-preview
   "codex" prompt nil
   (when (fboundp 'ear-adapter-cli--current-context-text)
     (ear-adapter-cli--current-context-text))))

(defun my/emacs-agent-runtime-codex-launch (prompt)
  "Queue an approval-gated Codex CLI launch using current context."
  (interactive (list (read-string "Codex prompt: " "Review this Emacs context.")))
  (unless (my/emacs-agent-runtime-load)
    (user-error "emacs-agent-runtime is not available"))
  (emacs-agent-runtime-queue-cli-agent-launch
   "codex" prompt nil
   (when (fboundp 'ear-adapter-cli--current-context-text)
     (ear-adapter-cli--current-context-text))))

;; Bind EAR's declaration root before demanding gptel.  gptel integrations may
;; load EAR transitively, so doing this only in gptel's :config block is too
;; late and can leave EAR partially initialized against the wrong directory.
(my/emacs-agent-runtime-apply-overlay-config)

;; gptel remains the chat UI/backend client. The old gptel-agent-runtime package
;; is intentionally not installed or loaded from this module anymore.
(use-package gptel
  :ensure t
  :demand t
  :config
  (setq gptel-default-mode 'org-mode)
  (my/emacs-agent-runtime-load)
  (when (boundp 'emacs-agent-runtime-cli-default-agent)
    (setq emacs-agent-runtime-cli-default-agent "codex"))
  (my/emacs-agent-runtime-install-gptel-tools))

;; Backends are configured once gptel has loaded. EAR does not own gptel
;; backends; it only contributes optional read-only tools and runtime context.
(with-eval-after-load 'gptel

(my/emacs-agent-runtime-load)

(require 'gptel-anthropic nil t)
(require 'gptel-openai nil t)
(require 'gptel-ollama nil t)
(require 'gptel-gemini nil t)

;; -- Anthropic / Claude -----------------------------------------------
;; Key stored in BW item `emacs_credentials' (custom field ANTHROPIC_API_KEY)
;; and cached in macOS Keychain service `emacs_credentials' (account ANTHROPIC_API_KEY).
;; Rotate via `M-x my/api-key-set' → ANTHROPIC_API_KEY.
(let ((backend (gptel-make-anthropic "Claude"
                  :stream t
                  :key (lambda () (my/api-key-fetch "ANTHROPIC_API_KEY")))))
  (setq my/gptel-backends
        `(("Claude Opus 4.7"    ,backend . claude-opus-4-7)
          ("Claude Sonnet 4.6"  ,backend . claude-sonnet-4-6)
          ("Claude Haiku 4.5"   ,backend . claude-haiku-4-5-20251001)))
  nil)

;; -- OpenAI / ChatGPT -------------------------------------------------
;; Key in BW + Keychain `emacs_credentials' (field/account OPENAI_API_KEY).
;; Rotate via `M-x my/api-key-set'.
;; Force Chat Completions via an explicit endpoint to avoid the Responses API.
(let ((backend (gptel-make-openai "ChatGPT"
                  :stream t
                  :host "api.openai.com"
                  :endpoint "/v1/chat/completions"
                  :key (lambda () (my/api-key-fetch "OPENAI_API_KEY")))))
  (setq my/gptel-backends
        (append my/gptel-backends
                `(("GPT-4o"       ,backend . gpt-4o)
                  ("GPT-4o-mini"  ,backend . gpt-4o-mini)
                  ("o3-mini"      ,backend . o3-mini)
                  ("o4-mini"      ,backend . o4-mini)))))

;; -- Google Gemini (free tier: https://aistudio.google.com/apikey) --
;; Key in BW + Keychain `emacs_credentials' (field/account GEMINI_API_KEY).
;; Rotate via `M-x my/api-key-set'.
;; Free tier quotas vary per model (2.0 Flash has the most generous limits).
(let ((backend (gptel-make-gemini "Gemini"
                 :stream t
                 :key (lambda () (my/api-key-fetch "GEMINI_API_KEY")))))
  (setq my/gptel-backends
        (append my/gptel-backends
                `(("Gemini 2.5 Pro"     ,backend . gemini-2.5-pro)
                  ("Gemini 2.5 Flash"   ,backend . gemini-2.5-flash)
                  ("Gemini 2.0 Flash"   ,backend . gemini-2.0-flash)))))

;; -- Groq (free tier: https://console.groq.com/keys) ----------------
;; OpenAI-compatible. Key in BW + Keychain `emacs_credentials'
;; (field/account GROQ_API_KEY). Rotate via `M-x my/api-key-set'.
;; Very fast inference (~500 tok/s on Llama 70B).
(let ((backend (gptel-make-openai "Groq"
                 :stream t
                 :host "api.groq.com"
                 :endpoint "/openai/v1/chat/completions"
                 :key (lambda () (my/api-key-fetch "GROQ_API_KEY"))
                 :models '(llama-3.3-70b-versatile
                           llama-3.1-8b-instant
                           mixtral-8x7b-32768
                           qwen-qwq-32b))))
  (setq my/gptel-backends
        (append my/gptel-backends
                `(("Llama 3.3 70B (Groq)"   ,backend . llama-3.3-70b-versatile)
                  ("Llama 3.1 8B (Groq)"    ,backend . llama-3.1-8b-instant)
                  ("Mixtral 8x7B (Groq)"    ,backend . mixtral-8x7b-32768)
                  ("Qwen QwQ 32B (Groq)"    ,backend . qwen-qwq-32b)))))

;; -- GitHub Models (free dev tier: https://github.com/marketplace/models) -
;; Set GITHUB_TOKEN in secrets.el to a fine-grained PAT with "models" permission.
;; Tight per-day quotas; intended for dev/test. Model catalog changes — verify
;; IDs at github.com/marketplace/models if a call returns 404.
(let ((backend (gptel-make-openai "GitHub Models"
                 :stream t
                 :host "models.inference.ai.azure.com"
                 :endpoint "/chat/completions"
                 :key (lambda () (getenv "GITHUB_TOKEN"))
                 :models '(gpt-4o
                           gpt-4o-mini
                           Meta-Llama-3.1-405B-Instruct
                           Mistral-Large-2411
                           Phi-3.5-mini-instruct))))
  (setq my/gptel-backends
        (append my/gptel-backends
                `(("GPT-4o (GitHub)"            ,backend . gpt-4o)
                  ("GPT-4o-mini (GitHub)"       ,backend . gpt-4o-mini)
                  ("Llama 3.1 405B (GitHub)"    ,backend . Meta-Llama-3.1-405B-Instruct)
                  ("Mistral Large (GitHub)"     ,backend . Mistral-Large-2411)
                  ("Phi 3.5 Mini (GitHub)"      ,backend . Phi-3.5-mini-instruct)))))

;; -- LM Studio (local, OpenAI-compatible) ----------------------------
;; LM Studio must be running: Sidebar -> Local Server -> Start Server
;; Port: 1234 (default). No API key required.
;; Verify model IDs with: curl http://localhost:1234/v1/models
(let ((backend (gptel-make-openai "LM Studio"
                  :stream t
                  :protocol "http"
                  :host "localhost:1234"
                  :endpoint "/v1/chat/completions"
                  :key "lm-studio"
                  :models '(mistralai/ministral-3-14b-reasoning
                            deepseek-r1-distill-qwen-7b
                            gemma-4-31b-it
                            gemma-3-12b-it))))
  (setq my/gptel-backends
        (append my/gptel-backends
                `(("Ministral 3B 14B Reasoning (LM Studio)" ,backend . mistralai/ministral-3-14b-reasoning)
                  ("DeepSeek R1 7B (LM Studio)"             ,backend . deepseek-r1-distill-qwen-7b)
                  ("Gemma 4 31B (LM Studio)"                ,backend . gemma-4-31b-it)
                  ("Gemma 3 12B Q4 (LM Studio)"             ,backend . gemma-3-12b-it))))
  nil)

;; -- MLX (local, Apple Silicon, via mlx-lm standalone server) --------
;; Start server: mlx_lm.server --model mlx-community/Qwen3-14B-4bit --port 8080
(let ((backend (gptel-make-openai "MLX"
                  :stream t
                  :protocol "http"
                  :host "localhost:8080"
                  :endpoint "/v1/chat/completions"
                  :key "mlx"
                  :models '(mlx-community/Qwen3-14B-4bit
                            mlx-community/gemma-3-12b-it-4bit))))
  (setq my/gptel-backends
        (append my/gptel-backends
                `(("Qwen3 14B (MLX)"    ,backend . mlx-community/Qwen3-14B-4bit)
                  ("Gemma 3 12B (MLX)"  ,backend . mlx-community/gemma-3-12b-it-4bit)))))

;; -- Ollama (local) ---------------------------------------------------
;; Only activated when `ollama' is found in PATH.
;; Install models first: ollama pull <name>
(when (executable-find "ollama")
  (let ((backend (gptel-make-ollama "Ollama"
                   :stream t
                   :host my/gptel-ollama-host
                   :models '((qwen2.5:14b-instruct :capabilities (tool-use json))
                             (llama3.2 :capabilities (tool-use json))
                             (mistral :capabilities (tool-use json))
                             phi3
                             (deepseek-r1 :capabilities (tool-use json))))))
    (setq my/gptel-ollama-backend backend)
    (setq my/gptel-backends
          (append my/gptel-backends
                  `(("Qwen 2.5 Instruct 14B (Ollama)"  ,backend . qwen2.5:14b-instruct)
                    ("Llama 3.2 (Ollama)"             ,backend . llama3.2)
                    ("Mistral (Ollama)"               ,backend . mistral)
                    ("DeepSeek R1 (Ollama)"           ,backend . deepseek-r1)))))
  ;; Promote the new instruct model so the runtime's default-local-model
  ;; selection lands on it when Ollama has no model loaded yet.
  (setq my/gptel-default-local-model 'qwen2.5:14b-instruct
        my/gptel-default-local-model-label
        "Qwen 2.5 Instruct 14B (Ollama)")
  ;; Local default lives at the 14B; PR 11 router target points at
  ;; Opus for the rare list-completeness-critical cases that even Haiku
  ;; might miss. When no Anthropic key is set, both stay local-only.
  (setq my/gptel-high-fidelity-model
        (and (my/api-key-fetch "ANTHROPIC_API_KEY") 'claude-opus-4-7))
  ;; Ollama stays registered as an opt-in local backend. It no longer changes
  ;; the global gptel default during startup; choose it explicitly with
  ;; gptel's model/backend menu when local-only work is desired.
  nil)

;; -- Standard default: Gemini 2.0 Flash ------------------------------
;; Runs LAST so it overrides any earlier backend registration. 2.0 Flash has
;; the most generous free-tier quota (15 RPM / 1500 RPD) and is plenty for
;; daily use. Switch to 2.5 Flash/Pro or a local backend manually via
;; gptel-menu when needed.
(when-let* ((entry (assoc "Gemini 2.0 Flash" my/gptel-backends))
            (backend (cadr entry))
            (model (cddr entry)))
  (setq gptel-backend backend
        gptel-model   model)
  (my/emacs-agent-runtime-install-gptel-tools)
  (message "gptel default: Gemini 2.0 Flash%s"
           (if (my/api-key-fetch "GEMINI_API_KEY")
               ""
             " (M-x my/api-key-set GEMINI_API_KEY before sending requests)")))

)  ;; end (with-eval-after-load 'gptel ...)

;;; 60_emacs-agent-runtime.el --- gptel and Emacs agent runtime loader -*- lexical-binding: t; -*-

(require 'cl-lib)

(defvar my/gptel-backends nil)
(defvar my/gptel-ollama-backend nil)
(defvar gptel-backend)
(defvar gptel-model)
(defvar gptel-default-mode)
(defvar gptel-directives)
(defvar gptel-tools)
(defvar gptel-use-tools)
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
  '("*.el"
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
             (fboundp 'my/api-key-fetch)
             (boundp 'ear-adapter-api-credential-resolver))
    (setq ear-adapter-api-credential-resolver #'my/api-key-fetch)
    (when (boundp 'ear-adapter-api-credential-resolver-name)
      (setq ear-adapter-api-credential-resolver-name 'setup-keychain))
    (when (boundp 'ear-adapter-api-prefer-credential-resolver)
      (setq ear-adapter-api-prefer-credential-resolver t))))

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

(defun my/emacs-agent-runtime--apply-loaded-config ()
  "Apply setup-owned defaults after EAR has loaded."
  (when (fboundp 'emacs-agent-runtime-mode)
    (emacs-agent-runtime-mode 1))
  (when (boundp 'emacs-agent-runtime-cli-default-agent)
    (setq emacs-agent-runtime-cli-default-agent "codex"))
  (my/emacs-agent-runtime-apply-credential-resolver)
  (my/emacs-agent-runtime-apply-context-config)
  (my/emacs-agent-runtime-apply-qmd-config)
  (my/emacs-agent-runtime-apply-open-tool-policy)
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
        (require 'emacs-agent-runtime nil t)))
    (when (fboundp 'elpaca-wait)
      (elpaca-wait))))

(my/emacs-agent-runtime-queue-elpaca)

(defun my/emacs-agent-runtime-load ()
  "Load Emacs Agent Runtime from the configured source."
  (let ((dir (file-name-as-directory
              (expand-file-name my/emacs-agent-runtime-dir))))
    (cond
     ((featurep 'emacs-agent-runtime)
      (my/emacs-agent-runtime--apply-loaded-config))
     ((eq my/emacs-agent-runtime-source 'elpaca)
      (if (require 'emacs-agent-runtime nil t)
          (my/emacs-agent-runtime--apply-loaded-config)
        (message "emacs-agent-runtime not available from Elpaca package")
        nil))
     ((not (eq my/emacs-agent-runtime-source 'local))
      (message "Unknown my/emacs-agent-runtime-source: %S"
               my/emacs-agent-runtime-source)
      nil)
     ((not (file-directory-p dir))
      (message "emacs-agent-runtime directory missing: %s" dir)
      nil)
     (t
      (add-to-list 'load-path dir)
      (if (require 'emacs-agent-runtime nil t)
          (progn
            (my/emacs-agent-runtime--apply-loaded-config)
            (message "emacs-agent-runtime loaded from %s" dir)
            t)
        (message "emacs-agent-runtime not loadable from %s" dir)
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

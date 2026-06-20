;;; 60_gptel.el --- gptel and Emacs agent runtime loader -*- lexical-binding: t; -*-

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

(defun my/emacs-agent-runtime-load ()
  "Load the local neutral Emacs Agent Runtime when available."
  (let ((dir (file-name-as-directory
              (expand-file-name my/emacs-agent-runtime-dir))))
    (cond
     ((featurep 'emacs-agent-runtime)
      (when (boundp 'emacs-agent-runtime-cli-default-agent)
        (setq emacs-agent-runtime-cli-default-agent "codex"))
      t)
     ((not (file-directory-p dir))
      (message "emacs-agent-runtime directory missing: %s" dir)
      nil)
     (t
      (add-to-list 'load-path dir)
      (if (require 'emacs-agent-runtime nil t)
          (progn
            (when (fboundp 'emacs-agent-runtime-mode)
              (emacs-agent-runtime-mode 1))
            (when (boundp 'emacs-agent-runtime-cli-default-agent)
              (setq emacs-agent-runtime-cli-default-agent "codex"))
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

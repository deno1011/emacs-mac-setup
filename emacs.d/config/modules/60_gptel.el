;;; 60_gptel.el --- gptel agent runtime loader -*- lexical-binding: t; -*-

(defvar my/gptel-backends nil)
(defvar my/gptel-ollama-backend nil)
(defvar gptel-backend)
(defvar gptel-model)
(defvar gptel-default-mode)
(defvar gptel-directives)
(defvar gptel-agent-runtime-ollama-host)
(defvar gptel-agent-runtime-default-local-model)
(defvar gptel-agent-runtime-default-local-model-label)
(defvar gptel-agent-runtime-high-fidelity-model)

(declare-function gptel-make-anthropic "gptel-anthropic")
(declare-function gptel-make-openai "gptel-openai")
(declare-function gptel-make-gemini "gptel-gemini")
(declare-function gptel-make-ollama "gptel-ollama")
(declare-function gptel-agent-runtime-start-ollama-if-needed "gptel-agent-runtime")
(declare-function gptel-agent-runtime-sync-directive-for-current-runtime "gptel-agent-runtime")
(declare-function gptel-agent-runtime-sync-tools "gptel-agent-runtime")

;; Elpaca handles install. The use-package form's `:ensure (RECIPE)' below
;; tells elpaca to clone from deno1011/gptel-agent-runtime. Updates are
;; user-triggered (M-x elpaca-fetch-all) rather than silent background
;; pulls — keeps the install reproducible with the rest of the lockfile.

;; Install gptel FIRST — gptel-agent-runtime depends on it. If elpaca
;; queues the runtime ahead of gptel and tries to build it before gptel
;; is ready, the runtime fails its dependency check ("Condition
;; (finished . gptel) failed: gptel failed"). Putting gptel's
;; use-package here (instead of in the "Backends Setup" section below)
;; ensures elpaca queues + builds it ahead of the runtime.
(use-package gptel
  :ensure t
  :demand t
  :config
  (setq gptel-default-mode 'org-mode))

(use-package gptel-agent-runtime
  :ensure (gptel-agent-runtime
           :host github
           :repo "deno1011/gptel-agent-runtime"
           :branch "main")
  ;; No `:files' spec on purpose. elpaca's `:defaults' already globs
  ;; `*.el' at the top of the repo (which is where every `gar-*.el'
  ;; lives) and excludes the standard `*-tests.el' patterns. An
  ;; explicit `(:exclude "test" "docs" "scripts")' tripped elpaca's
  ;; recipe parser with a "Wrong type argument: stringp, nil" —
  ;; bare directory names without globs hit an edge case in
  ;; `:exclude'. The repo's `docs/' dir isn't a `.el' file so it
  ;; isn't picked up anyway; `test/' and `scripts/' don't exist at
  ;; the top level.
  :after gptel
  :demand t
  :config
  (message "gptel-agent-runtime loaded from package"))

;; gptel itself is declared higher up in this file (before
;; gptel-agent-runtime so it queues first). Backends are configured
;; here once BOTH gptel AND gptel-agent-runtime have loaded.
;;
;; Wait for `gptel-agent-runtime' (not `gptel') because gptel-agent-
;; runtime's `:config' block defines defvaralias mappings from our
;; `my/gptel-backends' / `my/gptel-ollama-backend' to its own internal
;; names. If we set `my/gptel-backends' BEFORE that alias is in place,
;; gptel-agent-runtime overwrites the value when it later sets up the
;; alias — Emacs emits "defvaralias: Overwriting value of
;; my/gptel-backends by aliasing to ...". Sequencing on
;; gptel-agent-runtime instead means the alias is established first,
;; then our `setq' flows through it correctly.
;;
;; Both packages are built by elpaca on `after-init-hook'; this block
;; runs once gptel-agent-runtime's `:config' has completed.
(with-eval-after-load 'gptel-agent-runtime

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
  (when (fboundp 'gptel-agent-runtime-start-ollama-if-needed)
    (gptel-agent-runtime-start-ollama-if-needed))
  (let ((backend (gptel-make-ollama "Ollama"
                   :stream t
                   :host (if (boundp 'gptel-agent-runtime-ollama-host)
                             gptel-agent-runtime-ollama-host
                           "localhost:11434")
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
  (setq gptel-agent-runtime-default-local-model 'qwen2.5:14b-instruct
        gptel-agent-runtime-default-local-model-label
        "Qwen 2.5 Instruct 14B (Ollama)")
  ;; Local default lives at the 14B; PR 11 router target points at
  ;; Opus for the rare list-completeness-critical cases that even Haiku
  ;; might miss. When no Anthropic key is set, both stay local-only.
  (setq gptel-agent-runtime-high-fidelity-model
        (and (my/api-key-fetch "ANTHROPIC_API_KEY") 'claude-opus-4-7))
  ;; Ollama stays registered as an opt-in local backend. It no longer changes
  ;; the global gptel default during startup; choose it explicitly with
  ;; `gptel-agent-runtime-select-model' when local-only work is desired.
  nil)

;; -- Standard default: Gemini 2.0 Flash ------------------------------
;; Runs LAST so it overrides any earlier backend registration. 2.0 Flash has
;; the most generous free-tier quota (15 RPM / 1500 RPD) and is plenty for
;; daily use. Switch to 2.5 Flash/Pro or a local backend manually via
;; `gptel-agent-runtime-select-model' / gptel-menu when needed.
(when-let* ((entry (assoc "Gemini 2.0 Flash" my/gptel-backends))
            (backend (cadr entry))
            (model (cddr entry)))
  (setq gptel-backend backend
        gptel-model   model)
  (when (fboundp 'gptel-agent-runtime-sync-directive-for-current-runtime)
    (gptel-agent-runtime-sync-directive-for-current-runtime))
  (when (fboundp 'gptel-agent-runtime-sync-tools)
    (gptel-agent-runtime-sync-tools))
  (message "gptel default: Gemini 2.0 Flash%s"
           (if (my/api-key-fetch "GEMINI_API_KEY")
               ""
             " (M-x my/api-key-set GEMINI_API_KEY before sending requests)")))

)  ;; end (with-eval-after-load 'gptel-agent-runtime ...)

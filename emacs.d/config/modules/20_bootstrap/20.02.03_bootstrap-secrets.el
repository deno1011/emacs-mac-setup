;;; 20.02.03_bootstrap-secrets.el --- Bootstrap Layer 2 secrets -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer 3):
;;   (my/api-key-fetch--from-secrets KEY-NAME) → string or nil
;;   (my/secrets-ensure-readable)              → :done / (:error MSG)
;;   (my/api-key-known-names)                  → list of strings
;;   (my/api-key-store KEY-NAME VALUE)         → :ok / (:error MSG)
;;   (my/api-key-set--interactive)             → :ok / nil
;;   (my/api-key-credential-descriptors)       → list of descriptor plists
;;   (my/credential-store ACCT VALUE &optional ALLOW-SKIP)
;;                                             → :ok / (:error MSG)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/secrets--api-key-fields
;;   my/secrets--skipped-sentinel
;;   my/secrets--service
;;   my/secrets--missing-keys
;;
;; Depends on (Layer 1):
;;   my/keychain-get                    ← 20.01.01_bootstrap-keychain
;;   my/keychain-set                    ← 20.01.01_bootstrap-keychain

(declare-function my/keychain-get "20.01.01_bootstrap-keychain")
(declare-function my/keychain-set "20.01.01_bootstrap-keychain")

(defconst my/secrets--service "emacs_credentials"
  "macOS Keychain service holding all bootstrap-relevant secrets.")

(defconst my/secrets--skipped-sentinel "__SKIPPED__"
  "Literal Keychain value meaning the user opted out of this key.
Treated as `no key' by `my/api-key-fetch--from-secrets' and as
`configured' by `my/secrets-ensure-readable'.")

(defconst my/secrets--api-key-fields
  '("OPENAI_API_KEY"
    "ANTHROPIC_API_KEY"
    "GEMINI_API_KEY"
    "GROQ_API_KEY")
  "Keychain accounts each holding one LLM backend's API key.
Read by `my/secrets-ensure-readable' for the status check.
Add an entry here when a new gptel backend is wired up.")

(defun my/secrets--missing-keys ()
  "Return the list of `my/secrets--api-key-fields' entries that
have NO Keychain record at all (neither a real value nor the
__SKIPPED__ sentinel). An empty list means the user has made
an explicit decision for every supported backend."
  (seq-filter
   (lambda (key)
     (null (my/keychain-get my/secrets--service key)))
   my/secrets--api-key-fields))

(defun my/api-key-fetch--from-secrets (key-name)
  "Return the active API key value for KEY-NAME, or nil.

KEY-NAME is a string like \"OPENAI_API_KEY\". Reads
emacs_credentials/KEY-NAME from Keychain. Returns:

  - the stored string when a real key is configured
  - nil when no Keychain entry exists
  - nil when the entry holds the __SKIPPED__ sentinel
    (user opted out — gptel treats this exactly like
    \"no backend configured\")

Layer 3's `my/api-key-fetch' delegates to this function via
`fboundp' so feature modules see a consistent API regardless
of whether Layer 2 has loaded yet."
  (let ((value (my/keychain-get my/secrets--service key-name)))
    (cond
     ((null value) nil)
     ((string= value my/secrets--skipped-sentinel) nil)
     (t value))))

(defun my/secrets-ensure-readable ()
  "Verify every API-key field is either set or explicitly skipped.

Returns:
  - :done when every entry in `my/secrets--api-key-fields' has a
    Keychain record (a real key value OR the __SKIPPED__ sentinel)
  - (:error MSG) when at least one field has no Keychain record;
    MSG names the missing fields and carries the verbatim shell
    commands to either set or mark-skipped each one

This is an OPT step in the orchestrator: a failure surfaces in
the final Bootstrap message and in the *Warnings* buffer's
optional-failures list, but does NOT halt the bootstrap. gptel
handles missing keys at use time by reporting `no backend
configured' for the affected entry.

Idempotent: re-running after every field is decided returns
:done with no side effects."
  (let ((missing (my/secrets--missing-keys)))
    (cond
     ((null missing) :done)
     (t
      `(:error
        ,(format "API keys not yet configured (or marked __SKIPPED__): %s.

For each missing field, EITHER set a real value:

    security add-generic-password \\
      -s %s -a <FIELD> \\
      -w \"<api-key-value>\"

OR mark it permanently skipped (gptel will report \
\"no backend configured\" for that field, no further nag):

    security add-generic-password \\
      -s %s -a <FIELD> \\
      -w \"%s\""
                 (mapconcat #'identity missing ", ")
                 my/secrets--service
                 my/secrets--service
                 my/secrets--skipped-sentinel))))))

(defun my/api-key-known-names ()
  "Return the supported API-key Keychain accounts as a list of
strings (e.g. \"OPENAI_API_KEY\", \"ANTHROPIC_API_KEY\", …).

Layer 3's `my/api-key-set' uses this list to drive
completing-read so the user can only type a key name the
secrets module knows about. Returns a fresh copy so callers
can mutate it without affecting the constant."
  (copy-sequence my/secrets--api-key-fields))

(defun my/api-key-store (key-name value)
  "Set Keychain entry for KEY-NAME to VALUE.

VALUE is normalised:
  - nil or empty string → stored as the __SKIPPED__ sentinel
    (the user's explicit opt-out signal)
  - any other string    → stored verbatim

Returns :ok / (:error MSG) from the underlying Layer-1
`my/keychain-set'. Does not validate KEY-NAME against the
known-names list — caller is responsible for that, which
the interactive entry point does via completing-read."
  (let ((normalized
         (cond
          ((or (null value) (string-empty-p value))
           my/secrets--skipped-sentinel)
          (t value))))
    (my/keychain-set my/secrets--service key-name normalized)))

(defun my/api-key-set--interactive ()
  "Interactive form to set or rotate one API key.

Two prompts:
  1. Key name (completing-read over `my/api-key-known-names',
     `confirm' mode so the user can also type a custom name —
     useful if a new backend was added to the gptel config
     before the secrets list caught up).
  2. Value (`read-passwd' so the entry does not echo).

An empty value is taken as \"mark this backend permanently
skipped\" — the entry is stored as the __SKIPPED__ sentinel.

Returns :ok on a successful store, nil on (:error …) (caller
can chain). The result is also surfaced through `message' so
the user sees confirmation in the echo area."
  (interactive)
  (let* ((known  (my/api-key-known-names))
         (key    (completing-read "Set API key: " known nil 'confirm))
         (prompt (format "Value for %s (empty = mark __SKIPPED__): " key))
         (value  (read-passwd prompt))
         (result (my/api-key-store key value)))
    (cond
     ((eq result :ok)
      (message "my/api-key-set: %s stored." key)
      :ok)
     (t
      (message "my/api-key-set failed for %s: %s" key (cadr result))
      nil))))

(defun my/api-key-credential-descriptors ()
  "Return descriptor plists for every API key this module manages.

Each plist has the shape:
  (:account ACCT :label LBL :secret t :allow-skip t)

Consumed by Layer 3's unified `my/credential-set' form, which
collects descriptors from every Layer-2 module."
  (mapcar (lambda (account)
            (list :account account
                  :label (format "API key — %s" account)
                  :secret t
                  :allow-skip t))
          my/secrets--api-key-fields))

(defun my/credential-store (account value &optional allow-skip)
  "Store VALUE in `emacs_credentials/ACCOUNT' on the Keychain.

When ALLOW-SKIP is non-nil and VALUE is nil or the empty string,
the entry is written as the `__SKIPPED__' sentinel — the
user's explicit opt-out signal. When ALLOW-SKIP is nil and
VALUE is empty, the call refuses with (:error \"value required\")
without touching the Keychain.

Returns :ok / (:error MSG)."
  (cond
   ((or (null value) (string-empty-p value))
    (cond
     (allow-skip
      (my/keychain-set my/secrets--service account
                       my/secrets--skipped-sentinel))
     (t '(:error "value required (this credential cannot be left empty)"))))
   (t (my/keychain-set my/secrets--service account value))))

(provide 'my-bootstrap-secrets)
;;; 20.02.03_bootstrap-secrets.el ends here

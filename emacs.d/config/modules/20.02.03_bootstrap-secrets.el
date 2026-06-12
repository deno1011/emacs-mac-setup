;;; 20.02.03_bootstrap-secrets.el --- Bootstrap Layer 2 secrets -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer 3):
;;   (my/api-key-fetch--from-secrets KEY-NAME) → string or nil
;;   (my/secrets-ensure-readable)              → :done / (:error MSG)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/secrets--api-key-fields
;;   my/secrets--skipped-sentinel
;;   my/secrets--service
;;   my/secrets--missing-keys
;;
;; Depends on (Layer 1):
;;   my/keychain-get                    ← 20.01.01_bootstrap-keychain

(declare-function my/keychain-get "20.01.01_bootstrap-keychain")

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

(provide 'my-bootstrap-secrets)
;;; 20.02.03_bootstrap-secrets.el ends here

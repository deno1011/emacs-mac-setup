;;; 20.03.01_bootstrap.el --- Bootstrap Layer 3 main entry -*- lexical-binding: t -*-
;;
;; Public API (callable from any feature module):
;;   my/data-dir                            ← defvar, string path OR :not-resolved
;;   (my/api-key-fetch KEY-NAME)            → string or nil
;;   (my/api-key-set)                       ← interactive: API keys only
;;   (my/credential-set)                    ← interactive: any bootstrap credential
;;   (my/bootstrap)                         ← interactive orchestrator
;;   (my/bootstrap-ready-p)                 → t when bootstrap converged
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/bootstrap--ensure-steps             ← list of (LABEL FN REQUIRED) triples
;;   my/bootstrap--failed-p                 ← non-nil after a required failure
;;   my/bootstrap--run-step                 ← runs one ensure-* with fboundp gate
;;   my/bootstrap--format-result            ← aggregates Layer-2 results
;;   my/bootstrap--halt                     ← emits warning + message + signals
;;   my/bootstrap--repair-hint              ← per-step repair hint fallback
;;
;; Depends on (Layer 2 — declared, not yet implemented):
;;   my/secrets-ensure-readable      ← 20.02.NN_bootstrap-secrets
;;   my/repo-ensure-cloned           ← 20.02.NN_bootstrap-repo
;;   my/identity-ensure-loaded       ← 20.02.NN_bootstrap-identity
;;   my/data-dir-resolve             ← 20.02.NN_bootstrap-repo
;;   my/api-key-fetch--from-secrets  ← 20.02.NN_bootstrap-secrets

(declare-function my/secrets-ensure-readable            "20.02.03_bootstrap_secrets")
(declare-function my/repo-ensure-cloned                 "20.02.02_bootstrap_repo_clone")
(declare-function my/identity-ensure-loaded             "20.02.04_bootstrap_identity")
(declare-function my/data-dir-resolve                   "20.02.01_bootstrap_repo")
(declare-function my/api-key-fetch--from-secrets        "20.02.03_bootstrap_secrets")
(declare-function my/api-key-set--interactive           "20.02.03_bootstrap_secrets")
(declare-function my/credential-store                   "20.02.03_bootstrap_secrets")
(declare-function my/repo-credential-descriptors        "20.02.01_bootstrap_repo")
(declare-function my/repo-clone-credential-descriptors  "20.02.02_bootstrap_repo_clone")
(declare-function my/api-key-credential-descriptors     "20.02.03_bootstrap_secrets")
(declare-function my/identity-credential-descriptors    "20.02.04_bootstrap_identity")

(defvar my/data-dir :not-resolved
  "Absolute path of the user's data folder, or `:not-resolved'.
Until the Layer-2 resolver runs successfully this is the symbol
`:not-resolved'. Any feature module that uses it without first
checking `my/bootstrap-ready-p' will type-error on its first
`expand-file-name' call — by design, see this module's docstring
under \"Why the :not-resolved sentinel\".

Read by every feature module that stores data under a
user-configurable directory (30-core, 40-org, 50-apple-reminders,
60-gptel, 70-wiki, 80-gtd). The contract with these modules is
in BOOTSTRAP.md §4.")

(defvar my/bootstrap--failed-p nil
  "Non-nil after a required Layer-2 step has returned (:error …).
Reset to nil at the START of every `my/bootstrap' run, then set
to t the moment a required step fails. Read by
`my/bootstrap-ready-p' which is the public predicate feature
modules consult.")

(defvar my/bootstrap--ensure-steps
  '(("data-folder resolution"  my/data-dir-resolve        t)
    ("data-folder clone"       my/repo-ensure-cloned      t)
    ("github identity"         my/identity-ensure-loaded  nil)
    ("secrets readable"        my/secrets-ensure-readable nil))
  "Ordered list of (LABEL FUNCTION-SYMBOL REQUIRED) triples.
LABEL is a short human-readable name for the *Warnings* buffer.
FUNCTION-SYMBOL is a Layer-2 function expected to return
:done / :skip / (:error MSG). REQUIRED is t for steps whose
failure halts the bootstrap, nil for steps whose failure is
logged but does not halt.")

(defun my/bootstrap--run-step (step)
  "Run STEP — a (LABEL FN REQUIRED) triple — and return
(LABEL REQUIRED RESULT) where RESULT is :done, :skip, or
(:error MSG). The REQUIRED flag is passed through so the
caller can decide whether to halt.

If the function is not bound (Layer 2 hasn't written it yet),
RESULT is (:error \"pending: <fn> not yet defined\"). This is
an honest report, not a silent skip — the user sees the exact
reason the step did not run."
  (let* ((label    (nth 0 step))
         (fn       (nth 1 step))
         (required (nth 2 step))
         (result
          (cond
           ((not (fboundp fn))
            `(:error ,(format "pending: %s not yet defined" fn)))
           (t (condition-case err
                  (funcall fn)
                (error `(:error ,(format "uncaught signal: %s"
                                         (error-message-string err)))))))))
    (list label required result)))

(defun my/bootstrap--format-result (results)
  "Render RESULTS (a list of (LABEL REQUIRED OUTCOME) triples) as a
single human-readable line for the *Messages* buffer."
  (mapconcat
   (lambda (triple)
     (let ((label   (nth 0 triple))
           (outcome (nth 2 triple)))
       (format "%s=%s"
               label
               (cond ((eq outcome :done) "done")
                     ((eq outcome :skip) "skip")
                     ((and (consp outcome) (eq (car outcome) :error))
                      (format "error(%s)" (cadr outcome)))
                     (t (format "?(%s)" outcome))))))
   results
   "; "))

(defun my/bootstrap--repair-hint (fn)
  "Return a one-paragraph human repair hint for FN, the Layer-2
symbol of the step that failed. The actual error message from
the step is used verbatim by `my/bootstrap--halt'; this hint
adds the SPECIFIC next-action for cases that don't carry one."
  (cond
   ((not (fboundp fn))
    (format "Layer-2 module that implements `%s' is not yet on disk.
This is expected during the rewrite from the legacy
20-bootstrap.org. See BOOTSTRAP.md for the layer status."
            fn))
   (t "See the WHY message above for the specific cause. The
Layer-2 step is responsible for stating the concrete repair
command in its error payload.")))

(defun my/bootstrap--halt (label fn err-msg)
  "Surface a required-step failure and abort the orchestrator.
LABEL is the human step name. FN is the Layer-2 function symbol.
ERR-MSG is the (:error MSG) payload from the step.

Emits a `display-warning' at :emergency level with a structured
WHAT / WHY / FIX block, plus a one-line `message' nudge pointing
at *Warnings*. Sets `my/bootstrap--failed-p' to t and signals an
error so the load-time auto-fire stops cleanly."
  (setq my/bootstrap--failed-p t)
  (display-warning
   'emacs-setup
   (format
    "Bootstrap halted at required step: %s

WHY: %s

FIX: %s

After fixing, run  M-x my/bootstrap  to retry.

Feature modules that depend on `my/data-dir' will NOT execute
correctly until this step succeeds. See BOOTSTRAP.md §5 for the
public-contract details."
    label err-msg (my/bootstrap--repair-hint fn))
   :emergency)
  (message "Bootstrap halted at %s — see *Warnings* for repair instructions" label)
  (error "Bootstrap halted at %s: %s" label err-msg))

(defun my/bootstrap-ready-p ()
  "Return t when bootstrap has converged: no required step failed
AND `my/data-dir' resolves to a real string path.

Feature modules that depend on `my/data-dir' should wrap their
configuration in `(when (my/bootstrap-ready-p) …)' so they
short-circuit gracefully on bootstrap failure instead of
type-erroring on the `:not-resolved' sentinel."
  (and (not my/bootstrap--failed-p)
       (stringp my/data-dir)))

(defun my/api-key-fetch (key-name)
  "Return the credential for KEY-NAME (a string like \"OPENAI_API_KEY\").
Returns nil if the secret is not configured.

Delegates to Layer 2's `my/api-key-fetch--from-secrets' when
present. While Layer 2 is being built this function returns nil
unconditionally, which is the correct behaviour for feature
modules: they treat a missing key as \"no backend configured\" and
surface a setup instruction to the user."
  (if (fboundp 'my/api-key-fetch--from-secrets)
      (my/api-key-fetch--from-secrets key-name)
    nil))

(defun my/api-key-set ()
  "Interactively store a new value for one of the configured API keys.

Layer-3 entry point. Delegates to Layer-2's
`my/api-key-set--interactive' when it is loaded; falls back to
a pending-state message when the secrets module is missing
(skeleton / partial load state). The interactive prompt loop,
the completion list, and the Keychain write all live in
Layer 2.

See also `my/credential-set' for the unified form that covers
GitHub credentials in addition to API keys."
  (interactive)
  (cond
   ((fboundp 'my/api-key-set--interactive)
    (my/api-key-set--interactive))
   (t (message
       "my/api-key-set: pending — Layer-2 secrets module not loaded"))))

(defun my/bootstrap--all-credential-descriptors ()
  "Collect descriptor plists from every Layer-2 module that exposes
its credentials, deduplicated by `:account'. Order of preference:
repo → repo-clone → identity → secrets. The first occurrence of
each account wins so the label closest to the owning REQ step is
shown."
  (let ((seen (make-hash-table :test 'equal))
        (out '()))
    (dolist (fn '(my/repo-credential-descriptors
                  my/repo-clone-credential-descriptors
                  my/identity-credential-descriptors
                  my/api-key-credential-descriptors))
      (when (fboundp fn)
        (dolist (d (funcall fn))
          (let ((acct (plist-get d :account)))
            (unless (gethash acct seen)
              (puthash acct t seen)
              (push d out))))))
    (nreverse out)))

(defun my/credential-set ()
  "Interactively set or rotate any bootstrap-managed credential.

Collects descriptors from every loaded Layer-2 module
(`my/<domain>-credential-descriptors'), presents a single
completing-read menu over all of them, then prompts for the
value — `read-passwd' for secrets, `read-string' otherwise.

Empty input:
  - if the descriptor's :allow-skip is t, the entry is stored
    as the `__SKIPPED__' sentinel (opt-out)
  - if :allow-skip is nil, the call refuses with a message
    and no Keychain mutation

After a successful store, suggests `M-x my/bootstrap' to
re-run the orchestrator so the change takes effect on
already-running Emacs."
  (interactive)
  (cond
   ((not (fboundp 'my/credential-store))
    (message
     "my/credential-set: pending — Layer-2 secrets module not loaded"))
   (t
    (let* ((descriptors (my/bootstrap--all-credential-descriptors))
           (by-label    (mapcar (lambda (d)
                                  (cons (plist-get d :label) d))
                                descriptors))
           (label       (completing-read "Set credential: "
                                         (mapcar #'car by-label)
                                         nil t))
           (descriptor  (cdr (assoc label by-label)))
           (account     (plist-get descriptor :account))
           (secret?     (plist-get descriptor :secret))
           (skip?       (plist-get descriptor :allow-skip))
           (hint        (cond
                         (skip? " (empty = mark __SKIPPED__)")
                         (t     " (required)")))
           (prompt      (format "%s%s: " label hint))
           (value       (if secret?
                            (read-passwd prompt)
                          (read-string prompt)))
           (result      (my/credential-store account value skip?)))
      (cond
       ((eq result :ok)
        (message "my/credential-set: %s stored — run M-x my/bootstrap to apply"
                 account)
        :ok)
       (t
        (message "my/credential-set: %s NOT stored: %s"
                 account (cadr result))
        nil))))))

(defun my/bootstrap ()
  "Run the bootstrap subsystem to bring Emacs to a ready state.
Idempotent: every Layer-2 ensure-* is required to return
:done / :skip / (:error MSG) and to be safely re-runnable.

Halts on the first required-step failure (per BOOTSTRAP.md §5.5)
with a *Warnings* popup and a one-line *Messages* nudge. Non-
required failures are collected and surfaced in the final
message but do not halt the loop."
  (interactive)
  (setq my/bootstrap--failed-p nil)
  (let (results)
    (catch 'halt
      (dolist (step my/bootstrap--ensure-steps)
        (let* ((triple   (my/bootstrap--run-step step))
               (label    (nth 0 triple))
               (required (nth 1 triple))
               (outcome  (nth 2 triple)))
          (push triple results)
          (when (and required
                     (consp outcome)
                     (eq (car outcome) :error))
            (my/bootstrap--halt label (nth 1 step) (cadr outcome))
            (throw 'halt nil)))))
    (setq results (nreverse results))
    (message "Bootstrap: %s" (my/bootstrap--format-result results))
    results))

(condition-case _err
    (my/bootstrap)
  (error nil))

(provide 'my-bootstrap)
;;; 20.03.01_bootstrap.el ends here

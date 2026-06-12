;;; 20.03.01_bootstrap.el --- Bootstrap Layer 3 main entry -*- lexical-binding: t -*-
;;
;; Public API (callable from any feature module):
;;   my/data-dir                            ← defvar, string path
;;   (my/api-key-fetch KEY-NAME)            → string or nil
;;   (my/api-key-set)                       ← interactive rotator (not yet wired)
;;   (my/bootstrap)                         ← interactive orchestrator
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/bootstrap--ensure-steps             ← list of (LABEL . FN-SYMBOL) pairs
;;   my/bootstrap--run-step                 ← runs one ensure-* with fboundp gate
;;   my/bootstrap--format-result            ← aggregates Layer-2 results
;;
;; Depends on (Layer 2 — declared, not yet implemented):
;;   my/secrets-ensure-readable      ← 20.02.NN_bootstrap-secrets
;;   my/repo-ensure-cloned           ← 20.02.NN_bootstrap-repo
;;   my/identity-ensure-loaded       ← 20.02.NN_bootstrap-identity
;;   my/data-dir-resolve             ← 20.02.NN_bootstrap-repo
;;   my/api-key-fetch--from-secrets  ← 20.02.NN_bootstrap-secrets

(declare-function my/secrets-ensure-readable        "20.02.NN_bootstrap-secrets")
(declare-function my/repo-ensure-cloned             "20.02.NN_bootstrap-repo")
(declare-function my/identity-ensure-loaded         "20.02.NN_bootstrap-identity")
(declare-function my/data-dir-resolve               "20.02.NN_bootstrap-repo")
(declare-function my/api-key-fetch--from-secrets    "20.02.NN_bootstrap-secrets")

(defvar my/data-dir
  (file-name-as-directory (expand-file-name user-emacs-directory))
  "Absolute path of the user's data folder.
Initialised here to `user-emacs-directory' as a safe default.
Resolved to the real value (from Keychain) by
`my/data-dir-resolve' once the Layer-2 repo module lands.

Read by every feature module that stores data under a
user-configurable directory (30-core, 40-org, 50-apple-reminders,
60-gptel, 70-wiki, 80-gtd). The contract with these modules is
in BOOTSTRAP.md §4.")

(defvar my/bootstrap--ensure-steps
  '(("data-folder resolution"  . my/data-dir-resolve)
    ("data-folder clone"       . my/repo-ensure-cloned)
    ("github identity"         . my/identity-ensure-loaded)
    ("secrets readable"        . my/secrets-ensure-readable))
  "Ordered list of (LABEL . FUNCTION-SYMBOL) for the orchestrator.
Each FUNCTION-SYMBOL points at a Layer-2 function expected to
return :done / :skip / (:error MSG). Functions not yet bound
report as pending; see `my/bootstrap--run-step'.")

(defun my/bootstrap--run-step (step)
  "Run STEP — a (LABEL . FUNCTION-SYMBOL) pair — and return
(LABEL . RESULT) where RESULT is :done, :skip, or (:error MSG).

If the function is not bound (Layer 2 hasn't written it yet),
RESULT is (:error \"pending: <function-name> not yet defined\").
This is an honest report, not a silent skip — the user sees the
exact reason the step did not run."
  (let* ((label (car step))
         (fn    (cdr step)))
    (cons label
          (if (fboundp fn)
              (condition-case err
                  (funcall fn)
                (error `(:error ,(format "uncaught signal: %s"
                                         (error-message-string err)))))
            `(:error ,(format "pending: %s not yet defined" fn))))))

(defun my/bootstrap--format-result (results)
  "Render RESULTS (a list of (LABEL . OUTCOME) cells) as a single
human-readable line for the *Messages* buffer."
  (mapconcat
   (lambda (cell)
     (let ((label   (car cell))
           (outcome (cdr cell)))
       (format "%s=%s"
               label
               (cond ((eq outcome :done) "done")
                     ((eq outcome :skip) "skip")
                     ((and (consp outcome) (eq (car outcome) :error))
                      (format "error(%s)" (cadr outcome)))
                     (t (format "?(%s)" outcome))))))
   results
   "; "))

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
Stub until Layer 2's secrets module lands. Reports the pending
state instead of pretending to succeed."
  (interactive)
  (message "my/api-key-set: pending — Layer-2 secrets module not yet written"))

(defun my/bootstrap ()
  "Run the bootstrap subsystem to bring Emacs to a ready state.
Idempotent: every Layer-2 ensure-* is required to return
:done / :skip / (:error MSG) and to be safely re-runnable.

Currently a skeleton: most steps are not yet implemented in
Layer 2 and will report (:error \"pending\") until they land."
  (interactive)
  (let ((results (mapcar #'my/bootstrap--run-step my/bootstrap--ensure-steps)))
    (message "Bootstrap: %s" (my/bootstrap--format-result results))
    results))

(when (fboundp 'my/data-dir-resolve)
  (let ((result (my/data-dir-resolve)))
    (when (and (consp result) (eq (car result) :ok))
      (setq my/data-dir (file-name-as-directory (cadr result))))))

(provide 'my-bootstrap)
;;; 20.03.01_bootstrap.el ends here

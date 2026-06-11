;;; !00_startfirst.el --- Source-loaded module that bootstraps elpaca   -*- lexical-binding: t; -*-
;;; -*- no-byte-compile: t -*-
;;
;; Why this file exists, why it's named `!00_startfirst.el', and why it
;; is the ONLY module in `modules/' that gets loaded as SOURCE instead
;; of tangled-from-.org-then-byte-compiled.
;;
;; ---------------------------------------------------------------------
;; The macro / byte-compile / elpaca interaction
;; ---------------------------------------------------------------------
;;
;; `(elpaca …)' is an Emacs Lisp MACRO defined in `elpaca.el'. Macros
;; are expanded at compile / load time, BEFORE any of their arguments
;; are evaluated. If the compiler doesn't know `elpaca' is a macro,
;; it compiles `(elpaca FOO …)' as a regular function call. When the
;; byte-compiled file later loads, the bytecode tries to FUNCALL
;; `elpaca', which fails because by then `elpaca' is a macro and not
;; a function.
;;
;; The elpaca bootstrap PATTERN — clone elpaca into ~/.emacs.d/elpaca,
;; require it, then call `(elpaca elpaca-use-package …)' — needs the
;; macro to be DEFINED-AND-USED in the same file. That works in
;; init.el (which Emacs reads as source, one form at a time), or in
;; any other file loaded as source. It does NOT work in a file that
;; gets byte-compiled BEFORE the let block that requires elpaca has
;; a chance to register the macro.
;;
;; ---------------------------------------------------------------------
;; The naming convention `!00_…' (loaded first, no byte-compile)
;; ---------------------------------------------------------------------
;;
;; config.org's discovery loop globs `modules/*.org' and `modules/*.el'
;; and sorts them lexicographically. ASCII `!' is 0x21, before `0' at
;; 0x30, so `!00_*.el' sorts to position 1 — earlier than any
;; numbered module.
;;
;; `my/-load-module' in config.org has a special case for `!'-prefixed
;; .el files: it SKIPS the byte-compile step entirely and just calls
;; `(load PATH)' on the source. The two cooperating mechanisms — the
;; `!' name prefix and the `no-byte-compile: t' file-local variable
;; — protect this file from the byte-compile trap in two independent
;; ways (defence in depth: if a future change to the loader forgets
;; the `!' rule, the file-local variable still applies).
;;
;; ---------------------------------------------------------------------
;; What belongs here vs. in a regular .org module
;; ---------------------------------------------------------------------
;;
;; THIS FILE is reserved for code that needs source-load semantics —
;; specifically: code that DEFINES a macro (via `require') and CALLS
;; that macro within the same module. As of this writing the only
;; example is the elpaca bootstrap below.
;;
;; Do NOT put general feature configuration here. Anything that
;; doesn't strictly need source-load belongs in a numbered .org
;; module (00-startfirst.org, 20-bootstrap.org, …) where it gets the
;; benefit of org-mode prose + literate code blocks + byte-compile
;; caching.
;;
;; Triggers for adding more code here would be:
;;   - You're integrating another package-manager macro family that
;;     follows the same self-bootstrapping pattern as elpaca.
;;   - You're defining a macro in `modules/' that you also need to
;;     use during the same module's load.
;; Anything else, prefer a regular .org module.

;; ============================================================
;; Step 0 — Package manager (elpaca)
;; ============================================================
;;
;; Same code that used to live in init.el's section 3. Moved here so
;; init.el stays thin (only what config.org and elpaca's bootstrap
;; agree on: data-dir, config-dir, secrets loader, custom.el) and so
;; the elpaca block can sit alongside the rest of the module-level
;; configuration. The source-load semantics are preserved by THIS
;; FILE being a source-loaded module rather than a tangled-and-
;; compiled one.

(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca-activate)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-sources-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (<= emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
                                                      (list (format "--depth=%d" depth) "--no-single-branch"))
                                                  ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                        "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

(elpaca elpaca-use-package
  (require 'elpaca-use-package)
  (elpaca-use-package-mode))
(elpaca-wait)
(setq use-package-always-ensure t)

;;; !00_startfirst.el ends here

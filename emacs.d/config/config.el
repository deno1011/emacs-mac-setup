(defvar my/modules-dir
  (expand-file-name "modules/" my/config-dir)
  "Directory holding the literate (.org) and vendored (.el) modules
discovered by config.org. .org files are tangled + byte-compiled +
loaded; vendored .el files (no .org sibling) are byte-compiled +
loaded directly UNLESS their basename starts with `!' — those are
SOURCE-LOADED with no byte-compile (see `my/-load-module' for the
why). install.sh's `6c. Vendor async-tasks' step writes one such
byte-compiled .el; `modules/!00_startfirst.el' is the source-loaded
one (elpaca bootstrap).")

(defun my/-load-module (path)
  "Load PATH (either .org source or vendored .el). Prefer the
byte-compiled .elc when newer than the source. Errors in any
module are logged but do not abort the overall config load.

  PATH basename starts with `!'  → source-load PATH (no byte-compile,
                                   no .elc cache). Reserved for files
                                   that DEFINE-AND-USE a macro within
                                   the same load (e.g. elpaca
                                   bootstrap); byte-compiling such a
                                   file freezes the macro call as a
                                   function call against an undefined
                                   symbol, then the runtime funcall
                                   fails once the macro IS registered.
                                   The `!' sorts ASCII-before `0', so
                                   such files run first in the
                                   discovery loop's `string<' order.

  .org source                    → tangle to .el + byte-compile + load
  .el  source (no `!' prefix)    → byte-compile + load
  .elc current                   → load directly (~10 ms), no tangle /
                                   compile"
  (let* ((base (file-name-sans-extension path))
         (el   (concat base ".el"))
         (elc  (concat el  "c"))
         (name (file-name-nondirectory path))
         (org? (string-suffix-p ".org" path))
         (source-load? (string-prefix-p "!" name)))
    (condition-case err
        (cond
         ;; Source-load (no byte-compile, no .elc).
         (source-load?
          (load path nil 'nomessage))
         ;; .elc current relative to whichever source file we got — load.
         ((and (file-exists-p elc)
               (file-newer-than-file-p elc path))
          (load elc nil 'nomessage))
         ;; Literate source → tangle then byte-compile then load.
         (org?
          (require 'ob-tangle)
          (org-babel-tangle-file path el)
          (byte-compile-file el)
          (load (if (file-exists-p elc) elc el) nil 'nomessage))
         ;; Vendored .el (no .org sibling) → byte-compile + load directly.
         (t
          (byte-compile-file el)
          (load (if (file-exists-p elc) elc el) nil 'nomessage)))
      (error
       (message "CONFIG LOAD ERROR (%s): %s"
                (file-name-nondirectory path) err)))))

(defun my/-discover-modules (dir)
  "Return a flat list of loadable module paths under DIR, in load order.

Walks DIR recursively. At each level entries (files AND
subdirectories together) are sorted by name and processed in
that order. The flattened result is the list of paths to feed
into `my/-load-module', already in the order they should load.

For each entry encountered:

  - .org file              → included as-is
  - .el file               → included ONLY when no same-name .org
                             sibling exists in the same directory
                             (vendored sources; .org wins otherwise
                             because the tangle re-emits the .el)
  - subdirectory           → entered recursively; its flattened
                             contents are slotted into the parent's
                             sort sequence AT the subdirectory's own
                             name position
  - anything else           → skipped (README.md, .DS_Store, etc.)

Sort order across files and subdirectories means a top-level
subdir `20_bootstrap/' loads after `10-tasks.el' and before
`30-core.org' — the directory's name participates in the same
`string<' comparison as sibling files. Within the subdir, the
same rule applies recursively.

Dot-prefixed entries are filtered by the `^[^.]' regex passed
to `directory-files', skipping `.', `..', `.DS_Store', etc."
  (let ((entries (sort (directory-files dir t "^[^.]") #'string<)))
    (mapcan
     (lambda (entry)
       (cond
        ((file-directory-p entry)
         (my/-discover-modules entry))
        ((string-suffix-p ".org" entry)
         (list entry))
        ((string-suffix-p ".el" entry)
         (let ((org-sibling
                (concat (file-name-sans-extension entry) ".org")))
           (unless (file-exists-p org-sibling)
             (list entry))))
        (t nil)))
     entries)))

(when (file-directory-p my/modules-dir)
  (let ((live (seq-remove
               (lambda (p) (string-match-p "\\.disabled\\.org\\'" p))
               (my/-discover-modules my/modules-dir))))
    (dolist (f live)
      (my/-load-module f))))

;; Per-Mac override — loads LAST, can shadow anything above. Optional.
(let ((local (expand-file-name "local.org" my/config-dir)))
  (when (file-exists-p local) (my/-load-module local)))

;; Bootstrap is invoked synchronously at the END of the 20-bootstrap
;; module's own tangled block (see Step 9 of modules/20-bootstrap.org)
;; so the form opens — and `my/data-dir' is settled, the data repo is
;; cloned, and starter content is generated — BEFORE the discovery
;; loop continues on to 30-core / 40-org / 50-apple-reminders / etc.
;; This way every subsequent module loads with the final `my/data-dir'
;; in place, and `org-agenda-files', `org-apple-reminders-sync-file',
;; etc. resolve to the chosen path on the FIRST launch. Nothing left
;; to do on `emacs-startup-hook'.

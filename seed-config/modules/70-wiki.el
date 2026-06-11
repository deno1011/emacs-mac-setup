;;; 70-wiki.el --- LLM-maintained Emacs wiki -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)

(defvar my/data-dir)
(defvar my/gptel-backends)
(defvar gptel-backend)
(defvar gptel-directives)
(defvar gptel-model)
(defvar gptel--system-message)
(defvar gptel-use-context)

(declare-function gptel-mode "gptel")
(declare-function gptel-send "gptel")

(defvar my/wiki-base-dir (expand-file-name "wiki/emacs/" my/data-dir)
  "Root of the Emacs-knowledge LLM Wiki. Derived from `my/data-dir' so
the wiki lives inside whatever GH_REPO the user chose at install time
(~/emacs/ by default; ~/emacs-data/ etc. for custom installs).")

(defvar my/wiki-preferred-model nil
  "Label in `my/gptel-backends' used for wiki sessions opened by the
helpers in this file.

nil means inherit the normal gptel backend/model selected during setup
(for example Gemini 2.0 Flash on a fresh install).  Set this to a label
from `my/gptel-backends' only when the wiki should deliberately use a
different model for a specific workflow.")

(defun my/wiki-ensure-tree ()
  "Create the wiki directory tree if any subdirs are missing.
Doesn't touch files. Safe to call interactively."
  (interactive)
  (dolist (sub '("" "raw" "entities" "concepts" "sources"
                 "comparisons" "overviews"))
    (let ((d (expand-file-name sub my/wiki-base-dir)))
      (unless (file-directory-p d)
        (make-directory d t)
        (message "wiki: created %s" d)))))

;; Data-dir.el gate (RESTORED): on first-launch the form (which runs
;; from `my/bootstrap' on `emacs-startup-hook') hasn't been submitted
;; yet, so `my/wiki-base-dir' is built against the init.el `~/emacs/'
;; default. Skip ensure-tree until data-dir.el exists — otherwise we'd
;; mkdir `~/emacs/wiki/emacs/' before the user has chosen a data root.
;; After form Save + restart, the gate passes and the tree lands under
;; the chosen data folder.
(when (file-exists-p (expand-file-name "data-dir.el" user-emacs-directory))
  (my/wiki-ensure-tree))

(defun my/wiki-maintainer-build-prompt ()
  "Build the Wiki Maintainer system prompt from WIKI.org and index.org."
  (let* ((schema-path (expand-file-name "WIKI.org" my/wiki-base-dir))
         (index-path  (expand-file-name "index.org" my/wiki-base-dir))
         (file->str (lambda (p) (when (file-readable-p p)
                                  (with-temp-buffer
                                    (insert-file-contents p)
                                    (buffer-string)))))
         (schema (funcall file->str schema-path))
         (index  (funcall file->str index-path)))
    (concat
     "You are the Wiki Maintainer for the user's Emacs-knowledge LLM Wiki at "
     my/wiki-base-dir ".\n"
     "Pattern: Karpathy LLM-Wiki — a persistent, incrementally built knowledge\n"
     "base of interlinked org-roam pages. You own wiki/; the user curates raw/\n"
     "and asks questions.\n\n"
     "## Operating rules (load-bearing)\n"
     "- Read index.org first when answering a query; drill into linked pages as needed.\n"
     "- NEVER commit — the repo auto-pushes on commit. Surface diffs; let the user commit.\n"
     "- One source at a time, with 2–4 bullets of discussion before writing wiki pages.\n"
     "- Use [[id:UUID]] org-roam links for wiki-internal references; never [[file:...]].\n"
     "- For source-page ROAM_REFS pointing to raw files, use file:/absolute/path, never a bare absolute path.\n"
     "- Append every operation to log.org: ** [YYYY-MM-DD] <op> | <subject>.\n"
     "- Lint reports findings only; never auto-fix.\n\n"
     "## Full schema (WIKI.org)\n\n"
     (or schema "[WIKI.org not readable — abort and ask the user]")
     "\n\n## Current index (index.org)\n\n"
     (or index "[index.org not readable]"))))

(defun my/wiki-maintainer-refresh ()
  "Rebuild the wiki-maintainer gptel directive from disk.
Call after editing WIKI.org or significant index changes."
  (interactive)
  (with-eval-after-load 'gptel
    (setq gptel-directives
          (cons (cons 'wiki-maintainer (my/wiki-maintainer-build-prompt))
                (assq-delete-all 'wiki-maintainer gptel-directives)))
    (message "wiki-maintainer directive refreshed")))

(with-eval-after-load 'gptel
  (my/wiki-maintainer-refresh))

(defun my/wiki--slugify (s)
  "Convert string S to lowercase-kebab-case.
Lowercases, replaces runs of non-alphanumeric chars with single dashes,
trims leading/trailing dashes. Empty or nil input returns \"untitled\"."
  (let* ((s (downcase (or s "")))
         (s (replace-regexp-in-string "[^a-z0-9]+" "-" s))
         (s (replace-regexp-in-string "\\`-+\\|-+\\'" "" s)))
    (if (string-empty-p s) "untitled" s)))

(defun my/wiki--open-buffer (name &optional initial-prompt)
  "Open a fresh gptel buffer named *NAME* with wiki-maintainer + preferred
backend preloaded. If INITIAL-PROMPT is non-nil, insert it at point and
call `gptel-send' automatically. Returns the buffer."
  (require 'gptel)
  (my/wiki-maintainer-refresh)
  (let ((buf-name (format "*%s*" name)))
    (with-current-buffer (get-buffer-create buf-name)
      (unless (derived-mode-p 'org-mode)
        (org-mode))
      (gptel-mode 1)
      (setq-local gptel--system-message
                  (alist-get 'wiki-maintainer gptel-directives))
      (when-let* ((label my/wiki-preferred-model)
                  (entry (assoc label my/gptel-backends))
                  (backend (cadr entry))
                  (model (cddr entry)))
        (setq-local gptel-backend backend
                    gptel-model model))
      (goto-char (point-max))
      (when initial-prompt
        (insert initial-prompt)
        (insert "\n")
        (gptel-send)))
    (pop-to-buffer buf-name)
    (get-buffer buf-name)))

(defun my/wiki-ingest (file)
  "Ingest FILE into the wiki via gptel. FILE should already live in raw/."
  (interactive
   (list (read-file-name "Ingest source file: "
                         (expand-file-name "raw/" my/wiki-base-dir)
                         nil t)))
  (let* ((abs (expand-file-name file))
         (slug (file-name-base abs)))
    (my/wiki--open-buffer
     (format "wiki-ingest: %s" slug)
     (format "Ingest %s.\nUpdate index.org and log.org when done." abs))))

(defun my/wiki-import (file)
  "Copy FILE into the wiki's raw/ directory and immediately ingest it.
The destination filename is slugified to lowercase-kebab-case."
  (interactive (list (read-file-name "Import + ingest: " nil nil t)))
  (let* ((raw-dir (expand-file-name "raw/" my/wiki-base-dir))
         (slug (my/wiki--slugify (file-name-base file)))
         (ext (or (file-name-extension file t) ""))
         (dest (expand-file-name (concat slug ext) raw-dir)))
    (unless (file-directory-p raw-dir)
      (make-directory raw-dir t))
    (copy-file file dest t)
    (message "Copied to %s" dest)
    (my/wiki-ingest dest)))

(defun my/wiki-ingest-url (url &optional slug)
  "Download URL to raw/<SLUG>.md and ingest it.
If SLUG is omitted, derived from the URL's last path component.
Final slug is slugified to lowercase-kebab-case."
  (interactive "sURL to ingest: \nsSlug (blank to derive from URL): ")
  (let* ((raw-slug (if (and slug (not (string-empty-p slug)))
                       slug
                     (file-name-base (url-unhex-string url))))
         (slug (my/wiki--slugify raw-slug))
         (raw-dir (expand-file-name "raw/" my/wiki-base-dir))
         (dest (expand-file-name (format "%s.md" slug) raw-dir)))
    (unless (file-directory-p raw-dir)
      (make-directory raw-dir t))
    (require 'url)
    (url-copy-file url dest t)
    (message "Downloaded to %s, starting ingest..." dest)
    (my/wiki-ingest dest)))

(defun my/wiki-ingest-buffer (slug)
  "Save the current buffer (or active region) into raw/<SLUG>.<ext> and ingest.
Extension is .org if the buffer is in org-mode, otherwise .md. If a
region is active, only the region is saved; otherwise the whole buffer."
  (interactive
   (list (let ((default (when (buffer-file-name)
                          (file-name-base (buffer-file-name)))))
           (read-string
            (format "Slug%s: "
                    (if default (format " (default %s)" default) ""))
            nil nil default))))
  (when (or (null slug) (string-empty-p slug))
    (user-error "Slug required"))
  (let* ((slug (my/wiki--slugify slug))
         (raw-dir (expand-file-name "raw/" my/wiki-base-dir))
         (ext (if (derived-mode-p 'org-mode) ".org" ".md"))
         (dest (expand-file-name (concat slug ext) raw-dir))
         (start (if (use-region-p) (region-beginning) (point-min)))
         (end   (if (use-region-p) (region-end)       (point-max))))
    (unless (file-directory-p raw-dir)
      (make-directory raw-dir t))
    (write-region start end dest)
    (message "Saved %s to %s"
             (if (use-region-p) "region" "buffer") dest)
    (my/wiki-ingest dest)))

(defun my/wiki-open ()
  "Open a fresh gptel buffer with wiki-maintainer preloaded for
ad-hoc queries against the existing wiki."
  (interactive)
  (my/wiki--open-buffer "wiki-query"))

(defun my/wiki-lint ()
  "Open a wiki-maintainer buffer with the lint prompt preloaded.
The agent reports findings only — never auto-fixes."
  (interactive)
  (my/wiki--open-buffer
   "wiki-lint"
   (concat
    "Lint the wiki. Find:\n"
    "1. Orphan pages (no inbound id-links).\n"
    "2. Concepts mentioned in 2+ pages without their own page.\n"
    "3. Contradictions between pages.\n"
    "4. Stale claims superseded by newer sources.\n"
    "5. Missing cross-references between obviously related pages.\n"
    "Report findings only — do NOT modify any files. Append a log.org"
    " summary entry at the end and stop.")))

(global-set-key (kbd "C-c n I") #'my/wiki-ingest)
(global-set-key (kbd "C-c n M") #'my/wiki-import)
(global-set-key (kbd "C-c n U") #'my/wiki-ingest-url)
(global-set-key (kbd "C-c n B") #'my/wiki-ingest-buffer)
(global-set-key (kbd "C-c n Q") #'my/wiki-open)
(global-set-key (kbd "C-c n L") #'my/wiki-lint)

(with-eval-after-load 'org-capture
  (add-to-list
   'org-capture-templates
   '("w" "Wiki ingest (URL or local file)"
     plain (function my/wiki--capture-target)
     "" :immediate-finish t :no-save t)))

(defun my/wiki--capture-target ()
  "Capture handler: prompt for a URL or file path, ingest accordingly."
  (let ((input (read-string "URL or file path: ")))
    (cond
     ((string-match-p "\\`https?://" input) (my/wiki-ingest-url input))
     ((file-exists-p (expand-file-name input)) (my/wiki-import input))
     (t (user-error "Not a URL and not an existing file: %s" input))))
  ;; tell org-capture nothing to insert
  (org-capture-kill))

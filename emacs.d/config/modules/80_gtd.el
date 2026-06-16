;;; 80_gtd.el --- GTD defaults and personal overlay -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'org)
(require 'org-agenda)
(require 'org-capture)
(require 'org-id)

(defvar org-agenda-custom-commands)
(defvar org-agenda-files)
(defvar org-archive-location)
(defvar org-capture-templates)
(defvar org-default-notes-file)
(defvar org-enforce-todo-dependencies)
(defvar org-heading-regexp)
(defvar org-refile-targets)
(defvar org-tags-exclude-from-inheritance)
(defvar org-todo-keyword-faces)
(defvar org-todo-keywords)
(defvar org-todo-keywords-1)
(defvar org-todo-state-tags-triggers)
(defvar my/org-project-structural-fallback)
(defvar my/data-dir)
(defvar org-super-links-backlink-into-drawer)
(defvar org-super-links-related-into-drawer)
(defvar org-super-links-related-drawer-default-name)
(defvar org-super-links-search-function)
(declare-function my/bootstrap-ready-p "20.03.01_bootstrap")
(declare-function org-edna-edit "org-edna")
(declare-function org-edna-mode "org-edna")
(declare-function org-super-links-delete-link "org-super-links")
(declare-function org-super-links-insert-link "org-super-links")
(declare-function org-super-links-link "org-super-links")
(declare-function org-super-links-store-link "org-super-links")

(when (fboundp 'elpaca)
  (eval
   '(progn
      (elpaca
        (org-edna
         :inherit nil
         :type git
         :protocol https
         :host github
         :repo "emacsmirror/gnu_elpa"
         :branch "externals/org-edna"
         :ref "8258a4dfa00aa522249cdf9aeea5be4de97bd7c1"
         :pin t
         :files ("*" (:exclude ".git"))))
      (elpaca
        (org-super-links
         :inherit nil
         :type git
         :protocol https
         :host github
         :repo "toshism/org-super-links"
         :branch "develop"
         :ref "ce53993edc0fcfb85289f3eea74d1caa4dce8b60"
         :pin t
         :files ("*.el"))))))

(use-package org-edna
  :ensure nil
  :defer t
  :no-require t)

(use-package org-super-links
  :ensure nil
  :defer t
  :no-require t
  :init
  (setq org-super-links-backlink-into-drawer t
        org-super-links-related-into-drawer t
        org-super-links-related-drawer-default-name "RELATED"
        org-super-links-search-function 'org-super-links-get-location))

(defun my/gtd--maybe-enable-org-edna ()
  "Enable `org-edna-mode' when the package is available."
  (when (require 'org-edna nil t)
    (org-edna-mode 1)))

(add-hook 'org-mode-hook #'my/gtd--maybe-enable-org-edna)

(defun my/org-super-links--require ()
  "Load org-super-links or signal a helpful error."
  (unless (require 'org-super-links nil t)
    (user-error "org-super-links is not installed yet")))

(defun my/org-super-links-link ()
  "Create a bidirectional org-super-links link."
  (interactive)
  (my/org-super-links--require)
  (org-super-links-link))

(defun my/org-super-links-store-link ()
  "Store the current Org heading for later super-link insertion."
  (interactive)
  (my/org-super-links--require)
  (org-super-links-store-link))

(defun my/org-super-links-insert-link ()
  "Insert the stored super link and create the backlink."
  (interactive)
  (my/org-super-links--require)
  (org-super-links-insert-link))

(defun my/org-super-links-delete-link ()
  "Delete the super link at point and its backlink when present."
  (interactive)
  (my/org-super-links--require)
  (org-super-links-delete-link))

(defun my/org-edna-edit ()
  "Edit org-edna BLOCKER and TRIGGER properties for the current heading."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "This command works in Org buffers"))
  (unless (require 'org-edna nil t)
    (user-error "org-edna is not installed yet"))
  (org-edna-edit))

(global-set-key (kbd "C-c g e") #'my/org-edna-edit)
(global-set-key (kbd "C-c g s") #'my/org-super-links-link)
(global-set-key (kbd "C-c g l") #'my/org-super-links-store-link)
(global-set-key (kbd "C-c g i") #'my/org-super-links-insert-link)
(global-set-key (kbd "C-c g d") #'my/org-super-links-delete-link)

(defun my/gtd--org-root ()
  "Return the compact Org root for GTD files."
  (unless (and (boundp 'my/data-dir) (stringp my/data-dir))
    (user-error "Bootstrap is not ready; my/data-dir is unavailable"))
  (expand-file-name "data/org/" my/data-dir))

(defun my/gtd--file (name)
  "Return compact GTD file NAME under `my/gtd--org-root'."
  (expand-file-name name (my/gtd--org-root)))

(defun my/gtd--agenda-files ()
  "Return existing compact GTD files."
  (cl-remove-if-not
   #'file-exists-p
   (mapcar #'my/gtd--file '("inbox.org" "gtd.org" "calendar.org"))))

(setq org-todo-keywords
      '((sequence "TODO(t)" "NEXT(n)" "WAITING(w@/!)" "|"
                  "DONE(d@/!)" "CANCELLED(c@/!)")))

(setq org-todo-keyword-faces
      '(("TODO"      :foreground "red"          :weight bold)
        ("NEXT"      :foreground "blue"         :weight bold)
        ("WAITING"   :foreground "orange"       :weight bold)
        ("DONE"      :foreground "forest green" :weight bold)
        ("CANCELLED" :foreground "forest green" :weight bold)))

(setq org-todo-state-tags-triggers
      '(("CANCELLED" ("CANCELLED" . t))
        ("WAITING"   ("WAITING" . t))
        (done        ("WAITING") ("CANCELLED"))
        ("TODO"      ("WAITING") ("CANCELLED"))
        ("NEXT"      ("WAITING") ("CANCELLED"))))

(dolist (tag '("crypt" "project"))
  (cl-pushnew tag org-tags-exclude-from-inheritance :test #'string=))

(setq org-enforce-todo-dependencies t)

(defvar my/org-project-structural-fallback t
  "When non-nil, treat old TODO headings with TODO children as projects.
Explicit local :project: tags remain authoritative.  The structural
fallback keeps older Org data visible during migration.")

(defun my/org-local-tags ()
  "Return local tags on the current Org heading."
  (org-get-tags nil t))

(defun my/org-heading-has-todo-child-p ()
  "Return non-nil when the current heading has a TODO-keyword child."
  (let ((end (save-excursion (org-end-of-subtree t t)))
        (found nil))
    (save-excursion
      (forward-line 1)
      (while (and (not found)
                  (re-search-forward org-heading-regexp end t))
        (when (member (org-get-todo-state) org-todo-keywords-1)
          (setq found t))))
    found))

(defun my/org-project-p ()
  "Return non-nil when the current heading is a GTD project.
Prefer an explicit local :project: tag.  Fall back to the older
structural project shape while user data is being migrated."
  (or (member "project" (my/org-local-tags))
      (and my/org-project-structural-fallback
           (member (org-get-todo-state) org-todo-keywords-1)
           (my/org-heading-has-todo-child-p))))

(defun my/org-heading-has-progress-cookie-p (title)
  "Return non-nil when TITLE already contains a progress cookie."
  (string-match-p "\\[[0-9]*/[0-9]*\\]\\|\\[[0-9]+%\\]" title))

(defun my/org-ensure-progress-cookie ()
  "Add a TODO progress cookie to the current heading when missing."
  (let ((title (nth 4 (org-heading-components))))
    (when (and title (not (my/org-heading-has-progress-cookie-p title)))
      (org-edit-headline (concat "[/] " title)))))

(defun my/org-project-has-next-p ()
  "Return non-nil when the current project has a NEXT child action."
  (let ((end (save-excursion (org-end-of-subtree t t)))
        (found nil))
    (save-excursion
      (forward-line 1)
      (while (and (not found)
                  (re-search-forward org-heading-regexp end t))
        (when (equal (org-get-todo-state) "NEXT")
          (setq found t))))
    found))

(defun my/org-skip-non-stuck-projects ()
  "Skip headings that are not stuck local GTD projects."
  (if (and (my/org-project-p) (not (my/org-project-has-next-p)))
      nil
    (save-excursion (org-end-of-subtree t t))))

(defun my/org-skip-non-projects ()
  "Skip headings that are not explicit or migration-fallback projects."
  (if (my/org-project-p)
      nil
    (save-excursion (org-end-of-subtree t t))))

(defun my/org-mark-as-project (&optional category)
  "Mark the current heading as a compact GTD project."
  (interactive
   (list (when current-prefix-arg
           (read-string "CATEGORY: " (or (org-entry-get (point) "CATEGORY") "")))))
  (unless (derived-mode-p 'org-mode)
    (user-error "This command works in Org buffers"))
  (unless buffer-file-name
    (user-error "Save this Org buffer before marking projects; IDs need a file"))
  (org-back-to-heading t)
  (unless (org-get-todo-state)
    (org-todo "TODO"))
  (org-toggle-tag "project" 'on)
  (org-entry-put (point) "COOKIE_DATA" "todo recursive")
  (when (and category (not (string= category "")))
    (org-entry-put (point) "CATEGORY" category))
  (org-id-get-create)
  (my/org-ensure-progress-cookie)
  (org-update-parent-todo-statistics)
  (message "Marked heading as GTD project"))

(global-set-key (kbd "C-c g p") #'my/org-mark-as-project)

(when (my/bootstrap-ready-p)
  (setq org-default-notes-file (my/gtd--file "inbox.org"))

  (setq org-capture-templates
        `(("i" "Inbox" entry
           (file+headline ,(my/gtd--file "inbox.org") "Inbox")
           "* %?\n%U\n")
          ("n" "Next action" entry
           (file+headline ,(my/gtd--file "gtd.org") "Next Actions")
           "** NEXT %? %^G\n%U\n")
          ("p" "Project" entry
           (file+headline ,(my/gtd--file "gtd.org") "Projects")
           "** TODO [/] %^{Project outcome} :project:\n:PROPERTIES:\n:CATEGORY: %^{Category|project}\n:COOKIE_DATA: todo recursive\n:END:\n*** NEXT %?"
           :empty-lines 1)
          ("w" "Waiting" entry
           (file+headline ,(my/gtd--file "gtd.org") "Waiting")
           "** WAITING %? %^G\n%U\n")
          ("s" "Someday / Maybe" entry
           (file+headline ,(my/gtd--file "gtd.org") "Someday / Maybe")
           "** TODO %? :someday:\n%U\n")
          ("c" "Calendar" entry
           (file+headline ,(my/gtd--file "calendar.org") "Calendar")
           "** TODO %?\nSCHEDULED: %^t\n%U\n")
          ("f" "Flight / travel" entry
           (file+headline ,(my/gtd--file "gtd.org") "Tickler")
           "** TODO %? :travel:flight:\n%U\n")))

  (setq org-refile-targets
        `((,(my/gtd--file "inbox.org") :maxlevel . 2)
          (,(my/gtd--file "gtd.org") :maxlevel . 4)
          (,(my/gtd--file "calendar.org") :maxlevel . 2)
          (org-agenda-files :maxlevel . 4)))

  (setq org-archive-location
        (concat (my/gtd--file "archive.org") "::datetree/"))

  (setq org-agenda-files
        (cl-remove-duplicates
         (append (my/gtd--agenda-files) org-agenda-files)
         :test #'string=)))

(defun my/gtd--without-commands (keys commands)
  "Return COMMANDS without entries whose key is in KEYS."
  (cl-remove-if (lambda (command)
                  (member (car-safe command) keys))
                commands))

(setq org-agenda-custom-commands
      (append
       (my/gtd--without-commands
        '("g" "r" "J" "X" "B" "H" "C" "E" "K" "A" "G" "L" "R" "f")
        org-agenda-custom-commands)
       '(("g" "GTD dashboard"
          ((agenda "" ((org-agenda-span 1)
                       (org-deadline-warning-days 7)))
           (todo "NEXT"
                 ((org-agenda-overriding-header "Next actions")))
           (todo "WAITING"
                 ((org-agenda-overriding-header "Waiting")))
           (alltodo ""
                      ((org-agenda-overriding-header "Projects")
                       (org-agenda-skip-function 'my/org-skip-non-projects)))
           (alltodo ""
                      ((org-agenda-overriding-header "Stuck projects")
                       (org-agenda-skip-function 'my/org-skip-non-stuck-projects)))
           (tags "+inbox"
                 ((org-agenda-overriding-header "Inbox")))))
         ("r" "Weekly review"
          ((agenda "" ((org-agenda-span 7)
                       (org-agenda-start-on-weekday nil)))
           (alltodo ""
                      ((org-agenda-overriding-header "Projects")
                       (org-agenda-skip-function 'my/org-skip-non-projects)))
           (alltodo ""
                      ((org-agenda-overriding-header "Stuck projects")
                       (org-agenda-skip-function 'my/org-skip-non-stuck-projects)))
           (todo "WAITING"
                 ((org-agenda-overriding-header "Waiting")))
           (tags-todo "+someday"
                      ((org-agenda-overriding-header "Someday / Maybe")))
           (tags-todo "+area"
                      ((org-agenda-overriding-header "Areas")))
           (tags-todo "+goal"
                      ((org-agenda-overriding-header "Goals")))
           (tags-todo "+life"
                      ((org-agenda-overriding-header "Life / Values")))))
         ("J" "Projects" alltodo ""
          ((org-agenda-skip-function 'my/org-skip-non-projects)))
         ("X" "Stuck projects" alltodo ""
          ((org-agenda-skip-function 'my/org-skip-non-stuck-projects)))
         ("B" "Blocked / waiting"
          ((todo "WAITING"
                 ((org-agenda-overriding-header "Waiting")))
           (tags-todo "+blocked"
                      ((org-agenda-overriding-header "Blocked")))))
         ("H" "@home next actions" tags-todo "+@home/NEXT")
         ("C" "@computer next actions" tags-todo "+@computer/NEXT")
         ("E" "@errand next actions" tags-todo "+@errand/NEXT")
         ("K" "@calls next actions" tags-todo "+@calls/NEXT")
         ("A" "Areas" tags-todo "+area")
         ("G" "Goals" tags-todo "+goal")
         ("L" "Life / values" tags-todo "+life")
         ("R" "Higher-horizon review"
          ((tags-todo "+life"
                      ((org-agenda-overriding-header "Life / Values")))
           (tags-todo "+goal"
                      ((org-agenda-overriding-header "Goals")))
           (tags-todo "+area"
                      ((org-agenda-overriding-header "Areas")))))
         ("f" "Flights / travel"
          ((tags "+flight"
                 ((org-agenda-overriding-header "Flights")))
           (tags "+travel"
                 ((org-agenda-overriding-header "Travel"))))))))

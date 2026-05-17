;;; -*- lexical-binding: t -*-

(defun my/apple-reminders--ensure-cli ()
  "Ensure the reminders-cli tool is installed via Homebrew."
  (unless (executable-find "reminders")
    (when (executable-find "brew")
      ;; Tap first (idempotent), then install.
      (my/brew-install-and-log "tap" "keith/formulae" "tap" "keith/formulae")
      (my/brew-install-and-log "formula" "reminders-cli" "install" "reminders-cli")
      (message "reminders-cli not found — installing in background. Restart Emacs when done."))))

(my/apple-reminders--ensure-cli)

(defgroup my/apple-reminders nil
  "Integration between Emacs/Org and macOS Apple Reminders."
  :group 'org)

(defcustom my/apple-reminders-default-list nil
  "Name of the Apple Reminders list used for Org-synced items.
nil means use the first list returned by Apple Reminders."
  :type '(choice (const :tag "Auto-detect first list" nil) string)
  :group 'my/apple-reminders)

(defun my/apple-reminders--default-list ()
  "Return `my/apple-reminders-default-list', auto-detecting if nil."
  (or my/apple-reminders-default-list
      (car (ignore-errors (my/apple-reminders-lists)))))

(defcustom my/apple-reminders-cli (or (executable-find "reminders") "reminders")
  "Path to the reminders-cli binary."
  :type 'string
  :group 'my/apple-reminders)

(defun my/apple-reminders--run (&rest args)
  "Run reminders-cli with ARGS, return stdout. Signal error on failure."
  (unless (executable-find my/apple-reminders-cli)
    (user-error "reminders-cli not installed. Run: brew install keith/formulae/reminders-cli"))
  (with-temp-buffer
    (let ((exit (apply #'call-process my/apple-reminders-cli nil t nil args)))
      (unless (zerop exit)
        (error "reminders-cli failed (%d): %s" exit (buffer-string)))
      (string-trim (buffer-string)))))

(defun my/apple-reminders-lists ()
  "Return a list of Apple Reminders list names."
  (split-string (my/apple-reminders--run "show-lists") "\n" t))

(defun my/apple-reminders-show-lists ()
  "Display all Apple Reminders lists in the echo area."
  (interactive)
  (message "Reminders lists:\n%s"
           (mapconcat (lambda (l) (concat "  • " l))
                      (my/apple-reminders-lists) "\n")))

(defun my/apple-reminders-create-list (name)
  "Create a new Apple Reminders list called NAME."
  (interactive "sNew list name: ")
  (when (string-empty-p (string-trim name))
    (user-error "List name cannot be empty"))
  (my/apple-reminders--jxa-async
   (format "Application('Reminders').lists.push(Application('Reminders').List({name:%s}));"
           (json-encode name))
   (lambda (_)
     (message "Apple Reminders: created list \"%s\"." name))))

(defun my/apple-reminders-add (title &optional list-name due-date notes)
  "Add a reminder TITLE to LIST-NAME with optional DUE-DATE and NOTES.
DUE-DATE is an ISO date string like \"2025-12-31\" or natural language
like \"tomorrow 9am\" — reminders-cli parses both."
  (interactive
   (list (read-string "Reminder: ")
         (completing-read "List: " (my/apple-reminders-lists) nil nil
                          (my/apple-reminders--default-list))
         (read-string "Due (optional, e.g. 2025-12-31 or 'tomorrow 9am'): ")
         nil))
  (let* ((list (or list-name (my/apple-reminders--default-list)))
         (args (append (list "add" list title)
                       (when (and due-date (not (string-empty-p due-date)))
                         (list "--due-date" due-date))
                       (when (and notes (not (string-empty-p notes)))
                         (list "--notes" notes)))))
    (apply #'my/apple-reminders--run args)
    (message "Added to Apple Reminders [%s]: %s%s" list title
             (if (and due-date (not (string-empty-p due-date)))
                 (format " (due %s)" due-date) ""))))

(defun my/apple-reminders--extract-notes ()
  "Extract body text from org heading, stripping LOGBOOK and org metadata."
  (save-excursion
    (org-back-to-heading t)
    (let* ((start (save-excursion (org-end-of-meta-data t) (point)))
           (end   (save-excursion (org-end-of-subtree t) (point)))
           (raw   (buffer-substring-no-properties start end)))
      (string-trim
       (replace-regexp-in-string ":LOGBOOK:\\(?:.\\|\n\\)*?:END:\n?" "" raw)))))

(defun my/apple-reminders--org-item-values ()
  "Return alist of org heading values that map to Apple Reminders fields."
  (save-excursion
    (org-back-to-heading t)
    (let* ((raw   (org-get-heading t t t t))
           (title (replace-regexp-in-string
                   "^\\(?:\\[#[ABC]\\] \\)?\\(?:★ \\)?" "" raw))
           (dl    (org-entry-get nil "DEADLINE"))
           (due   (when (and dl (string-match
                                   "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" dl))
                    (match-string 1 dl)))
           (prio-char (nth 3 (org-heading-components)))
           (prio  (cond ((eql prio-char ?A) 1)
                        ((eql prio-char ?B) 5)
                        ((eql prio-char ?C) 9)
                        (t 0)))
           (flagged (if (member "flagged" (org-get-tags nil t)) t nil))
           (notes   (my/apple-reminders--extract-notes)))
      `((title . ,title) (due . ,due) (priority . ,prio)
        (flagged . ,flagged) (notes . ,notes)))))

(defun my/org-heading-to-reminder (&optional list-name)
  "Push org heading at point to Apple Reminders (all synced fields).
With prefix arg, prompt for list name."
  (interactive
   (when current-prefix-arg
     (list (completing-read "List: " (my/apple-reminders-lists) nil nil
                            (my/apple-reminders--default-list)))))
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  (let* ((list (or list-name (my/apple-reminders--default-list)))
         (vals (my/apple-reminders--org-item-values))
         (new-id (my/apple-reminders--create-in-apple list vals)))
    (when new-id
      (org-set-property "REMINDER_ID"   new-id)
      (org-set-property "REMINDER_LIST" list)
      (message "Pushed to Apple Reminders [%s]: %s" list (alist-get 'title vals)))))

(defun my/apple-reminders--on-todo-state-change ()
  "Instantly sync org TODO state change to Apple Reminders via REMINDER_ID.
DONE/CANCELLED → completed=true. TODO/NEXT/WAITING → completed=false (reopen)."
  (unless my/apple-reminders--syncing
    (let ((id   (org-entry-get nil "REMINDER_ID"))
          (list (org-entry-get nil "REMINDER_LIST")))
      (when (and id list)
        (cond
         ((member org-state '("DONE" "CANCELLED"))
          (my/apple-reminders--jxa-async
           (format "Application('Reminders').lists.byName(%s).reminders.byId(%s).completed=true;"
                   (json-encode list) (json-encode id))))
         ((member org-state '("TODO" "NEXT" "WAITING"))
          (my/apple-reminders--jxa-async
           (format "Application('Reminders').lists.byName(%s).reminders.byId(%s).completed=false;"
                   (json-encode list) (json-encode id)))))))))

(add-hook 'org-after-todo-state-change-hook #'my/apple-reminders--on-todo-state-change)

(defun my/apple-reminders--maybe-push-heading (&rest _)
  "Push heading at point to Apple if it has a REMINDER_ID. Triggered by org advice."
  (when (and (derived-mode-p 'org-mode)
             (not my/apple-reminders--syncing))
    (condition-case err
        (let* ((id   (org-entry-get nil "REMINDER_ID"))
               (list (org-entry-get nil "REMINDER_LIST"))
               (m    (when (and id list)
                       (save-excursion (org-back-to-heading t) (point-marker)))))
          (when m
            (my/apple-reminders--update-in-apple
             list id (my/apple-reminders--org-item-values)
             (lambda (new-mod)
               (when (marker-buffer m)
                 (with-current-buffer (marker-buffer m)
                   (save-excursion
                     (goto-char m)
                     (when (stringp new-mod)
                       (org-set-property "REMINDER_ORG_MOD" new-mod)))))
               (set-marker m nil)))))
      (error (message "Reminders push: %s" (error-message-string err))))))

(advice-add 'org-priority         :after #'my/apple-reminders--maybe-push-heading)
(advice-add 'org-deadline         :after #'my/apple-reminders--maybe-push-heading)
(advice-add 'org-set-tags-command :after #'my/apple-reminders--maybe-push-heading)

(defcustom my/apple-reminders-sync-list nil
  "Apple Reminders list used for bidirectional sync with `my/apple-reminders-sync-file'.
nil means use the first list returned by Apple Reminders."
  :type '(choice (const :tag "Auto-detect first list" nil) string)
  :group 'my/apple-reminders)

(defcustom my/apple-reminders-sync-file "~/org/reminders.org"
  "Org file mirrored bidirectionally with `my/apple-reminders-sync-list'."
  :type 'string :group 'my/apple-reminders)

(defvar my/apple-reminders--syncing nil
  "Non-nil while a sync is in progress; prevents recursive save-hook calls.")

;;; JXA helpers

(defun my/apple-reminders--jxa-run (script)
  "Run JXA SCRIPT synchronously via osascript. Returns stdout string."
  (string-trim (shell-command-to-string
                (concat "osascript -l JavaScript -e "
                        (shell-quote-argument script)))))

(defun my/apple-reminders--jxa-async (script &optional callback)
  "Run JXA SCRIPT via osascript asynchronously.
CALLBACK receives the stdout string when the process exits."
  (let ((buf (generate-new-buffer " *ar-jxa*")))
    (make-process
     :name "ar-jxa"
     :buffer buf
     :command (list "osascript" "-l" "JavaScript" "-e" script)
     :sentinel (lambda (proc _event)
                 (unless (process-live-p proc)
                   (let ((out (with-current-buffer buf
                                (string-trim (buffer-string)))))
                     (kill-buffer buf)
                     (when callback (funcall callback out))))))))

(defun my/apple-reminders--complete-in-apple (list-name id)
  "Mark Apple reminder ID in LIST-NAME as completed (async)."
  (my/apple-reminders--jxa-async
   (format "Application('Reminders').lists.byName(%s).reminders.byId(%s).completed=true;"
           (json-encode list-name) (json-encode id))))

(defun my/apple-reminders--create-in-apple (list-name vals)
  "Create Apple reminder in LIST-NAME from VALS alist. Returns new ID string or nil.
Captures all IDs before and after push to find the new one without relying on
whose(), which can fail due to timing and cause duplicate entries."
  (let* ((title   (alist-get 'title    vals ""))
         (notes   (alist-get 'notes    vals ""))
         (prio    (alist-get 'priority vals 0))
         (due     (alist-get 'due      vals))
         (flagged (alist-get 'flagged  vals))
         (script
          (format
           "var app=Application('Reminders'),list=app.lists.byName(%s);
var prev=list.reminders.id();
list.reminders.push(app.Reminder({name:%s,body:%s,priority:%d,flagged:%s%s}));
var next=list.reminders.id(),newId=null;
for(var i=0;i<next.length;i++){if(prev.indexOf(next[i])<0){newId=next[i];break;}}
JSON.stringify(newId);"
           (json-encode list-name)
           (json-encode title) (json-encode notes) prio
           (if flagged "true" "false")
           (if due (format ",dueDate:new Date(%s)" (json-encode (concat due "T00:00:00"))) ""))))
    (condition-case nil
        (json-parse-string (my/apple-reminders--jxa-run script))
      (error nil))))

(defun my/apple-reminders--update-in-apple (list-name id vals &optional callback)
  "Push VALS alist to Apple reminder ID in LIST-NAME.
Without CALLBACK: synchronous; returns Apple's post-push modificationDate string or nil.
With CALLBACK: async; CALLBACK receives the modificationDate string."
  (let* ((title   (alist-get 'title    vals ""))
         (notes   (alist-get 'notes    vals ""))
         (prio    (alist-get 'priority vals 0))
         (due     (alist-get 'due      vals))
         (flagged (alist-get 'flagged  vals))
         (script
          (format
           "var r=Application('Reminders').lists.byName(%s).reminders.byId(%s);
r.name=%s;r.body=%s;r.priority=%d;r.flagged=%s;%s
var md=r.modificationDate();JSON.stringify((md&&md instanceof Date)?md.toISOString():null);"
           (json-encode list-name) (json-encode id)
           (json-encode title) (json-encode notes) prio
           (if flagged "true" "false")
           (if due
               (format "r.dueDate=new Date(%s);" (json-encode (concat due "T00:00:00")))
             "r.dueDate=null;"))))
    (if callback
        (my/apple-reminders--jxa-async script callback)
      (condition-case nil
          (json-parse-string (my/apple-reminders--jxa-run script))
        (error nil)))))

(defun my/apple-reminders-migrate-flat-headings ()
  "One-time migration: move flat * TODO reminder entries under * ListName headings.
Run once after upgrading from v1.4.x. Operates on `my/apple-reminders-sync-file'."
  (interactive)
  (let* ((file (expand-file-name my/apple-reminders-sync-file))
         (buf  (find-file-noselect file))
         moves)
    (with-current-buffer buf
      (org-map-entries
       (lambda ()
         (when (and (= (org-current-level) 1)
                    (org-entry-get nil "REMINDER_LIST"))
           (let* ((beg   (point))
                  (end   (save-excursion (org-end-of-subtree t t) (point)))
                  (lname (org-entry-get nil "REMINDER_LIST"))
                  (text  (buffer-substring-no-properties beg end)))
             (push (list (copy-marker beg) (copy-marker end) lname text) moves))))
       nil nil)
      (dolist (m (sort (copy-sequence moves)
                       (lambda (a b) (> (marker-position (car a))
                                        (marker-position (car b))))))
        (delete-region (nth 0 m) (nth 1 m))
        (set-marker (nth 0 m) nil)
        (set-marker (nth 1 m) nil))
      (dolist (m (nreverse moves))
        (let* ((lname (nth 2 m))
               (text  (with-temp-buffer
                        (insert (nth 3 m))
                        (goto-char (point-min))
                        (while (re-search-forward "^\\*+" nil t)
                          (replace-match (concat (match-string 0) "*")))
                        (buffer-string))))
          (my/apple-reminders--goto-list-heading lname)
          (unless (bolp) (insert "\n"))
          (insert text)))
      (save-buffer))
    (message "Migrated %d entries under list headings." (length moves))))

(defun my/apple-reminders--goto-list-heading (list-name)
  "Move point to end of LIST-NAME's subtree, creating the * heading if absent."
  (goto-char (point-min))
  (if (re-search-forward (format "^\\* %s\\(?:[[:space:]]\\|$\\)" (regexp-quote list-name)) nil t)
      (org-end-of-subtree t t)
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert (format "* %s [/]\n" list-name)))
  (unless (bolp) (insert "\n")))

(defun my/apple-reminders--insert-org-heading (item list-name)
  "Insert ** TODO org heading for Apple ITEM under LIST-NAME's section."
  (let* ((id      (alist-get 'id       item))
         (title   (alist-get 'title    item))
         (notes   (alist-get 'notes    item))
         (due     (alist-get 'due      item))
         (prio    (alist-get 'priority item))
         (flagged (alist-get 'flagged  item)))
    (unless (bolp) (insert "\n"))
    (insert (format "** TODO %s%s%s\n"
                    (my/apple-reminders--prio-label prio)
                    (if (eq flagged t) "★ " "")
                    title))
    (when (and due (not (eq due :null)))
      (insert (format "   DEADLINE: <%s>\n" due)))
    (insert (format "   :PROPERTIES:\n   :REMINDER_ID:   %s\n   :REMINDER_LIST: %s\n   :END:\n"
                    id list-name))
    (when (and (stringp notes) (not (string-empty-p notes)))
      (dolist (line (split-string notes "\n"))
        (insert (format "   %s\n" line))))))

;;; Push-only (org → Apple): called from save hook

(defun my/apple-reminders--find-in-cache (id)
  "Return Apple cache item with REMINDER_ID = ID, or nil."
  (catch 'found
    (dolist (entry my/apple-reminders--cache)
      (dolist (item (alist-get 'items entry))
        (when (equal (alist-get 'id item) id)
          (throw 'found item))))))

(defun my/apple-reminders--last-known-mod ()
  "Return the most recent Apple modDate we have recorded for the entry at point.
This is max(REMINDER_APPLE_MOD, REMINDER_ORG_MOD), or nil if neither is set."
  (let ((amod (org-entry-get nil "REMINDER_APPLE_MOD"))
        (omod (org-entry-get nil "REMINDER_ORG_MOD")))
    (cond
     ((and amod omod) (if (string> amod omod) amod omod))
     (amod amod)
     (omod omod)
     (t nil))))

(defun my/apple-reminders--push-to-apple ()
  "Push changed org entries → Apple. Changes detected by comparing against in-memory cache.
New items get REMINDER_ID stamped back. REMINDER_ORG_MOD is set to Apple's post-push modDate."
  (let* ((list-name (or my/apple-reminders-sync-list (my/apple-reminders--default-list)))
         (n-new 0) (n-updated 0)
         new-pts)
    (org-map-entries
     (lambda ()
       (let* ((id     (org-entry-get nil "REMINDER_ID"))
              (rlist  (or (org-entry-get nil "REMINDER_LIST") list-name))
              (state  (org-get-todo-state))
              (cached (and id (my/apple-reminders--find-in-cache id))))
         (cond
          ((and (null id) (member state '("TODO" "NEXT" "WAITING")))
           (push (point-marker) new-pts))
          ((and id (member state '("DONE" "CANCELLED")))
           (when (and cached (not (eq (alist-get 'completed cached) t)))
             (my/apple-reminders--complete-in-apple rlist id)))
          ((and id (member state '("TODO" "NEXT" "WAITING")))
           (let* ((vals (my/apple-reminders--org-item-values))
                  (needs-push
                   (or (null cached)
                       (not (equal (or (alist-get 'title   vals) "")
                                   (or (alist-get 'title   cached) "")))
                       (not (equal (or (alist-get 'notes   vals) "")
                                   (or (alist-get 'notes   cached) "")))
                       (not (= (or (alist-get 'priority vals) 0)
                               (or (alist-get 'priority cached) 0)))
                       (not (equal (alist-get 'due vals)
                                   (let ((d (alist-get 'due cached)))
                                     (and (stringp d) (not (string-empty-p d)) d))))
                       (not (eq (alist-get 'flagged vals)
                                (eq (alist-get 'flagged cached) t))))))
             (when needs-push
               (let ((new-mod (my/apple-reminders--update-in-apple rlist id vals)))
                 (when (stringp new-mod)
                   (org-set-property "REMINDER_ORG_MOD" new-mod)))
               (setq n-updated (1+ n-updated))))))))
     nil nil)
    (dolist (m (nreverse new-pts))
      (goto-char m)
      (when-let (new-id (my/apple-reminders--create-in-apple
                         list-name (my/apple-reminders--org-item-values)))
        (org-set-property "REMINDER_ID"   new-id)
        (org-set-property "REMINDER_LIST" list-name)
        (setq n-new (1+ n-new))))
    (when (or (> n-new 0) (> n-updated 0))
      (message "Reminders push: %d new, %d updated." n-new n-updated))))

;;; Full bidirectional sync (C-c r R)

(defun my/apple-reminders-sync ()
  "Full bidirectional sync: `my/apple-reminders-sync-file' ↔ all Apple Reminders lists.

- New org item (no REMINDER_ID) → created in Apple, ID stamped back.
- Apple not changed (modDate unchanged) → org wins: push org fields to Apple if different.
- Apple changed (modDate newer than last sync) → Apple wins: priority/due/flagged pulled.
- DONE/CANCELLED in org, open in Apple → Apple completed.
- Open in org, completed/gone in Apple → org marked DONE.
- Open in Apple, missing from org → pulled under its * ListName heading."
  (interactive)
  (message "Reminders: syncing…")
  (let* ((default-list (my/apple-reminders--default-list))
         (file (expand-file-name my/apple-reminders-sync-file))
         (raw  (my/apple-reminders--jxa-run my/apple-reminders--fetch-script))
         (data (condition-case nil
                   (json-parse-string raw :object-type 'alist :array-type 'list)
                 (error (user-error "Reminders sync: fetch failed — %s" raw))))
         (apple-by-id (let ((ht (make-hash-table :test #'equal)))
                        (dolist (entry data)
                          (dolist (item (alist-get 'items entry))
                            (puthash (alist-get 'id item) item ht)))
                        ht))
         (n-done 0) (n-pushed 0) (n-pulled 0) (n-updated 0) (n-reopened 0))
    (unless (file-exists-p file)
      (with-temp-file file
        (insert "#+TITLE: Reminders\n#+STARTUP: overview\n#+TODO: TODO NEXT WAITING | DONE CANCELLED\n\n")))
    (let ((my/apple-reminders--syncing t))
      (with-current-buffer (find-file-noselect file)
        (org-save-outline-visibility t
        (let (done-pts new-pts reopen-pts apple-updates changed-positions)
          (org-map-entries
           (lambda ()
             (let* ((id    (org-entry-get nil "REMINDER_ID"))
                    (rlist (or (org-entry-get nil "REMINDER_LIST") default-list))
                    (state (org-get-todo-state)))
               (cond
                ((and (null id) (member state '("TODO" "NEXT" "WAITING")))
                 (push (point-marker) new-pts))
                (id
                 (let ((apple (gethash id apple-by-id)))
                   (cond
                    ((and (member state '("DONE" "CANCELLED"))
                          apple (not (eq (alist-get 'completed apple) t)))
                     ;; Apple shows open but org is DONE.
                     ;; If Apple's modDate grew since our last sync: Apple changed (reopened) → reopen org.
                     ;; Else org's DONE is authoritative → push complete to Apple.
                     (let* ((a-mod (let ((m (alist-get 'modDate apple)))
                                     (and (stringp m) (not (string-empty-p m)) m)))
                            (last  (my/apple-reminders--last-known-mod)))
                       (if (and a-mod (or (null last) (string> a-mod last)))
                           (push (point-marker) reopen-pts)
                         (my/apple-reminders--complete-in-apple rlist id))))
                    ((and (member state '("TODO" "NEXT" "WAITING"))
                          (or (null apple) (eq (alist-get 'completed apple) t)))
                     (push (point-marker) done-pts))
                    ((member state '("TODO" "NEXT" "WAITING"))
                     ;; Two-timestamp conflict resolution:
                     ;; apple-changed = apple-mod > max(REMINDER_APPLE_MOD, REMINDER_ORG_MOD)
                     ;; If Apple changed → Apple wins (pull fields). Else → org wins (push fields).
                     (let* ((a-mod        (let ((m (alist-get 'modDate apple)))
                                            (and (stringp m) (not (string-empty-p m)) m)))
                            (last-known   (my/apple-reminders--last-known-mod))
                            (apple-changed (and a-mod
                                               (or (null last-known)
                                                   (string> a-mod last-known)))))
                       (if apple-changed
                           ;; Apple wins: queue field updates
                           (let* ((a-prio    (or (alist-get 'priority apple) 0))
                                  (a-due     (let ((d (alist-get 'due apple)))
                                               (and (stringp d) (not (string-empty-p d)) d)))
                                  (a-flagged (eq (alist-get 'flagged apple) t))
                                  (p-char    (nth 3 (org-heading-components)))
                                  (o-prio    (cond ((eql p-char ?A) 1)
                                                   ((eql p-char ?B) 5)
                                                   ((eql p-char ?C) 9)
                                                   (t 0)))
                                  (o-due     (let ((dl (org-entry-get nil "DEADLINE")))
                                               (when (and dl (string-match
                                                             "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" dl))
                                                 (match-string 1 dl))))
                                  (o-flagged (not (null (member "flagged" (org-get-tags nil t)))))
                                  (changed   (or (/= a-prio o-prio)
                                                 (not (equal a-due o-due))
                                                 (not (eq a-flagged o-flagged)))))
                             (when changed
                               (push (list (point-marker) rlist
                                           a-prio o-prio a-due o-due a-flagged o-flagged a-mod)
                                     apple-updates)))
                         ;; Org wins: push if org differs from Apple's fetched state
                         (let* ((vals (my/apple-reminders--org-item-values))
                                (needs-push
                                 (or (not (equal (or (alist-get 'title vals) "")
                                                 (or (alist-get 'title apple) "")))
                                     (not (equal (or (alist-get 'notes vals) "")
                                                 (or (alist-get 'notes apple) "")))
                                     (not (= (or (alist-get 'priority vals) 0)
                                             (or (alist-get 'priority apple) 0)))
                                     (not (equal (alist-get 'due vals)
                                                 (let ((d (alist-get 'due apple)))
                                                   (and (stringp d) (not (string-empty-p d)) d))))
                                     (not (eq (alist-get 'flagged vals)
                                              (eq (alist-get 'flagged apple) t))))))
                           (when needs-push
                             (let ((new-mod (my/apple-reminders--update-in-apple rlist id vals)))
                               (when (stringp new-mod)
                                 (org-set-property "REMINDER_ORG_MOD" new-mod)))
                             (setq n-updated (1+ n-updated)))))))))))))
           nil nil)
          (dolist (m (nreverse done-pts))
            (goto-char m)
            (push (point-marker) changed-positions)
            (org-todo "DONE") (set-marker m nil)
            (setq n-done (1+ n-done)))
          (dolist (m (nreverse new-pts))
            (goto-char m)
            (push (point-marker) changed-positions)
            (let* ((rlist (or (org-entry-get nil "REMINDER_LIST") default-list))
                   (new-id (my/apple-reminders--create-in-apple
                            rlist (my/apple-reminders--org-item-values))))
              (when new-id
                (org-set-property "REMINDER_ID"   new-id)
                (org-set-property "REMINDER_LIST" rlist)
                (setq n-pushed (1+ n-pushed)))))
          ;; Apply Apple → org field updates
          (dolist (upd (nreverse apple-updates))
            (cl-destructuring-bind (m _rlist a-prio o-prio a-due o-due a-flagged o-flagged a-mod) upd
              (goto-char m)
              (push (point-marker) changed-positions)
              (unless (= a-prio o-prio)
                (org-priority (cond ((= a-prio 1) ?A)
                                    ((= a-prio 5) ?B)
                                    ((= a-prio 9) ?C)
                                    (t 'remove))))
              (unless (equal a-due o-due)
                (if a-due
                    (org-add-planning-info 'deadline a-due)
                  (org-add-planning-info nil nil 'deadline)))
              (unless (eq a-flagged o-flagged)
                (org-toggle-tag "flagged" (if a-flagged 'on 'off)))
              (when (stringp a-mod)
                (org-set-property "REMINDER_APPLE_MOD" a-mod))
              (setq n-updated (1+ n-updated))
              (set-marker m nil)))
          ;; Apply Apple-reopen: DONE in org, open in Apple, Apple modDate newer → mark org TODO
          (dolist (m (nreverse reopen-pts))
            (goto-char m)
            (push (point-marker) changed-positions)
            (org-todo "TODO")
            (set-marker m nil)
            (setq n-reopened (1+ n-reopened)))
        (let ((known-ids (let (ids)
                           (org-map-entries
                            (lambda () (when-let (id (org-entry-get nil "REMINDER_ID"))
                                         (push id ids)))
                            nil nil)
                           ids)))
          (dolist (entry data)
            (let ((lname (alist-get 'list  entry))
                  (items (alist-get 'items entry)))
              (dolist (item items)
                (when (and (not (member (alist-get 'id item) known-ids))
                           (not (eq (alist-get 'completed item) t)))
                  (my/apple-reminders--goto-list-heading lname)
                  (push (point-marker) changed-positions)
                  (my/apple-reminders--insert-org-heading item lname)
                  (setq n-pulled (1+ n-pulled)))))))
        ;; Stamp REMINDER_APPLE_MOD for all synced entries using the modDate from this fetch.
        ;; max(REMINDER_APPLE_MOD, REMINDER_ORG_MOD) gives the conflict baseline next sync.
        (org-map-entries
         (lambda ()
           (when-let (id (org-entry-get nil "REMINDER_ID"))
             (let* ((a (gethash id apple-by-id))
                    (m (when a (alist-get 'modDate a))))
               (when (stringp m)
                 (org-set-property "REMINDER_APPLE_MOD" m)))))
         nil nil)
        (org-map-entries
         (lambda ()
           (unless (save-excursion (beginning-of-line)
                                   (looking-at "[^\n]*\\[[0-9]*/[0-9]*\\]"))
             (end-of-line) (insert " [/]"))
           (org-update-statistics-cookies nil))
         "LEVEL=1" nil)
        (save-buffer)
        (dolist (m (nreverse changed-positions))
          (when (marker-position m)
            (goto-char m)
            (org-reveal)
            (set-marker m nil)))))
        ))
    (message "Reminders: %d←DONE  %d↑reopened  %d→Apple  %d←Apple  %d updated"
             n-done n-reopened n-pushed n-pulled n-updated)))

;;; Async JXA core

(defvar my/apple-reminders--cache nil
  "Last fetched Reminders data; used for instant re-renders.")

(defvar my/apple-reminders--done-items nil
  "Alist of (list-name . (item ...)) for reminders completed this session.")

(defvar my/apple-reminders--show-done nil
  "When non-nil, show session-completed reminders at the bottom of each list.")

(defcustom my/apple-reminders-agenda-file nil
  "Separate auto-generated org file for org-agenda integration.
nil (default) means use `my/apple-reminders-sync-file' for the agenda directly.
Set to a file path only if you want a separate read-only agenda file."
  :type '(choice (const :tag "Use reminders.org (default)" nil) file)
  :group 'my/apple-reminders)

(defconst my/apple-reminders--fetch-script
  "var app=Application('Reminders'),out=[];
app.lists().forEach(function(l){
  var rs=l.reminders;
  var names=rs.name(),ids=rs.id(),bodies=rs.body(),
      dates=rs.dueDate(),prios=rs.priority(),flags=rs.flagged(),compl=rs.completed(),
      mods=rs.modificationDate();
  var items=[];
  for(var i=0;i<names.length;i++){
    var d=dates[i],md=mods[i];
    items.push({id:ids[i],title:names[i],notes:bodies[i]||'',
                due:(d&&d instanceof Date&&!isNaN(d)&&d.getFullYear()>1970)?(d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')):null,
                priority:prios[i],flagged:flags[i],completed:!!compl[i],
                modDate:(md&&md instanceof Date&&!isNaN(md))?md.toISOString():null});
  }
  out.push({list:l.name(),items:items});
});
JSON.stringify(out);"
  "JXA script returning all open Reminders as JSON. Uses batch property fetch for speed.")

;;; Render (sync, uses cache)

(defun my/apple-reminders--prio-label (p)
  (cond ((eql p 1) "[#A] ") ((eql p 5) "[#B] ") ((eql p 9) "[#C] ") (t "")))

(defun my/apple-reminders--loc-at-point ()
  "Return (list-name . reminder-id) for reminder heading at point, or nil."
  (ignore-errors
    (save-excursion
      (org-back-to-heading t)
      (let ((id   (org-entry-get nil "REMINDER_ID"))
            (list (org-entry-get nil "REMINDER_LIST")))
        (when (and id list) (cons list id))))))

(defun my/apple-reminders--insert-item (item lname state)
  "Insert an org heading for ITEM in list LNAME with todo STATE."
  (let* ((id      (alist-get 'id       item))
         (title   (alist-get 'title    item))
         (notes   (alist-get 'notes    item))
         (due     (alist-get 'due      item))
         (prio    (alist-get 'priority item))
         (flagged (alist-get 'flagged  item)))
    (insert (format "** %s %s%s%s\n"
                    state
                    (my/apple-reminders--prio-label prio)
                    (if (eq flagged t) "★ " "")
                    title))
    (when (and due (not (eq due :null)))
      (insert (format "   DEADLINE: <%s>\n" due)))
    (insert (format "   :PROPERTIES:\n   :REMINDER_ID:   %s\n   :REMINDER_LIST: %s\n   :END:\n"
                    id lname))
    (when (and (stringp notes) (not (string-empty-p notes)))
      (dolist (line (split-string notes "\n"))
        (insert (format "   %s\n" line))))))

(defun my/apple-reminders-dashboard--render (data)
  "Render DATA into *Apple Reminders* without any network call."
  (let ((buf (get-buffer-create "*Apple Reminders*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t)
            (saved-pos (point)))
        (erase-buffer)
        (org-mode)
        (insert "#+TITLE: Apple Reminders\n\n")
        (dolist (entry data)
          (let* ((lname (alist-get 'list  entry))
                 (items (alist-get 'items entry))
                 (done  (cdr (cl-assoc lname my/apple-reminders--done-items :test #'string=))))
            (insert (format "* %s\n" lname))
            (cond
             ((and (null items) (or (null done) (not my/apple-reminders--show-done)))
              (insert "  /No open reminders./\n\n"))
             (t
              (dolist (item items)
                (my/apple-reminders--insert-item item lname "TODO"))
              (when (and done my/apple-reminders--show-done)
                (dolist (item done)
                  (my/apple-reminders--insert-item item lname "DONE")))))))
        (org-content)
        (goto-char (min saved-pos (point-max))))
      (setq buffer-read-only t)
      (let ((map (make-sparse-keymap)))
        (set-keymap-parent map org-mode-map)
        (define-key map (kbd "g")       #'my/apple-reminders-dashboard-refresh)
        (define-key map (kbd "q")       #'quit-window)
        (define-key map (kbd "t")       #'my/apple-reminders-dashboard-complete)
        (define-key map (kbd "C-c C-t") #'my/apple-reminders-dashboard-complete)
        (define-key map (kbd "h")       #'my/apple-reminders-toggle-done)
        (define-key map (kbd "e")       #'my/apple-reminders-dashboard-jump-to-org)
        (use-local-map map)))
    (unless (get-buffer-window buf) (switch-to-buffer buf))))

(defun my/apple-reminders--write-agenda-file (data)
  "Write open reminders from DATA to `my/apple-reminders-agenda-file'."
  (when my/apple-reminders-agenda-file
    (let ((file (expand-file-name my/apple-reminders-agenda-file)))
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert "#+TITLE: Apple Reminders (auto-generated — do not edit)\n")
        (insert "#+STARTUP: overview\n")
        (insert "#+TODO: TODO | DONE\n\n")
        (dolist (entry data)
          (let ((lname (alist-get 'list  entry))
                (items (alist-get 'items entry)))
            (dolist (item items)
              (let* ((title   (alist-get 'title    item))
                     (due     (alist-get 'due      item))
                     (prio    (alist-get 'priority item))
                     (flagged (alist-get 'flagged  item))
                     (id      (alist-get 'id       item)))
                (insert (format "* TODO %s%s%s\n"
                                (my/apple-reminders--prio-label prio)
                                (if (eq flagged t) "★ " "")
                                title))
                (when (and due (not (eq due :null)))
                  (insert (format "  DEADLINE: <%s>\n" due)))
                (insert (format "  :PROPERTIES:\n  :REMINDER_LIST: %s\n  :REMINDER_ID: %s\n  :END:\n"
                                lname id)))))))
      (add-to-list 'org-agenda-files file))))

(defun my/apple-reminders-toggle-done ()
  "Toggle visibility of session-completed reminders at the bottom of each list."
  (interactive)
  (setq my/apple-reminders--show-done (not my/apple-reminders--show-done))
  (when my/apple-reminders--cache
    (my/apple-reminders-dashboard--render my/apple-reminders--cache))
  (message "Done items: %s" (if my/apple-reminders--show-done "shown" "hidden")))

(defun my/apple-reminders-dashboard-refresh ()
  "Fetch all reminders asynchronously, reset session-done list, re-render."
  (interactive)
  (setq my/apple-reminders--done-items nil)
  (message "Apple Reminders: refreshing…")
  (my/apple-reminders--jxa-async
   my/apple-reminders--fetch-script
   (lambda (raw)
     (condition-case err
         (let ((data (json-parse-string raw :object-type 'alist :array-type 'list)))
           (setq my/apple-reminders--cache data)
           (my/apple-reminders--write-agenda-file data)
           (my/apple-reminders-dashboard--render data)
           (message "Apple Reminders: ready."))
       (error (message "Apple Reminders fetch error: %s" err))))))

(defun my/apple-reminders-dashboard ()
  "Open *Apple Reminders* dashboard. Uses cache; press g to fetch fresh data."
  (interactive)
  (if my/apple-reminders--cache
      (my/apple-reminders-dashboard--render my/apple-reminders--cache)
    (my/apple-reminders-dashboard-refresh)))

(run-with-idle-timer 3 nil #'my/apple-reminders--background-pull)

(defun my/apple-reminders-dashboard-jump-to-org ()
  "Open reminders.org at the heading for the reminder at point.
Edit with standard org commands; changes auto-push to Apple on save or
immediately on C-c , (priority), C-c C-d (deadline), C-c C-q (tags)."
  (interactive)
  (let ((loc (my/apple-reminders--loc-at-point)))
    (unless loc (user-error "No reminder at point"))
    (let ((id   (cdr loc))
          (file (expand-file-name my/apple-reminders-sync-file)))
      (unless (file-exists-p file)
        (user-error "reminders.org not found — run C-c r R first to sync"))
      (find-file file)
      (goto-char (point-min))
      (unless (org-find-property "REMINDER_ID" id)
        (user-error "Not in reminders.org yet — run C-c r R to pull it first"))
      (org-reveal))))

(defun my/apple-reminders-dashboard-complete ()
  "Complete the reminder at point. Shows DONE immediately; h to toggle visibility."
  (interactive)
  (let ((loc (my/apple-reminders--loc-at-point)))
    (unless loc (user-error "No reminder at point"))
    (let* ((lname (car loc))
           (id    (cdr loc))
           (list-entry (cl-find lname my/apple-reminders--cache
                                :key (lambda (e) (alist-get 'list e))
                                :test #'string=))
           (item (when list-entry
                   (cl-find id (alist-get 'items list-entry)
                             :key (lambda (e) (alist-get 'id e))
                             :test #'string=))))
      (when item
        ;; Move item from cache to done-items
        (let ((done-cell (cl-assoc lname my/apple-reminders--done-items :test #'string=)))
          (if done-cell
              (setcdr done-cell (cons item (cdr done-cell)))
            (push (cons lname (list item)) my/apple-reminders--done-items)))
        ;; Remove from cache so re-renders don't re-show it as TODO
        (let ((items-cell (assq 'items list-entry)))
          (when items-cell
            (setcdr items-cell
                    (cl-remove id (cdr items-cell)
                               :key (lambda (e) (alist-get 'id e))
                               :test #'string=))))))
    (save-excursion
      (org-back-to-heading t)
      (let ((inhibit-read-only t))
        (org-todo "DONE")))
    (my/apple-reminders--jxa-async
     (format "var app=Application('Reminders');app.lists.byName(%s).reminders.byId(%s).completed=true;"
             (json-encode (car loc)) (json-encode (cdr loc)))
     (lambda (_) (message "Apple Reminders: completed. Press h to show done items.")))))

(defcustom my/apple-reminders-auto-sync-interval 300
  "Seconds between background Apple → org pulls. 0 to disable."
  :type 'integer :group 'my/apple-reminders)

(defvar my/apple-reminders--sync-timer nil)

(defun my/apple-reminders--background-pull ()
  "Async pull: refresh cache and reminders.org for all Apple Reminders lists."
  (unless my/apple-reminders--syncing
    (my/apple-reminders--jxa-async
     my/apple-reminders--fetch-script
     (lambda (raw)
       (condition-case nil
           (let* ((data (json-parse-string raw :object-type 'alist :array-type 'list))
                  (file (expand-file-name my/apple-reminders-sync-file))
                  (apple-by-id (let ((ht (make-hash-table :test #'equal)))
                                  (dolist (entry data)
                                    (dolist (item (alist-get 'items entry))
                                      (puthash (alist-get 'id item) item ht)))
                                  ht)))
             (setq my/apple-reminders--cache data)
             (my/apple-reminders--write-agenda-file data)
             (when (file-exists-p file)
               (let ((my/apple-reminders--syncing t))
                 (with-current-buffer (find-file-noselect file)
                   (org-save-outline-visibility t
                   (let (done-pts reopen-pts)
                     (org-map-entries
                      (lambda ()
                        (let* ((id    (org-entry-get nil "REMINDER_ID"))
                               (state (org-get-todo-state)))
                          (when id
                            (cond
                             ;; Apple completed → mark org DONE
                             ((and (member state '("TODO" "NEXT" "WAITING"))
                                   (let ((a (gethash id apple-by-id)))
                                     (or (null a) (eq (alist-get 'completed a) t))))
                              (push (point-marker) done-pts))
                             ;; Apple reopened → mark org TODO
                             ((and (member state '("DONE" "CANCELLED"))
                                   (let ((a (gethash id apple-by-id)))
                                     (and a (not (eq (alist-get 'completed a) t)))))
                              (push (point-marker) reopen-pts))))))
                      nil nil)
                     (dolist (m (nreverse done-pts))
                       (goto-char m)
                       (org-todo "DONE")
                       (set-marker m nil))
                     (dolist (m (nreverse reopen-pts))
                       (goto-char m)
                       (org-todo "TODO")
                       (set-marker m nil)))
                   ;; Sync fields from Apple → org: two-timestamp guard.
                   ;; Apple wins only if modDate > max(REMINDER_APPLE_MOD, REMINDER_ORG_MOD).
                   (let (field-updates)
                     (org-map-entries
                      (lambda ()
                        (let* ((id     (org-entry-get nil "REMINDER_ID"))
                               (aitem  (when id (gethash id apple-by-id))))
                          (when (and id aitem
                                     (not (eq (alist-get 'completed aitem) t))
                                     (member (org-get-todo-state) '("TODO" "NEXT" "WAITING")))
                            (let* ((a-prio      (or (alist-get 'priority aitem) 0))
                                   (a-due       (let ((d (alist-get 'due aitem)))
                                                  (and (stringp d) (not (string-empty-p d)) d)))
                                   (a-flagged   (eq (alist-get 'flagged aitem) t))
                                   (a-mod       (let ((m (alist-get 'modDate aitem)))
                                                  (and (stringp m) (not (string-empty-p m)) m)))
                                   (p-char      (nth 3 (org-heading-components)))
                                   (o-prio      (cond ((eql p-char ?A) 1)
                                                      ((eql p-char ?B) 5)
                                                      ((eql p-char ?C) 9)
                                                      (t 0)))
                                   (o-due       (let ((dl (org-entry-get nil "DEADLINE")))
                                                  (when (and dl (string-match
                                                                "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" dl))
                                                    (match-string 1 dl))))
                                   (o-flagged   (not (null (member "flagged" (org-get-tags nil t)))))
                                   (changed     (or (/= a-prio o-prio)
                                                    (not (equal a-due o-due))
                                                    (not (eq a-flagged o-flagged))))
                                   (last-known  (my/apple-reminders--last-known-mod))
                                   (apple-changed (and a-mod
                                                       (or (null last-known)
                                                           (string> a-mod last-known)))))
                              (when (and changed apple-changed)
                                (push (list (point-marker)
                                            a-prio o-prio a-due o-due a-flagged o-flagged a-mod)
                                      field-updates))))))
                      nil nil)
                     (dolist (upd (nreverse field-updates))
                       (cl-destructuring-bind (m a-prio o-prio a-due o-due a-flagged o-flagged a-mod) upd
                         (goto-char m)
                         (unless (= a-prio o-prio)
                           (org-priority (cond ((= a-prio 1) ?A)
                                               ((= a-prio 5) ?B)
                                               ((= a-prio 9) ?C)
                                               (t 'remove))))
                         (unless (equal a-due o-due)
                           (if a-due
                               (org-add-planning-info 'deadline a-due)
                             (org-add-planning-info nil nil 'deadline)))
                         (unless (eq a-flagged o-flagged)
                           (org-toggle-tag "flagged" (if a-flagged 'on 'off)))
                         (when (stringp a-mod)
                           (org-set-property "REMINDER_APPLE_MOD" a-mod))
                         (set-marker m nil))))
                   (let ((known-ids (let (ids)
                                      (org-map-entries
                                       (lambda () (when-let (id (org-entry-get nil "REMINDER_ID"))
                                                    (push id ids)))
                                       nil nil)
                                      (dolist (buf (buffer-list))
                                        (with-current-buffer buf
                                          (when (and (derived-mode-p 'org-mode)
                                                     (buffer-file-name)
                                                     (not (string= (expand-file-name (buffer-file-name))
                                                                   (expand-file-name my/apple-reminders-sync-file))))
                                            (ignore-errors
                                              (org-map-entries
                                               (lambda () (when-let (id (org-entry-get nil "REMINDER_ID"))
                                                            (push id ids)))
                                               nil nil)))))
                                      ids)))
                     (dolist (entry data)
                       (let ((lname (alist-get 'list  entry))
                             (items (alist-get 'items entry)))
                         (dolist (item items)
                           (when (and (not (member (alist-get 'id item) known-ids))
                                      (not (eq (alist-get 'completed item) t)))
                             (my/apple-reminders--goto-list-heading lname)
                             (my/apple-reminders--insert-org-heading item lname)
                             ;; Stamp modDate so next sync knows Apple's state
                             (save-excursion
                               (org-back-to-heading t)
                               (let ((md (alist-get 'modDate item)))
                                 (when (stringp md)
                                   (org-set-property "REMINDER_APPLE_MOD" md))))))))
                   ;; Final pass: stamp REMINDER_APPLE_MOD for all items (covers no-change entries)
                   (org-map-entries
                    (lambda ()
                      (when-let (id (org-entry-get nil "REMINDER_ID"))
                        (let* ((a  (gethash id apple-by-id))
                               (md (when a (alist-get 'modDate a))))
                          (when (stringp md)
                            (org-set-property "REMINDER_APPLE_MOD" md)))))
                    nil nil)
                   (org-map-entries
                    (lambda ()
                      (unless (save-excursion (beginning-of-line)
                                              (looking-at "[^\n]*\\[[0-9]*/[0-9]*\\]"))
                        (end-of-line) (insert " [/]"))
                      (org-update-statistics-cookies nil))
                    "LEVEL=1" nil)
                   (save-buffer)
                   ;; Rebuild open agenda buffers so org-hd-marker stays fresh
                   (dolist (buf (buffer-list))
                     (when (buffer-live-p buf)
                       (with-current-buffer buf
                         (when (derived-mode-p 'org-agenda-mode)
                           (let ((inhibit-message t))
                             (ignore-errors (org-agenda-redo)))))))))))))
         (error nil))))))

(defun my/apple-reminders--start-sync-timer ()
  (when (and (> my/apple-reminders-auto-sync-interval 0)
             (null my/apple-reminders--sync-timer))
    (setq my/apple-reminders--sync-timer
          (run-with-timer my/apple-reminders-auto-sync-interval
                          my/apple-reminders-auto-sync-interval
                          #'my/apple-reminders--background-pull))))

(my/apple-reminders--start-sync-timer)

;;; Save hook: push org → Apple when reminders.org is saved

(defun my/apple-reminders--on-save ()
  "When reminders.org is saved, push changes to Apple Reminders."
  (when (and (buffer-file-name)
             (not my/apple-reminders--syncing)
             (string= (expand-file-name (buffer-file-name))
                      (expand-file-name my/apple-reminders-sync-file)))
    (let ((my/apple-reminders--syncing t))
      (my/apple-reminders--push-to-apple)
      (when (buffer-modified-p) (save-buffer)))))

(add-hook 'after-save-hook #'my/apple-reminders--on-save)

;;; Org-capture: C-c c A from any buffer (key "A" avoids conflict with existing templates)

(defun my/apple-reminders--setup-capture ()
  (add-to-list 'org-capture-templates
               `("A" "Apple Reminder" entry
                 (file+headline ,(expand-file-name my/apple-reminders-sync-file)
                                ,(or (my/apple-reminders--default-list) "Reminders"))
                 ,(concat "** TODO %?\n"
                          "   :PROPERTIES:\n"
                          "   :REMINDER_LIST: " (or (my/apple-reminders--default-list) "") "\n"
                          "   :END:\n")
                 :empty-lines 1)))

(if (featurep 'org-capture)
    (my/apple-reminders--setup-capture)
  (with-eval-after-load 'org-capture (my/apple-reminders--setup-capture)))

;;; Org-agenda: register files and add dedicated "A" command

(defun my/apple-reminders--ensure-agenda-files ()
  "Register reminders.org in org-agenda-files and add the 'A' custom command.
reminders.org (editable, all lists) is the primary agenda source.
If `my/apple-reminders-agenda-file' is also set, it is registered too."
  (let* ((sync-file (expand-file-name my/apple-reminders-sync-file))
         (extra     (and my/apple-reminders-agenda-file
                         (expand-file-name my/apple-reminders-agenda-file)))
         (all-files (delq nil (list sync-file extra))))
    ;; Create reminders.org stub if it does not exist yet
    (unless (file-exists-p sync-file)
      (condition-case nil
          (progn
            (make-directory (file-name-directory sync-file) t)
            (with-temp-file sync-file
              (insert "#+TITLE: Reminders\n#+STARTUP: overview\n#+TODO: TODO NEXT WAITING | DONE CANCELLED\n\n"))
            (run-with-idle-timer 1 nil #'my/apple-reminders--background-pull))
        (error nil)))
    (when (file-exists-p sync-file)
      (add-to-list 'org-agenda-files sync-file))
    (when (and extra (file-exists-p extra))
      (add-to-list 'org-agenda-files extra))
    ;; Dedicated agenda command: f12 A  shows all open Apple Reminders
    (add-to-list 'org-agenda-custom-commands
                 `("A" "Apple Reminders" todo "TODO"
                   ((org-agenda-files
                     (cl-remove-if-not #'file-exists-p ',all-files))
                    (org-agenda-overriding-header "Apple Reminders"))))))

(with-eval-after-load 'org-agenda
  (my/apple-reminders--ensure-agenda-files))
(my/apple-reminders--ensure-agenda-files)
(add-hook 'org-agenda-mode-hook #'my/apple-reminders--ensure-agenda-files)

;;; Global bindings — work from any buffer
(global-set-key (kbd "C-c r d") #'my/apple-reminders-dashboard)
(global-set-key (kbd "C-c r l") #'my/apple-reminders-show-lists)
(global-set-key (kbd "C-c r L") #'my/apple-reminders-create-list)
(global-set-key (kbd "C-c r a") #'my/apple-reminders-add)
(global-set-key (kbd "C-c r R") #'my/apple-reminders-sync)

;;; Org-specific bindings — only meaningful in org buffers
(defun my/apple-reminders--setup-org-keys ()
  (define-key org-mode-map (kbd "C-c r p") #'my/org-heading-to-reminder)
  (define-key org-mode-map (kbd "C-c r R") #'my/apple-reminders-sync))

(if (featurep 'org)
    (my/apple-reminders--setup-org-keys)
  (with-eval-after-load 'org (my/apple-reminders--setup-org-keys)))

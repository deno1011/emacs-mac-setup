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

(defcustom my/apple-reminders-default-list "Emacs"
  "Name of the Apple Reminders list used for Org-synced items.
Created on first use if it does not exist."
  :type 'string
  :group 'my/apple-reminders)

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


(defun my/apple-reminders-show (&optional list-name)
  "Show open reminders from LIST-NAME (default: `my/apple-reminders-default-list')."
  (interactive)
  (let ((list (or list-name my/apple-reminders-default-list)))
    (message "%s" (my/apple-reminders--run "show" list))))

(defun my/apple-reminders-add (title &optional list-name due-date notes)
  "Add a reminder TITLE to LIST-NAME with optional DUE-DATE and NOTES.
DUE-DATE is an ISO date string like \"2025-12-31\" or natural language
like \"tomorrow 9am\" — reminders-cli parses both."
  (interactive
   (list (read-string "Reminder: ")
         (completing-read "List: " (my/apple-reminders-lists) nil nil
                          my/apple-reminders-default-list)
         (read-string "Due (optional, e.g. 2025-12-31 or 'tomorrow 9am'): ")
         nil))
  (let* ((list (or list-name my/apple-reminders-default-list))
         (args (append (list "add" list title)
                       (when (and due-date (not (string-empty-p due-date)))
                         (list "--due-date" due-date))
                       (when (and notes (not (string-empty-p notes)))
                         (list "--notes" notes)))))
    (apply #'my/apple-reminders--run args)
    (message "Added to Apple Reminders [%s]: %s%s" list title
             (if (and due-date (not (string-empty-p due-date)))
                 (format " (due %s)" due-date) ""))))

(defun my/apple-reminders-complete (list-name index)
  "Mark reminder at INDEX in LIST-NAME as completed.
INDEX matches the number shown by `my/apple-reminders-show'."
  (interactive
   (let* ((list (completing-read "List: " (my/apple-reminders-lists) nil t
                                 my/apple-reminders-default-list))
          (idx (read-number "Index: ")))
     (list list idx)))
  (my/apple-reminders--run "complete" list-name (number-to-string index))
  (message "Completed [%s] #%d" list-name index))

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
           (ps    (org-entry-get nil "PRIORITY"))
           (prio  (cond ((string= ps "A") 1)
                        ((string= ps "B") 5)
                        ((string= ps "C") 9)
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
                            my/apple-reminders-default-list))))
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org-mode buffer"))
  (let* ((list (or list-name my/apple-reminders-default-list))
         (vals (my/apple-reminders--org-item-values))
         (new-id (my/apple-reminders--create-in-apple list vals)))
    (when new-id
      (org-set-property "REMINDER_ID"   new-id)
      (org-set-property "REMINDER_LIST" list)
      (message "Pushed to Apple Reminders [%s]: %s" list (alist-get 'title vals)))))

(defun my/apple-reminders--on-todo-state-change ()
  "Instantly sync org TODO state change to Apple Reminders via REMINDER_ID.
DONE/CANCELLED → completed=true. TODO/NEXT/WAITING → completed=false (reopen)."
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
                 (json-encode list) (json-encode id))))))))

(add-hook 'org-after-todo-state-change-hook #'my/apple-reminders--on-todo-state-change)

(defcustom my/apple-reminders-sync-list my/apple-reminders-default-list
  "Apple Reminders list used for bidirectional sync with `my/apple-reminders-sync-file'."
  :type 'string :group 'my/apple-reminders)

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

(defun my/apple-reminders--complete-in-apple (list-name id)
  "Mark Apple reminder ID in LIST-NAME as completed (async)."
  (my/apple-reminders--jxa-async
   (format "Application('Reminders').lists.byName(%s).reminders.byId(%s).completed=true;"
           (json-encode list-name) (json-encode id))))

(defun my/apple-reminders--create-in-apple (list-name vals)
  "Create Apple reminder in LIST-NAME from VALS alist. Returns new ID string or nil."
  (let* ((title   (alist-get 'title    vals ""))
         (notes   (alist-get 'notes    vals ""))
         (prio    (alist-get 'priority vals 0))
         (due     (alist-get 'due      vals))
         (flagged (alist-get 'flagged  vals))
         (script
          (format
           "var app=Application('Reminders'),list=app.lists.byName(%s);
list.reminders.push(app.Reminder({name:%s,body:%s,priority:%d,flagged:%s%s}));
var f=list.reminders.whose({name:%s,completed:false})();
JSON.stringify(f[f.length-1].id());"
           (json-encode list-name)
           (json-encode title) (json-encode notes) prio
           (if flagged "true" "false")
           (if due (format ",dueDate:new Date(%s)" (json-encode (concat due "T00:00:00"))) "")
           (json-encode title))))
    (condition-case nil
        (json-parse-string (my/apple-reminders--jxa-run script))
      (error nil))))

(defun my/apple-reminders--update-in-apple (list-name id vals)
  "Push VALS alist to Apple reminder ID in LIST-NAME (async). Org wins."
  (let* ((title   (alist-get 'title    vals ""))
         (notes   (alist-get 'notes    vals ""))
         (prio    (alist-get 'priority vals 0))
         (due     (alist-get 'due      vals))
         (flagged (alist-get 'flagged  vals))
         (script
          (format
           "var r=Application('Reminders').lists.byName(%s).reminders.byId(%s);
r.name=%s;r.body=%s;r.priority=%d;r.flagged=%s;%s"
           (json-encode list-name) (json-encode id)
           (json-encode title) (json-encode notes) prio
           (if flagged "true" "false")
           (if due
               (format "r.dueDate=new Date(%s);" (json-encode (concat due "T00:00:00")))
             "r.dueDate=null;"))))
    (my/apple-reminders--jxa-async script)))

(defun my/apple-reminders--insert-org-heading (item list-name)
  "Insert org heading for Apple ITEM alist at point."
  (let* ((id      (alist-get 'id       item))
         (title   (alist-get 'title    item))
         (notes   (alist-get 'notes    item))
         (due     (alist-get 'due      item))
         (prio    (alist-get 'priority item))
         (flagged (alist-get 'flagged  item)))
    (unless (bolp) (insert "\n"))
    (insert (format "* TODO %s%s%s\n"
                    (my/apple-reminders--prio-label prio)
                    (if (eq flagged t) "★ " "")
                    title))
    (when (and due (not (eq due :null)))
      (insert (format "  DEADLINE: <%s>\n" due)))
    (insert (format "  :PROPERTIES:\n  :REMINDER_ID:   %s\n  :REMINDER_LIST: %s\n  :END:\n"
                    id list-name))
    (when (and (stringp notes) (not (string-empty-p notes)))
      (dolist (line (split-string notes "\n"))
        (insert (format "  %s\n" line))))))

;;; Push-only (org → Apple): called from save hook

(defun my/apple-reminders--push-to-apple ()
  "Push org → Apple only. No fetch. New items get REMINDER_ID stamped back."
  (let* ((list-name my/apple-reminders-sync-list)
         (n-new 0) (n-updated 0)
         new-pts)
    (org-map-entries
     (lambda ()
       (let* ((id    (org-entry-get nil "REMINDER_ID"))
              (rlist (or (org-entry-get nil "REMINDER_LIST") list-name))
              (state (org-get-todo-state)))
         (cond
          ((and (null id) (member state '("TODO" "NEXT" "WAITING")))
           (push (point-marker) new-pts))
          ((and id (member state '("DONE" "CANCELLED")))
           (my/apple-reminders--complete-in-apple rlist id))
          ((and id (member state '("TODO" "NEXT" "WAITING")))
           (my/apple-reminders--update-in-apple
            rlist id (my/apple-reminders--org-item-values))
           (setq n-updated (1+ n-updated))))))
     nil nil)
    (dolist (m (nreverse new-pts))
      (goto-char m)
      (when-let (new-id (my/apple-reminders--create-in-apple
                         list-name (my/apple-reminders--org-item-values)))
        (org-set-property "REMINDER_ID"   new-id)
        (org-set-property "REMINDER_LIST" list-name)
        (setq n-new (1+ n-new))))
    (message "Reminders push: %d new, %d updated." n-new n-updated)))

;;; Full bidirectional sync (C-c r R)

(defun my/apple-reminders-sync ()
  "Full bidirectional sync: `my/apple-reminders-sync-file' ↔ `my/apple-reminders-sync-list'.

- New org item (no REMINDER_ID) → created in Apple, ID stamped back.
- Open in both → org values pushed to Apple (org wins on conflict).
- DONE/CANCELLED in org, open in Apple → Apple completed.
- Open in org, completed/gone in Apple → org marked DONE.
- Open in Apple, missing from org → pulled as new TODO heading."
  (interactive)
  (message "Reminders: syncing…")
  (let* ((list-name my/apple-reminders-sync-list)
         (file      (expand-file-name my/apple-reminders-sync-file))
         (fetch-script
          (format
           "var app=Application('Reminders'),list=app.lists.byName(%s),rs=list.reminders;
var names=rs.name(),ids=rs.id(),bodies=rs.body(),dates=rs.dueDate(),
    prios=rs.priority(),flags=rs.flagged(),compl=rs.completed();
var out=[];for(var i=0;i<names.length;i++){var d=dates[i];
  out.push({id:ids[i],title:names[i],notes:bodies[i]||'',
            due:d?d.toISOString().slice(0,10):null,
            priority:prios[i],flagged:flags[i],completed:compl[i]});}
JSON.stringify(out);"
           (json-encode list-name)))
         (raw (my/apple-reminders--jxa-run fetch-script))
         (apple-items
          (condition-case nil
              (json-parse-string raw :object-type 'alist :array-type 'list)
            (error (user-error "Reminders sync: fetch failed — %s" raw))))
         (apple-by-id (let ((ht (make-hash-table :test #'equal)))
                        (dolist (i apple-items) (puthash (alist-get 'id i) i ht))
                        ht))
         (n-done 0) (n-pushed 0) (n-pulled 0) (n-updated 0))
    (unless (file-exists-p file)
      (with-temp-file file
        (insert (format
                 "#+TITLE: Reminders — %s\n#+STARTUP: overview\n#+TODO: TODO NEXT WAITING | DONE CANCELLED\n\n"
                 list-name))))
    (let ((my/apple-reminders--syncing t))
      (with-current-buffer (find-file-noselect file)
        (let (done-pts new-pts)
          (org-map-entries
           (lambda ()
             (let* ((id    (org-entry-get nil "REMINDER_ID"))
                    (rlist (or (org-entry-get nil "REMINDER_LIST") list-name))
                    (state (org-get-todo-state)))
               (cond
                ((and (null id) (member state '("TODO" "NEXT" "WAITING")))
                 (push (point-marker) new-pts))
                (id
                 (let ((apple (gethash id apple-by-id)))
                   (cond
                    ((and (member state '("DONE" "CANCELLED"))
                          apple (not (eq (alist-get 'completed apple) t)))
                     (my/apple-reminders--complete-in-apple rlist id))
                    ((and (member state '("TODO" "NEXT" "WAITING"))
                          (or (null apple) (eq (alist-get 'completed apple) t)))
                     (push (point-marker) done-pts))
                    ((member state '("TODO" "NEXT" "WAITING"))
                     (my/apple-reminders--update-in-apple
                      rlist id (my/apple-reminders--org-item-values))
                     (setq n-updated (1+ n-updated)))))))))
           nil nil)
          (dolist (m (nreverse done-pts))
            (goto-char m) (org-todo "DONE") (set-marker m nil)
            (setq n-done (1+ n-done)))
          (dolist (m (nreverse new-pts))
            (goto-char m)
            (when-let (new-id (my/apple-reminders--create-in-apple
                               list-name (my/apple-reminders--org-item-values)))
              (org-set-property "REMINDER_ID"   new-id)
              (org-set-property "REMINDER_LIST" list-name)
              (setq n-pushed (1+ n-pushed)))))
        (let ((known-ids (let (ids)
                           (org-map-entries
                            (lambda () (when-let (id (org-entry-get nil "REMINDER_ID"))
                                         (push id ids)))
                            nil nil)
                           ids)))
          (dolist (item apple-items)
            (when (and (not (eq (alist-get 'completed item) t))
                       (not (member (alist-get 'id item) known-ids)))
              (goto-char (point-max))
              (my/apple-reminders--insert-org-heading item list-name)
              (setq n-pulled (1+ n-pulled)))))
        (save-buffer)))
    (message "Reminders: %d←DONE  %d→Apple  %d←Apple  %d updated"
             n-done n-pushed n-pulled n-updated)))

;;; Async JXA core

(defvar my/apple-reminders--cache nil
  "Last fetched Reminders data; used for instant re-renders.")

(defvar my/apple-reminders--done-items nil
  "Alist of (list-name . (item ...)) for reminders completed this session.")

(defvar my/apple-reminders--show-done nil
  "When non-nil, show session-completed reminders at the bottom of each list.")

(defcustom my/apple-reminders-agenda-file
  (expand-file-name "~/org/reminders-agenda.org")
  "Org file written on each dashboard refresh for org-agenda integration.
Set to nil to disable."
  :type '(choice file (const nil))
  :group 'my/apple-reminders)

(defconst my/apple-reminders--fetch-script
  "var app=Application('Reminders'),out=[];
app.lists().forEach(function(l){
  var rs=l.reminders;
  var names=rs.name(),ids=rs.id(),bodies=rs.body(),
      dates=rs.dueDate(),prios=rs.priority(),flags=rs.flagged(),compl=rs.completed();
  var items=[];
  for(var i=0;i<names.length;i++){
    if(compl[i]) continue;
    var d=dates[i];
    items.push({id:ids[i],title:names[i],notes:bodies[i]||'',
                due:d?d.toISOString().slice(0,10):null,
                priority:prios[i],flagged:flags[i]});
  }
  out.push({list:l.name(),items:items});
});
JSON.stringify(out);"
  "JXA script returning all open Reminders as JSON. Uses batch property fetch for speed.")

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
        (define-key map (kbd "e t")     #'my/apple-reminders-dashboard-edit-title)
        (define-key map (kbd "e n")     #'my/apple-reminders-dashboard-edit-notes)
        (define-key map (kbd "e d")     #'my/apple-reminders-dashboard-edit-due)
        (define-key map (kbd "e p")     #'my/apple-reminders-dashboard-edit-priority)
        (use-local-map map)))
    (unless (get-buffer-window buf) (switch-to-buffer buf))))

(defun my/apple-reminders--write-agenda-file (data)
  "Write open reminders from DATA to `my/apple-reminders-agenda-file'."
  (when my/apple-reminders-agenda-file
    (let ((file (expand-file-name my/apple-reminders-agenda-file)))
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

;;; Edit commands — prompt instantly, update + refresh async

(defun my/apple-reminders--update-then-refresh (script)
  "Run JXA update SCRIPT async, then trigger a dashboard refresh after a short delay."
  (message "Apple Reminders: updating…")
  (my/apple-reminders--jxa-async script
    (lambda (_) (run-with-timer 1.0 nil #'my/apple-reminders-dashboard-refresh))))

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

(defun my/apple-reminders-dashboard-edit-title ()
  "Edit the title of the reminder at point."
  (interactive)
  (let ((loc (my/apple-reminders--loc-at-point)))
    (unless loc (user-error "No reminder at point"))
    (let ((new (read-string "Title: "
                            (save-excursion (org-back-to-heading t)
                                            (org-get-heading t t t t)))))
      (my/apple-reminders--update-then-refresh
       (format "var app=Application('Reminders');app.lists.byName(%s).reminders.byId(%s).name=%s;"
               (json-encode (car loc)) (json-encode (cdr loc)) (json-encode new))))))

(defun my/apple-reminders-dashboard-edit-notes ()
  "Edit the notes of the reminder at point."
  (interactive)
  (let ((loc (my/apple-reminders--loc-at-point)))
    (unless loc (user-error "No reminder at point"))
    (let* ((current (save-excursion
                      (org-back-to-heading t)
                      (string-trim
                       (buffer-substring-no-properties
                        (save-excursion (org-end-of-meta-data t) (point))
                        (save-excursion (org-end-of-subtree t)   (point))))))
           (new (read-string "Notes: " current)))
      (my/apple-reminders--update-then-refresh
       (format "var app=Application('Reminders');app.lists.byName(%s).reminders.byId(%s).body=%s;"
               (json-encode (car loc)) (json-encode (cdr loc)) (json-encode new))))))

(defun my/apple-reminders-dashboard-edit-due ()
  "Edit the due date of the reminder at point (YYYY-MM-DD, empty to clear)."
  (interactive)
  (let ((loc (my/apple-reminders--loc-at-point)))
    (unless loc (user-error "No reminder at point"))
    (let ((new (read-string "Due date (YYYY-MM-DD, empty to clear): ")))
      (my/apple-reminders--update-then-refresh
       (if (string-empty-p new)
           (format "var app=Application('Reminders');app.lists.byName(%s).reminders.byId(%s).dueDate=null;"
                   (json-encode (car loc)) (json-encode (cdr loc)))
         (format "var app=Application('Reminders');app.lists.byName(%s).reminders.byId(%s).dueDate=new Date(%s);"
                 (json-encode (car loc)) (json-encode (cdr loc))
                 (json-encode (concat new "T00:00:00"))))))))

(defun my/apple-reminders-dashboard-edit-priority ()
  "Change the priority of the reminder at point."
  (interactive)
  (let ((loc (my/apple-reminders--loc-at-point)))
    (unless loc (user-error "No reminder at point"))
    (let* ((choice (completing-read "Priority: " '("None" "High" "Medium" "Low") nil t))
           (prio   (cond ((string= choice "High")   1)
                         ((string= choice "Medium")  5)
                         ((string= choice "Low")     9)
                         (t 0))))
      (my/apple-reminders--update-then-refresh
       (format "var app=Application('Reminders');app.lists.byName(%s).reminders.byId(%s).priority=%d;"
               (json-encode (car loc)) (json-encode (cdr loc)) prio)))))

(defcustom my/apple-reminders-auto-sync-interval 300
  "Seconds between background Apple → org pulls. 0 to disable."
  :type 'integer :group 'my/apple-reminders)

(defvar my/apple-reminders--sync-timer nil)

(defun my/apple-reminders--background-pull ()
  "Async pull: refresh cache, agenda file, and reminders.org (pull direction only)."
  (unless my/apple-reminders--syncing
    (my/apple-reminders--jxa-async
     my/apple-reminders--fetch-script
     (lambda (raw)
       (condition-case nil
           (let* ((data      (json-parse-string raw :object-type 'alist :array-type 'list))
                  (list-name my/apple-reminders-sync-list)
                  (file      (expand-file-name my/apple-reminders-sync-file))
                  (sync-entry (cl-find list-name data
                                       :key (lambda (e) (alist-get 'list e))
                                       :test #'string=))
                  (sync-items (when sync-entry (alist-get 'items sync-entry)))
                  (apple-by-id (let ((ht (make-hash-table :test #'equal)))
                                  (dolist (item (or sync-items '()))
                                    (puthash (alist-get 'id item) item ht))
                                  ht)))
             ;; Update dashboard cache and agenda file
             (setq my/apple-reminders--cache data)
             (my/apple-reminders--write-agenda-file data)
             ;; Pull-only sync to reminders.org
             (when (and sync-items (file-exists-p file))
               (let ((my/apple-reminders--syncing t))
                 (with-current-buffer (find-file-noselect file)
                   ;; Mark Apple-completed as DONE in org
                   (let (done-pts)
                     (org-map-entries
                      (lambda ()
                        (when (and (org-entry-get nil "REMINDER_ID")
                                   (member (org-get-todo-state) '("TODO" "NEXT" "WAITING")))
                          (unless (gethash (org-entry-get nil "REMINDER_ID") apple-by-id)
                            (push (point-marker) done-pts))))
                      nil nil)
                     (dolist (m (nreverse done-pts))
                       (goto-char m) (org-todo "DONE") (set-marker m nil)))
                   ;; Pull Apple items not yet in org
                   (let ((known-ids (let (ids)
                                      (org-map-entries
                                       (lambda () (when-let (id (org-entry-get nil "REMINDER_ID"))
                                                    (push id ids)))
                                       nil nil)
                                      ids)))
                     (dolist (item sync-items)
                       (when (not (member (alist-get 'id item) known-ids))
                         (goto-char (point-max))
                         (my/apple-reminders--insert-org-heading item list-name))))
                   (save-buffer)))))
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

;;; Org-capture: C-c c r from any buffer

(defun my/apple-reminders--setup-capture ()
  (add-to-list 'org-capture-templates
               `("r" "Apple Reminder" entry
                 (file ,(expand-file-name my/apple-reminders-sync-file))
                 ,(concat "* TODO %?\n"
                          "  :PROPERTIES:\n"
                          "  :REMINDER_LIST: " my/apple-reminders-sync-list "\n"
                          "  :END:\n")
                 :empty-lines 1)))

(if (featurep 'org-capture)
    (my/apple-reminders--setup-capture)
  (with-eval-after-load 'org-capture (my/apple-reminders--setup-capture)))

;;; Org-agenda: add both files so all reminders appear in M-x org-agenda

(defun my/apple-reminders--ensure-agenda-files ()
  "Register reminder files in org-agenda-files; create agenda stub if needed."
  (let ((sync   (expand-file-name my/apple-reminders-sync-file))
        (agenda (and my/apple-reminders-agenda-file
                     (expand-file-name my/apple-reminders-agenda-file))))
    ;; reminders.org: only add when it exists (created by C-c r R).
    (when (file-exists-p sync) (add-to-list 'org-agenda-files sync))
    (when agenda
      ;; reminders-agenda.org: auto-generated, create stub so agenda doesn't warn.
      (unless (file-exists-p agenda)
        (if my/apple-reminders--cache
            (my/apple-reminders--write-agenda-file my/apple-reminders--cache)
          (with-temp-file agenda
            (insert "#+TITLE: Apple Reminders (auto-generated — do not edit)\n")
            (insert "#+STARTUP: overview\n")
            (insert "#+TODO: TODO | DONE\n\n"))
          (run-with-idle-timer 1 nil #'my/apple-reminders--background-pull)))
      (add-to-list 'org-agenda-files agenda))))

(my/apple-reminders--ensure-agenda-files)
(add-hook 'org-agenda-mode-hook #'my/apple-reminders--ensure-agenda-files)

;;; Global bindings — work from any buffer
(global-set-key (kbd "C-c r d") #'my/apple-reminders-dashboard)
(global-set-key (kbd "C-c r l") #'my/apple-reminders-show-lists)
(global-set-key (kbd "C-c r a") #'my/apple-reminders-add)
(global-set-key (kbd "C-c r s") #'my/apple-reminders-show)

;;; Org-specific bindings — only meaningful in org buffers
(defun my/apple-reminders--setup-org-keys ()
  (define-key org-mode-map (kbd "C-c r p") #'my/org-heading-to-reminder)
  (define-key org-mode-map (kbd "C-c r R") #'my/apple-reminders-sync))

(if (featurep 'org)
    (my/apple-reminders--setup-org-keys)
  (with-eval-after-load 'org (my/apple-reminders--setup-org-keys)))

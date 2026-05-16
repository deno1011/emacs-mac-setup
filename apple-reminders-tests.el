;;; apple-reminders-tests.el --- ERT tests for apple-reminders integration -*- lexical-binding: t -*-

;; Run with: M-x ert RET t RET
;; Or from shell: emacs --batch -l apple-reminders.el -l apple-reminders-tests.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'org)
(require 'cl-lib)
(require 'json)


;;;; ──────────────────────────────────────────────────────────────────
;;;; 1. Pure functions — no mocking needed
;;;; ──────────────────────────────────────────────────────────────────

;;; my/apple-reminders--prio-label

(ert-deftest ar/prio-label-high ()
  "Priority 1 (high) → \"[#A] \"."
  (should (string= (my/apple-reminders--prio-label 1) "[#A] ")))

(ert-deftest ar/prio-label-medium ()
  "Priority 5 (medium) → \"[#B] \"."
  (should (string= (my/apple-reminders--prio-label 5) "[#B] ")))

(ert-deftest ar/prio-label-low ()
  "Priority 9 (low) → \"[#C] \"."
  (should (string= (my/apple-reminders--prio-label 9) "[#C] ")))

(ert-deftest ar/prio-label-none ()
  "Priority 0 or any non-mapped value → empty string."
  (should (string= (my/apple-reminders--prio-label 0)   ""))
  (should (string= (my/apple-reminders--prio-label 3)   ""))
  (should (string= (my/apple-reminders--prio-label 99)  "")))


;;; my/apple-reminders--extract-notes

(ert-deftest ar/extract-notes-plain-body ()
  "Plain text body after heading is returned verbatim."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO My Task\nSome notes here\n")
    (goto-char (point-min))
    (should (string= (my/apple-reminders--extract-notes) "Some notes here"))))

(ert-deftest ar/extract-notes-strips-logbook ()
  "LOGBOOK drawer is stripped; remaining text is kept."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO My Task\n:LOGBOOK:\n- State \"DONE\" [2025-01-01]\n:END:\nReal notes\n")
    (goto-char (point-min))
    (should (string= (my/apple-reminders--extract-notes) "Real notes"))))

(ert-deftest ar/extract-notes-empty-heading ()
  "Heading with no body (only PROPERTIES) returns empty string."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO My Task\n:PROPERTIES:\n:REMINDER_ID: x\n:END:\n")
    (goto-char (point-min))
    (should (string= (my/apple-reminders--extract-notes) ""))))

(ert-deftest ar/extract-notes-multiline ()
  "Multi-line body is returned with all lines."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Task\nLine one\nLine two\nLine three\n")
    (goto-char (point-min))
    (let ((notes (my/apple-reminders--extract-notes)))
      (should (string-match-p "Line one" notes))
      (should (string-match-p "Line two" notes))
      (should (string-match-p "Line three" notes)))))


;;; my/apple-reminders--org-item-values

(ert-deftest ar/org-item-values-basic-title ()
  "Plain TODO heading: title extracted correctly."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Buy groceries\n")
    (goto-char (point-min))
    (let ((vals (my/apple-reminders--org-item-values)))
      (should (string= (alist-get 'title vals) "Buy groceries")))))

(ert-deftest ar/org-item-values-strips-priority-prefix ()
  "Priority prefix [#A] is stripped from the title."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO [#A] Urgent meeting\n")
    (goto-char (point-min))
    (should (string= (alist-get 'title (my/apple-reminders--org-item-values))
                     "Urgent meeting"))))

(ert-deftest ar/org-item-values-strips-star-prefix ()
  "Flagged ★ prefix is stripped from the title."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO ★ Starred item\n")
    (goto-char (point-min))
    (should (string= (alist-get 'title (my/apple-reminders--org-item-values))
                     "Starred item"))))

(ert-deftest ar/org-item-values-priority-a ()
  "Org priority A → Apple priority 1."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO [#A] High\n")
    (goto-char (point-min))
    (should (= (alist-get 'priority (my/apple-reminders--org-item-values)) 1))))

(ert-deftest ar/org-item-values-priority-b ()
  "Org priority B → Apple priority 5."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO [#B] Medium\n")
    (goto-char (point-min))
    (should (= (alist-get 'priority (my/apple-reminders--org-item-values)) 5))))

(ert-deftest ar/org-item-values-priority-c ()
  "Org priority C → Apple priority 9."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO [#C] Low\n")
    (goto-char (point-min))
    (should (= (alist-get 'priority (my/apple-reminders--org-item-values)) 9))))

(ert-deftest ar/org-item-values-no-priority ()
  "No priority → 0."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Plain task\n")
    (goto-char (point-min))
    (should (= (alist-get 'priority (my/apple-reminders--org-item-values)) 0))))

(ert-deftest ar/org-item-values-deadline ()
  "DEADLINE timestamp is extracted as ISO date string."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Task\nDEADLINE: <2025-12-31 Wed>\n")
    (goto-char (point-min))
    (should (string= (alist-get 'due (my/apple-reminders--org-item-values))
                     "2025-12-31"))))

(ert-deftest ar/org-item-values-no-deadline ()
  "No DEADLINE → due is nil."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Task without deadline\n")
    (goto-char (point-min))
    (should (null (alist-get 'due (my/apple-reminders--org-item-values))))))

(ert-deftest ar/org-item-values-flagged-tag ()
  ":flagged: tag → flagged field is t."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Important item  :flagged:\n")
    (goto-char (point-min))
    (should (eq (alist-get 'flagged (my/apple-reminders--org-item-values)) t))))

(ert-deftest ar/org-item-values-not-flagged ()
  "No :flagged: tag → flagged field is nil."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Plain item  :work:\n")
    (goto-char (point-min))
    (should (null (alist-get 'flagged (my/apple-reminders--org-item-values))))))

(ert-deftest ar/org-item-values-notes-body ()
  "Body text ends up in the notes field."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Task\nRemember to call Alice\n")
    (goto-char (point-min))
    (should (string-match-p "Alice"
                            (alist-get 'notes (my/apple-reminders--org-item-values))))))


;;; my/apple-reminders--loc-at-point

(ert-deftest ar/loc-at-point-present ()
  "Returns (list-name . reminder-id) when both properties exist."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Task\n:PROPERTIES:\n:REMINDER_ID:   abc-123\n:REMINDER_LIST: MyList\n:END:\n")
    (goto-char (point-min))
    (let ((loc (my/apple-reminders--loc-at-point)))
      (should loc)
      (should (string= (car loc) "MyList"))
      (should (string= (cdr loc) "abc-123")))))

(ert-deftest ar/loc-at-point-no-properties ()
  "Returns nil when REMINDER_ID is absent."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Plain task\n")
    (goto-char (point-min))
    (should (null (my/apple-reminders--loc-at-point)))))

(ert-deftest ar/loc-at-point-partial-properties ()
  "Returns nil when only one of the two properties is present."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Task\n:PROPERTIES:\n:REMINDER_ID: id-only\n:END:\n")
    (goto-char (point-min))
    (should (null (my/apple-reminders--loc-at-point)))))


;;;; ──────────────────────────────────────────────────────────────────
;;;; 2. Auto-detection — mock my/apple-reminders-lists
;;;; ──────────────────────────────────────────────────────────────────

(ert-deftest ar/default-list-uses-custom-when-set ()
  "Returns my/apple-reminders-default-list when it is a non-nil string."
  (let ((my/apple-reminders-default-list "PinnedList"))
    (should (string= (my/apple-reminders--default-list) "PinnedList"))))

(ert-deftest ar/default-list-auto-detects-first ()
  "When default-list is nil, returns the first list from the CLI."
  (let ((my/apple-reminders-default-list nil))
    (cl-letf (((symbol-function 'my/apple-reminders-lists)
               (lambda () '("Alpha" "Beta" "Gamma"))))
      (should (string= (my/apple-reminders--default-list) "Alpha")))))

(ert-deftest ar/default-list-nil-when-cli-fails ()
  "When CLI errors and default-list is nil, returns nil gracefully."
  (let ((my/apple-reminders-default-list nil))
    (cl-letf (((symbol-function 'my/apple-reminders-lists)
               (lambda () (error "CLI not available"))))
      (should (null (my/apple-reminders--default-list))))))

(ert-deftest ar/default-list-nil-when-no-lists ()
  "When CLI returns empty list and default-list is nil, returns nil."
  (let ((my/apple-reminders-default-list nil))
    (cl-letf (((symbol-function 'my/apple-reminders-lists)
               (lambda () '())))
      (should (null (my/apple-reminders--default-list))))))


;;;; ──────────────────────────────────────────────────────────────────
;;;; 3. CLI wrapper — mock executable-find / call-process
;;;; ──────────────────────────────────────────────────────────────────

(ert-deftest ar/run-signals-user-error-when-no-cli ()
  "Signals user-error when reminders-cli binary is not found."
  (cl-letf (((symbol-function 'executable-find) (lambda (_) nil)))
    (should-error (my/apple-reminders--run "show-lists") :type 'user-error)))

(ert-deftest ar/lists-splits-output-on-newlines ()
  "my/apple-reminders-lists returns a list split on newlines."
  (cl-letf (((symbol-function 'my/apple-reminders--run)
             (lambda (&rest _) "Inbox\nWork\nPersonal")))
    (should (equal (my/apple-reminders-lists) '("Inbox" "Work" "Personal")))))

(ert-deftest ar/lists-ignores-blank-lines ()
  "Blank lines in CLI output are excluded from the result."
  (cl-letf (((symbol-function 'my/apple-reminders--run)
             (lambda (&rest _) "Inbox\n\nWork\n")))
    (should (equal (my/apple-reminders-lists) '("Inbox" "Work")))))

(ert-deftest ar/add-calls-cli-with-correct-args ()
  "my/apple-reminders-add passes title and list to CLI."
  (let (received-args)
    (cl-letf (((symbol-function 'my/apple-reminders--run)
               (lambda (&rest args) (setq received-args args) ""))
              ((symbol-function 'my/apple-reminders--default-list)
               (lambda () "Inbox")))
      (my/apple-reminders-add "Call Alice" "Inbox" nil nil)
      (should (equal (car received-args) "add"))
      (should (member "Inbox" received-args))
      (should (member "Call Alice" received-args)))))

(ert-deftest ar/add-passes-due-date-flag ()
  "Due date is passed as --due-date when provided."
  (let (received-args)
    (cl-letf (((symbol-function 'my/apple-reminders--run)
               (lambda (&rest args) (setq received-args args) ""))
              ((symbol-function 'my/apple-reminders--default-list)
               (lambda () "Inbox")))
      (my/apple-reminders-add "Doctor" "Inbox" "2025-06-01" nil)
      (should (member "--due-date" received-args))
      (should (member "2025-06-01" received-args)))))

(ert-deftest ar/add-omits-due-date-when-empty ()
  "Empty string due date does not add --due-date flag."
  (let (received-args)
    (cl-letf (((symbol-function 'my/apple-reminders--run)
               (lambda (&rest args) (setq received-args args) ""))
              ((symbol-function 'my/apple-reminders--default-list)
               (lambda () "Inbox")))
      (my/apple-reminders-add "Task" "Inbox" "" nil)
      (should-not (member "--due-date" received-args)))))

(ert-deftest ar/add-uses-auto-detected-list-when-nil ()
  "Passes auto-detected list when list-name argument is nil."
  (let (received-args)
    (cl-letf (((symbol-function 'my/apple-reminders--run)
               (lambda (&rest args) (setq received-args args) ""))
              ((symbol-function 'my/apple-reminders--default-list)
               (lambda () "AutoList")))
      (my/apple-reminders-add "Task" nil nil nil)
      (should (member "AutoList" received-args)))))


;;;; ──────────────────────────────────────────────────────────────────
;;;; 4. Org state-change hook
;;;; ──────────────────────────────────────────────────────────────────

(ert-deftest ar/state-done-sends-completed-true ()
  "DONE state → JXA script sets completed=true."
  (let (sent-script)
    (cl-letf (((symbol-function 'my/apple-reminders--jxa-async)
               (lambda (script &optional _cb) (setq sent-script script))))
      (with-temp-buffer
        (org-mode)
        (insert "* DONE Task\n:PROPERTIES:\n:REMINDER_ID:   id-001\n:REMINDER_LIST: MyList\n:END:\n")
        (goto-char (point-min))
        (let ((org-state "DONE"))
          (my/apple-reminders--on-todo-state-change))))
    (should sent-script)
    (should (string-match-p "completed=true" sent-script))
    (should (string-match-p "id-001" sent-script))
    (should (string-match-p "MyList" sent-script))))

(ert-deftest ar/state-cancelled-sends-completed-true ()
  "CANCELLED state → JXA script sets completed=true."
  (let (sent-script)
    (cl-letf (((symbol-function 'my/apple-reminders--jxa-async)
               (lambda (script &optional _cb) (setq sent-script script))))
      (with-temp-buffer
        (org-mode)
        (insert "* CANCELLED Task\n:PROPERTIES:\n:REMINDER_ID:   id-002\n:REMINDER_LIST: Work\n:END:\n")
        (goto-char (point-min))
        (let ((org-state "CANCELLED"))
          (my/apple-reminders--on-todo-state-change))))
    (should (string-match-p "completed=true" sent-script))))

(ert-deftest ar/state-todo-sends-completed-false ()
  "TODO (reopen) state → JXA script sets completed=false."
  (let (sent-script)
    (cl-letf (((symbol-function 'my/apple-reminders--jxa-async)
               (lambda (script &optional _cb) (setq sent-script script))))
      (with-temp-buffer
        (org-mode)
        (insert "* TODO Task\n:PROPERTIES:\n:REMINDER_ID:   id-003\n:REMINDER_LIST: Inbox\n:END:\n")
        (goto-char (point-min))
        (let ((org-state "TODO"))
          (my/apple-reminders--on-todo-state-change))))
    (should (string-match-p "completed=false" sent-script))))

(ert-deftest ar/state-next-sends-completed-false ()
  "NEXT state → JXA script sets completed=false."
  (let (sent-script)
    (cl-letf (((symbol-function 'my/apple-reminders--jxa-async)
               (lambda (script &optional _cb) (setq sent-script script))))
      (with-temp-buffer
        (org-mode)
        (insert "* NEXT Task\n:PROPERTIES:\n:REMINDER_ID:   id-004\n:REMINDER_LIST: Inbox\n:END:\n")
        (goto-char (point-min))
        (let ((org-state "NEXT"))
          (my/apple-reminders--on-todo-state-change))))
    (should (string-match-p "completed=false" sent-script))))

(ert-deftest ar/state-change-no-id-skipped ()
  "Heading without REMINDER_ID → no JXA call at all."
  (let (sent-script)
    (cl-letf (((symbol-function 'my/apple-reminders--jxa-async)
               (lambda (script &optional _cb) (setq sent-script script))))
      (with-temp-buffer
        (org-mode)
        (insert "* DONE Plain task without properties\n")
        (goto-char (point-min))
        (let ((org-state "DONE"))
          (my/apple-reminders--on-todo-state-change))))
    (should (null sent-script))))


;;;; ──────────────────────────────────────────────────────────────────
;;;; 5. Org advice hook (priority / deadline / tags)
;;;; ──────────────────────────────────────────────────────────────────

(ert-deftest ar/maybe-push-calls-update-when-id-present ()
  "Heading with REMINDER_ID and REMINDER_LIST → update-in-apple called."
  (let (called-list called-id)
    (cl-letf (((symbol-function 'my/apple-reminders--update-in-apple)
               (lambda (list id _vals) (setq called-list list called-id id))))
      (with-temp-buffer
        (org-mode)
        (insert "* TODO Task\n:PROPERTIES:\n:REMINDER_ID:   id-push\n:REMINDER_LIST: PushList\n:END:\n")
        (goto-char (point-min))
        (let ((my/apple-reminders--syncing nil))
          (my/apple-reminders--maybe-push-heading))))
    (should (string= called-list "PushList"))
    (should (string= called-id   "id-push"))))

(ert-deftest ar/maybe-push-skipped-without-id ()
  "Heading without REMINDER_ID → update-in-apple is never called."
  (let (called)
    (cl-letf (((symbol-function 'my/apple-reminders--update-in-apple)
               (lambda (&rest _) (setq called t))))
      (with-temp-buffer
        (org-mode)
        (insert "* TODO Task with no properties\n")
        (goto-char (point-min))
        (let ((my/apple-reminders--syncing nil))
          (my/apple-reminders--maybe-push-heading))))
    (should (null called))))

(ert-deftest ar/maybe-push-suppressed-when-syncing ()
  "my/apple-reminders--syncing=t suppresses the push."
  (let (called)
    (cl-letf (((symbol-function 'my/apple-reminders--update-in-apple)
               (lambda (&rest _) (setq called t))))
      (with-temp-buffer
        (org-mode)
        (insert "* TODO Task\n:PROPERTIES:\n:REMINDER_ID:   id-x\n:REMINDER_LIST: L\n:END:\n")
        (goto-char (point-min))
        (let ((my/apple-reminders--syncing t))
          (my/apple-reminders--maybe-push-heading))))
    (should (null called))))

(ert-deftest ar/maybe-push-suppressed-outside-org ()
  "Non-org buffer → push is suppressed."
  (let (called)
    (cl-letf (((symbol-function 'my/apple-reminders--update-in-apple)
               (lambda (&rest _) (setq called t))))
      (with-temp-buffer
        ;; fundamental-mode, not org-mode
        (insert "* TODO Task\n")
        (goto-char (point-min))
        (let ((my/apple-reminders--syncing nil))
          (my/apple-reminders--maybe-push-heading))))
    (should (null called))))


;;;; ──────────────────────────────────────────────────────────────────
;;;; 6. Save hook
;;;; ──────────────────────────────────────────────────────────────────

(ert-deftest ar/on-save-triggers-push-for-sync-file ()
  "push-to-apple is called when reminders.org is saved."
  (let (push-called)
    (cl-letf (((symbol-function 'my/apple-reminders--push-to-apple)
               (lambda () (setq push-called t))))
      (with-temp-buffer
        (setq buffer-file-name (expand-file-name my/apple-reminders-sync-file))
        (let ((my/apple-reminders--syncing nil))
          (my/apple-reminders--on-save))))
    (should push-called)))

(ert-deftest ar/on-save-skipped-for-other-file ()
  "push-to-apple is NOT called when a different file is saved."
  (let (push-called)
    (cl-letf (((symbol-function 'my/apple-reminders--push-to-apple)
               (lambda () (setq push-called t))))
      (with-temp-buffer
        (setq buffer-file-name "/tmp/some-other-file.org")
        (let ((my/apple-reminders--syncing nil))
          (my/apple-reminders--on-save))))
    (should (null push-called))))

(ert-deftest ar/on-save-skipped-when-syncing ()
  "push-to-apple is NOT called when my/apple-reminders--syncing is t."
  (let (push-called)
    (cl-letf (((symbol-function 'my/apple-reminders--push-to-apple)
               (lambda () (setq push-called t))))
      (with-temp-buffer
        (setq buffer-file-name (expand-file-name my/apple-reminders-sync-file))
        (let ((my/apple-reminders--syncing t))
          (my/apple-reminders--on-save))))
    (should (null push-called))))

(ert-deftest ar/on-save-skipped-when-no-file-name ()
  "push-to-apple is NOT called when buffer has no file name."
  (let (push-called)
    (cl-letf (((symbol-function 'my/apple-reminders--push-to-apple)
               (lambda () (setq push-called t))))
      (with-temp-buffer
        ;; buffer-file-name is nil in a fresh temp buffer
        (let ((my/apple-reminders--syncing nil))
          (my/apple-reminders--on-save))))
    (should (null push-called))))


;;;; ──────────────────────────────────────────────────────────────────
;;;; 7. Dashboard helpers
;;;; ──────────────────────────────────────────────────────────────────

;;; my/apple-reminders--insert-org-heading

(ert-deftest ar/insert-org-heading-basic ()
  "Inserts a * TODO heading with REMINDER_ID and REMINDER_LIST."
  (with-temp-buffer
    (org-mode)
    (my/apple-reminders--insert-org-heading
     '((id . "h-001") (title . "Buy milk") (due . nil)
       (priority . 0) (flagged . :false) (notes . ""))
     "Shopping")
    (let ((content (buffer-string)))
      (should (string-match-p "\\* TODO Buy milk" content))
      (should (string-match-p ":REMINDER_ID:.*h-001" content))
      (should (string-match-p ":REMINDER_LIST:.*Shopping" content)))))

(ert-deftest ar/insert-org-heading-with-deadline ()
  "DEADLINE is inserted when due date is present."
  (with-temp-buffer
    (org-mode)
    (my/apple-reminders--insert-org-heading
     '((id . "h-002") (title . "Dentist") (due . "2025-07-15")
       (priority . 0) (flagged . :false) (notes . ""))
     "Health")
    (should (string-match-p "DEADLINE: <2025-07-15>" (buffer-string)))))

(ert-deftest ar/insert-org-heading-omits-deadline-when-nil ()
  "No DEADLINE line when due is nil."
  (with-temp-buffer
    (org-mode)
    (my/apple-reminders--insert-org-heading
     '((id . "h-003") (title . "Read book") (due . nil)
       (priority . 0) (flagged . :false) (notes . ""))
     "Personal")
    (should-not (string-match-p "DEADLINE" (buffer-string)))))

(ert-deftest ar/insert-org-heading-priority ()
  "High-priority item gets [#A] prefix."
  (with-temp-buffer
    (org-mode)
    (my/apple-reminders--insert-org-heading
     '((id . "h-004") (title . "Critical fix") (due . nil)
       (priority . 1) (flagged . :false) (notes . ""))
     "Work")
    (should (string-match-p "\\[#A\\]" (buffer-string)))))

(ert-deftest ar/insert-org-heading-flagged ()
  "Flagged item (flagged=t) gets ★ prefix."
  (with-temp-buffer
    (org-mode)
    (my/apple-reminders--insert-org-heading
     '((id . "h-005") (title . "VIP task") (due . nil)
       (priority . 0) (flagged . t) (notes . ""))
     "Inbox")
    (should (string-match-p "★" (buffer-string)))))

(ert-deftest ar/insert-org-heading-notes-appended ()
  "Notes are appended after the properties drawer."
  (with-temp-buffer
    (org-mode)
    (my/apple-reminders--insert-org-heading
     '((id . "h-006") (title . "Call Bob") (due . nil)
       (priority . 0) (flagged . :false) (notes . "At 3pm\nMention project X"))
     "Inbox")
    (let ((content (buffer-string)))
      (should (string-match-p "At 3pm" content))
      (should (string-match-p "Mention project X" content)))))


;;; my/apple-reminders--write-agenda-file

(ert-deftest ar/write-agenda-file-creates-todos ()
  "Writes one * TODO heading per open reminder."
  (let* ((tmpfile (make-temp-file "ar-test-agenda" nil ".org"))
         (my/apple-reminders-agenda-file tmpfile)
         (org-agenda-files nil)           ; prevent leaking into global state
         (test-data '(((list . "Work")
                       (items . (((id . "1") (title . "Send report")
                                  (due . "2025-12-31") (priority . 1)
                                  (flagged . t) (notes . ""))
                                 ((id . "2") (title . "Review PR")
                                  (due . nil) (priority . 0)
                                  (flagged . :false) (notes . ""))))))))
    (unwind-protect
        (progn
          (my/apple-reminders--write-agenda-file test-data)
          (with-temp-buffer
            (insert-file-contents tmpfile)
            (let ((content (buffer-string)))
              (should (string-match-p "\\* TODO.*Send report" content))
              (should (string-match-p "\\* TODO.*Review PR" content))
              (should (string-match-p "DEADLINE: <2025-12-31>" content))
              (should (string-match-p "\\[#A\\]" content))
              (should (string-match-p "★" content)))))
      (delete-file tmpfile))))

(ert-deftest ar/write-agenda-file-registers-in-agenda ()
  "The written file is added to org-agenda-files."
  (let* ((tmpfile (make-temp-file "ar-test-agenda" nil ".org"))
         (my/apple-reminders-agenda-file tmpfile)
         (org-agenda-files nil))
    (unwind-protect
        (progn
          (my/apple-reminders--write-agenda-file
           '(((list . "Inbox") (items . ()))))
          (should (member tmpfile org-agenda-files)))
      (delete-file tmpfile))))

(ert-deftest ar/write-agenda-file-skipped-when-nil ()
  "Nothing is written when my/apple-reminders-agenda-file is nil."
  (let ((my/apple-reminders-agenda-file nil))
    ;; Should not signal an error
    (should-not (condition-case err
                    (progn
                      (my/apple-reminders--write-agenda-file '())
                      nil)
                  (error err)))))


;;;; ──────────────────────────────────────────────────────────────────
;;;; 8. create-in-apple JXA script
;;;; ──────────────────────────────────────────────────────────────────

(ert-deftest ar/create-in-apple-uses-before-after-id-diff ()
  "JXA script captures IDs before and after push instead of using whose().
whose() has timing bugs that cause duplicates — this is the guard."
  (let (sent-script)
    (cl-letf (((symbol-function 'my/apple-reminders--jxa-run)
               (lambda (script) (setq sent-script script) "null")))
      (my/apple-reminders--create-in-apple
       "Inbox" '((title . "Test") (notes . "") (priority . 0)
                 (due . nil) (flagged . nil))))
    (should (string-match-p "prev=list\\.reminders\\.id()" sent-script))
    (should (string-match-p "next=list\\.reminders\\.id()" sent-script))
    (should-not (string-match-p "whose" sent-script))))

(ert-deftest ar/create-in-apple-returns-nil-on-jxa-error ()
  "Returns nil gracefully when JXA fails — does not signal an error."
  (cl-letf (((symbol-function 'my/apple-reminders--jxa-run)
             (lambda (_) (error "osascript error"))))
    (should (null (my/apple-reminders--create-in-apple
                   "Inbox" '((title . "X") (notes . "") (priority . 0)
                              (due . nil) (flagged . nil)))))))

(ert-deftest ar/create-in-apple-includes-due-date-when-set ()
  "JXA script includes dueDate when due is non-nil."
  (let (sent-script)
    (cl-letf (((symbol-function 'my/apple-reminders--jxa-run)
               (lambda (script) (setq sent-script script) "null")))
      (my/apple-reminders--create-in-apple
       "Inbox" '((title . "Task") (notes . "") (priority . 0)
                 (due . "2025-12-31") (flagged . nil))))
    (should (string-match-p "dueDate" sent-script))
    (should (string-match-p "2025-12-31" sent-script))))

(ert-deftest ar/create-in-apple-omits-due-date-when-nil ()
  "JXA script has no dueDate when due is nil."
  (let (sent-script)
    (cl-letf (((symbol-function 'my/apple-reminders--jxa-run)
               (lambda (script) (setq sent-script script) "null")))
      (my/apple-reminders--create-in-apple
       "Inbox" '((title . "Task") (notes . "") (priority . 0)
                 (due . nil) (flagged . nil))))
    (should-not (string-match-p "dueDate" sent-script))))


;;;; ──────────────────────────────────────────────────────────────────
;;;; 9. Push-to-Apple sync scenarios
;;;; ──────────────────────────────────────────────────────────────────

(ert-deftest ar/push-creates-new-item-and-stamps-id ()
  "New TODO item (no REMINDER_ID) → create-in-apple called, ID stamped back."
  (let (created-list created-title stamped-id)
    (cl-letf (((symbol-function 'my/apple-reminders--default-list)
               (lambda () "AutoList"))
              ((symbol-function 'my/apple-reminders--create-in-apple)
               (lambda (list vals)
                 (setq created-list list
                       created-title (alist-get 'title vals))
                 "new-id-999"))
              ((symbol-function 'my/apple-reminders--update-in-apple)
               (lambda (&rest _) nil))
              ((symbol-function 'my/apple-reminders--complete-in-apple)
               (lambda (&rest _) nil)))
      (with-temp-buffer
        (org-mode)
        (insert "* TODO Brand new task\n")
        (let ((my/apple-reminders-sync-list nil))
          (my/apple-reminders--push-to-apple))
        (setq stamped-id (org-entry-get (point-min) "REMINDER_ID"))))
    (should (string= created-list "AutoList"))
    (should (string= created-title "Brand new task"))
    (should (string= stamped-id "new-id-999"))))

(ert-deftest ar/push-completes-done-items ()
  "DONE item with REMINDER_ID → complete-in-apple is called."
  (let (completed-id)
    (cl-letf (((symbol-function 'my/apple-reminders--complete-in-apple)
               (lambda (_list id) (setq completed-id id)))
              ((symbol-function 'my/apple-reminders--create-in-apple)
               (lambda (&rest _) nil))
              ((symbol-function 'my/apple-reminders--update-in-apple)
               (lambda (&rest _) nil)))
      (with-temp-buffer
        (org-mode)
        (insert "* DONE Finished task\n:PROPERTIES:\n:REMINDER_ID:   done-id\n:REMINDER_LIST: MyList\n:END:\n")
        (let ((my/apple-reminders-sync-list "MyList"))
          (my/apple-reminders--push-to-apple))))
    (should (string= completed-id "done-id"))))

(ert-deftest ar/push-updates-existing-open-items ()
  "Existing open item (TODO + REMINDER_ID) → update-in-apple is called."
  (let (updated-id)
    (cl-letf (((symbol-function 'my/apple-reminders--update-in-apple)
               (lambda (_list id _vals) (setq updated-id id)))
              ((symbol-function 'my/apple-reminders--create-in-apple)
               (lambda (&rest _) nil))
              ((symbol-function 'my/apple-reminders--complete-in-apple)
               (lambda (&rest _) nil)))
      (with-temp-buffer
        (org-mode)
        (insert "* TODO Existing task\n:PROPERTIES:\n:REMINDER_ID:   exist-id\n:REMINDER_LIST: MyList\n:END:\n")
        (let ((my/apple-reminders-sync-list "MyList"))
          (my/apple-reminders--push-to-apple))))
    (should (string= updated-id "exist-id"))))

(ert-deftest ar/push-skips-headings-without-todo-state ()
  "Non-TODO headings (no state keyword) are ignored entirely."
  (let (created-count)
    (setq created-count 0)
    (cl-letf (((symbol-function 'my/apple-reminders--default-list)
               (lambda () "Inbox"))
              ((symbol-function 'my/apple-reminders--create-in-apple)
               (lambda (&rest _) (setq created-count (1+ created-count)) nil))
              ((symbol-function 'my/apple-reminders--update-in-apple)
               (lambda (&rest _) nil))
              ((symbol-function 'my/apple-reminders--complete-in-apple)
               (lambda (&rest _) nil)))
      (with-temp-buffer
        (org-mode)
        (insert "* Plain heading without TODO keyword\n")
        (let ((my/apple-reminders-sync-list nil))
          (my/apple-reminders--push-to-apple))))
    (should (= created-count 0))))

(ert-deftest ar/push-uses-auto-detected-list-when-sync-list-nil ()
  "When my/apple-reminders-sync-list is nil, auto-detect is used."
  (let (used-list)
    (cl-letf (((symbol-function 'my/apple-reminders--default-list)
               (lambda () "DetectedList"))
              ((symbol-function 'my/apple-reminders--create-in-apple)
               (lambda (list _vals) (setq used-list list) "id"))
              ((symbol-function 'my/apple-reminders--update-in-apple)
               (lambda (&rest _) nil))
              ((symbol-function 'my/apple-reminders--complete-in-apple)
               (lambda (&rest _) nil)))
      (with-temp-buffer
        (org-mode)
        (insert "* TODO New item\n")
        (let ((my/apple-reminders-sync-list nil))
          (my/apple-reminders--push-to-apple))))
    (should (string= used-list "DetectedList"))))


;;;; ──────────────────────────────────────────────────────────────────
;;;; 10. Agenda file registration
;;;; ──────────────────────────────────────────────────────────────────

(ert-deftest ar/ensure-agenda-adds-existing-sync-file ()
  "Existing reminders.org is added to org-agenda-files."
  (let* ((tmpfile (make-temp-file "reminders" nil ".org"))
         (my/apple-reminders-sync-file tmpfile)
         (my/apple-reminders-agenda-file nil)
         (org-agenda-files nil))
    (unwind-protect
        (progn
          (my/apple-reminders--ensure-agenda-files)
          (should (member tmpfile org-agenda-files)))
      (delete-file tmpfile))))

(ert-deftest ar/ensure-agenda-skips-missing-sync-file ()
  "Missing reminders.org is NOT added to org-agenda-files."
  (let* ((my/apple-reminders-sync-file "/tmp/nonexistent-reminders-99999.org")
         (my/apple-reminders-agenda-file nil)
         (org-agenda-files nil))
    (my/apple-reminders--ensure-agenda-files)
    (should (null org-agenda-files))))

(ert-deftest ar/ensure-agenda-creates-stub-for-missing-sync-file ()
  "Missing reminders.org is created as a stub when parent dir exists."
  (let* ((tmpdir (make-temp-file "ar-sync-dir" t))
         (stub-path (expand-file-name "reminders.org" tmpdir))
         (my/apple-reminders-sync-file stub-path)
         (my/apple-reminders-agenda-file nil)
         (org-agenda-files nil)
         (org-agenda-custom-commands nil))
    (unwind-protect
        (progn
          (my/apple-reminders--ensure-agenda-files)
          (should (file-exists-p stub-path)))
      (when (file-exists-p stub-path) (delete-file stub-path))
      (delete-directory tmpdir))))

(ert-deftest ar/ensure-agenda-adds-custom-command ()
  "\"A\" custom agenda command is added to org-agenda-custom-commands."
  (let* ((tmpfile (make-temp-file "reminders" nil ".org"))
         (my/apple-reminders-sync-file tmpfile)
         (my/apple-reminders-agenda-file nil)
         (org-agenda-files nil)
         (org-agenda-custom-commands nil))
    (unwind-protect
        (progn
          (my/apple-reminders--ensure-agenda-files)
          (should (assoc "A" org-agenda-custom-commands)))
      (delete-file tmpfile))))


(provide 'apple-reminders-tests)
;;; apple-reminders-tests.el ends here

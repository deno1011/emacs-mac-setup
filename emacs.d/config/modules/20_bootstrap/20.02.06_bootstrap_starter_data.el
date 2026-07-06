;;; 20.02.06_bootstrap_starter_data.el --- Bootstrap Layer 2 starter data -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer 3):
;;   (my/starter-data-ensure)              → :done / :skip / (:error MSG)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/starter-data--source-root
;;   my/starter-data--ear-source-root
;;   my/starter-data--files
;;   my/starter-data--ear-files
;;   my/starter-data--source
;;   my/starter-data--ear-source
;;   my/starter-data--target
;;   my/starter-data--ear-target
;;   my/starter-data--copy-missing
;;   my/starter-data--copy-ear-missing
;;
;; Depends on:
;;   none
;;
;; Forward-declared variables (owned by Layer 3):
;;   my/data-dir                           ← 20.03.01_bootstrap

(defvar my/data-dir)

(defconst my/starter-data--source-root
  (expand-file-name
   "../../starter-data/org/"
   (file-name-directory (or load-file-name buffer-file-name default-directory)))
  "Directory containing distro starter Org templates.")

(defconst my/starter-data--ear-source-root
  (expand-file-name
   "../../starter-data/ear/"
   (file-name-directory (or load-file-name buffer-file-name default-directory)))
  "Directory containing distro starter EAR overlay templates.")

(defconst my/starter-data--files
  '("inbox.org"
    "gtd.org"
    "calendar.org"
    "archive.org"
    "gtd/projects.org"
    "gtd/next.org"
    "gtd/waiting.org"
    "gtd/someday.org"
    "gtd/tickler.org"
    "gtd/reference.org"
    "gtd/sources.org"
    "gtd/daily-coach.org"
    "gtd/scheduling-policy.org"
    "gtd/inbox-clarifier.org"
    "gtd/weekly-review-coach.org"
    "gtd/horizon-coach.org"
    "gtd/initial-setup-coach.org"
    "gtd/life-coach.org"
    "gtd/life-agent-roles.org"
    "gtd/calendar-coach.org"
    "gtd/apple-reminders-setup.org"
    "gtd/apple-calendar-setup.org")
  "Starter Org files copied into data/org/ when missing.")

(defconst my/starter-data--ear-files
  '("jobs/agent-learning-dreaming.eld")
  "Starter EAR overlay files copied into ear/ when missing.")

(defun my/starter-data--source (file)
  "Return the distro template path for FILE."
  (expand-file-name file my/starter-data--source-root))

(defun my/starter-data--ear-source (file)
  "Return the distro EAR template path for FILE."
  (expand-file-name file my/starter-data--ear-source-root))

(defun my/starter-data--target (file)
  "Return the user data path for FILE."
  (expand-file-name (concat "data/org/" file) my/data-dir))

(defun my/starter-data--ear-target (file)
  "Return the user EAR overlay path for FILE."
  (expand-file-name (concat "ear/" file) my/data-dir))

(defun my/starter-data--copy-missing (file)
  "Copy starter FILE into user data when missing."
  (let ((source (my/starter-data--source file))
        (target (my/starter-data--target file)))
    (cond
     ((file-exists-p target)
      :skip)
     ((not (file-exists-p source))
      `(:error ,(format "Starter template is missing from the distro: %s

FIX: reinstall or update the configuration to restore the
config/starter-data/org/ templates, then run M-x my/bootstrap."
                         source)))
     (t
      (make-directory (file-name-directory target) t)
      (copy-file source target nil)
      :done))))

(defun my/starter-data--copy-ear-missing (file)
  "Copy starter EAR FILE into user data when missing."
  (let ((source (my/starter-data--ear-source file))
        (target (my/starter-data--ear-target file)))
    (cond
     ((file-exists-p target)
      :skip)
     ((not (file-exists-p source))
      `(:error ,(format "Starter EAR template is missing from the distro: %s

FIX: reinstall or update the configuration to restore the
config/starter-data/ear/ templates, then run M-x my/bootstrap."
                         source)))
     (t
      (make-directory (file-name-directory target) t)
      (copy-file source target nil)
      :done))))

(defun my/starter-data-ensure ()
  "Ensure compact starter Org files exist in `my/data-dir'."
  (cond
   ((not (stringp my/data-dir))
    `(:error ,(format "my/data-dir is not a string (%S). \
This step requires my/data-dir-resolve to have succeeded first."
                      my/data-dir)))
   ((not (file-directory-p my/data-dir))
    `(:error ,(format "Data directory does not exist: %s

FIX: run M-x my/bootstrap again after the data-folder clone step succeeds."
                      my/data-dir)))
   (t
    (let ((created nil)
          (error-result nil))
      (dolist (file my/starter-data--files)
        (let ((result (my/starter-data--copy-missing file)))
          (cond
           ((eq result :done)
            (push file created))
           ((and (consp result) (eq (car result) :error))
            (setq error-result result)))))
      (dolist (file my/starter-data--ear-files)
        (let ((result (my/starter-data--copy-ear-missing file)))
          (cond
           ((eq result :done)
            (push (concat "ear/" file) created))
           ((and (consp result) (eq (car result) :error))
            (setq error-result result)))))
      (cond
       (error-result error-result)
       (created :done)
       (t :skip))))))

(provide 'my-bootstrap-starter-data)
;;; 20.02.06_bootstrap_starter_data.el ends here

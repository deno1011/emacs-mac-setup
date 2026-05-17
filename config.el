;; apple-reminders.org deactivated — replaced by org-apple-reminders package
;; org-reminders-setup.org deactivated — ginqi7/org-reminders too buggy
(defvar my/config-split-files '("core.org" "org-setup.org" "gptel-setup.org"))
(when (eq system-type 'darwin)
  (add-to-list 'my/config-split-files "org-apple-reminders-setup.org" t))

(defvar my/config-fallback-base-url
  "https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/"
  "Base URL for fetching missing config files on first install.")

(defun my/ensure-config-file (filename)
  (let ((path (expand-file-name filename my/config-dir)))
    (unless (file-exists-p path)
      (message "Config: fetching missing %s from emacs-mac-setup..." filename)
      (condition-case err
          (progn (require 'url)
                 (url-copy-file (concat my/config-fallback-base-url filename) path t))
        (error (message "Config: could not fetch %s: %s" filename err))))
    path))

(dolist (f my/config-split-files)
  (let ((path (my/ensure-config-file f)))
    (when (file-exists-p path)
      (condition-case err
          (org-babel-load-file path)
        (error (message "CONFIG LOAD ERROR (%s): %s" f err))))))

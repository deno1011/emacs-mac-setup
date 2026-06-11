;;; 80-gtd.el --- GTD overlay loader -*- lexical-binding: t; -*-

(defvar my/data-dir)

(let ((gtd-config (expand-file-name "data/org/gtd-config.el" my/data-dir)))
  (when (file-exists-p gtd-config)
    (condition-case err
        (load gtd-config nil nil t)
      (error (message "GTD CONFIG LOAD ERROR: %s" err)))))

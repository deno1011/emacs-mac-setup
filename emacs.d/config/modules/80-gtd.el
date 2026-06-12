;;; 80-gtd.el --- GTD overlay loader -*- lexical-binding: t; -*-

(defvar my/data-dir)
(declare-function my/bootstrap-ready-p "20.03.01_bootstrap")

(when (my/bootstrap-ready-p)
  (let ((gtd-config (expand-file-name "data/org/gtd-config.el" my/data-dir)))
    (when (file-exists-p gtd-config)
      (condition-case err
          (load gtd-config nil nil t)
        (error (message "GTD CONFIG LOAD ERROR: %s" err))))))

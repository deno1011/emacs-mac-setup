;;; 00_startfirst.el --- Earliest module: theme + frame setup -*- lexical-binding: t; -*-

;; Built-in dark theme — no install required.
(load-theme 'modus-vivendi t)

;; Do not unload `compat' during startup.  Packages such as Vertico may
;; already have compiled calls to compatibility functions that Emacs 30 does
;; not provide itself.  Removing the feature while those packages stay loaded
;; leaves commands such as `M-x' with void compatibility functions.

;;; 00-fullscreen.el --- Fullscreen graphical frames early -*- lexical-binding: t; -*-

(defun my/fullscreen-frame (frame)
  "Put graphical FRAME into fullscreen."
  (when (and (frame-live-p frame)
             (display-graphic-p frame))
    (with-selected-frame frame
      (unless (memq (frame-parameter frame 'fullscreen)
                    '(fullscreen fullboth))
        (set-frame-parameter frame 'fullscreen 'fullboth)))))

(add-hook 'after-make-frame-functions #'my/fullscreen-frame)

(when (display-graphic-p)
  (my/fullscreen-frame (selected-frame)))

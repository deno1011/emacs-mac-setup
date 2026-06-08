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

;;; early-init.el --- GC tuning, runs before package.el / init.el  -*- lexical-binding: t; -*-
;;
;; Emacs 27+ loads this file FIRST, before package.el and before init.el.
;; The only reason this file exists is to give the garbage collector room
;; to breathe during startup — without it, the default 800 KB threshold
;; causes a GC at almost every command, and a long-running session
;; eventually beach-balls on a fragmented heap.
;;
;; Runtime tuning + idle-GC continues in core.org once init has settled.
;; Search "Garbage collection (linked to ~/.emacs.d/early-init.el)" there
;; for the runtime half and the rationale for the split.

(setq gc-cons-threshold  (* 256 1024 1024)   ; 256 MB during init
      gc-cons-percentage 0.6)

;; Don't let package.el initialize itself before init.el runs — init.el
;; does it explicitly. Skipping the implicit early init saves a few
;; hundred ms on startup.
(setq package-enable-at-startup nil)

;;; early-init.el ends here

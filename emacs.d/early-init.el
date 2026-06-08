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

;; Stable used to hide byte/native compiler warnings at startup via
;; `warning-minimum-level'. Keep real runtime warnings visible, but stop async
;; native compilation from opening a scary warning buffer for harmless package
;; byte-compiler notes during first-start package builds.
(setq native-comp-async-report-warnings-errors nil)

;; Don't let package.el initialize itself before init.el runs — init.el
;; does it explicitly. Skipping the implicit early init saves a few
;; hundred ms on startup.
(setq package-enable-at-startup nil)

;; Kill the WHITE FLASH at startup. early-init.el runs before the first
;; frame is painted, so setting `default-frame-alist' here means the
;; initial frame already has dark colors instead of the default white.
;; Values are tuned to match `modus-vivendi' (built-in dark theme,
;; loaded in 00-startfirst.org) closely enough that there's no visible
;; transition when the theme later applies. Once cyberpunk-theme
;; finishes building (via elpaca in 20-core.org), it overrides these.
(setq default-frame-alist
      (append '((background-color . "#000000")
                (foreground-color . "#ffffff")
                (ns-appearance . dark)
                (ns-transparent-titlebar . t))
              default-frame-alist))
;; Same for the initial GUI frame (existing frame at the time of
;; `package-enable-at-startup'; default-frame-alist only affects future
;; frames). Without this the first frame still flashes white before
;; the theme applies.
(set-face-attribute 'default nil :background "#000000" :foreground "#ffffff")
;; Suppress the default Emacs splash + scratch message contrast.
(setq inhibit-startup-screen t)

;;; early-init.el ends here

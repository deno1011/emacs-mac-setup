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

;; ENV SNAPSHOT — `doom env'-style protection against LaunchAgent /
;; brew services losing the user's shell environment.
;;
;; install.sh writes ~/.emacs.d/env-snapshot.el on every install. It
;; captures PATH, LIBRARY_PATH, MANPATH, INFOPATH from the install
;; shell (which has brew shellenv sourced + the user's profile read).
;; This file restores those vars into the running Emacs process BEFORE
;; any package, any module, any native-comp invocation can need them.
;;
;; Without this, a fresh daemon launched by emacs-plus@30's
;; LaunchAgent on login sees only the macOS LaunchAgent default env
;; — no /opt/homebrew/bin, no LIBRARY_PATH, no nothing from ~/.zshrc.
;; The hardcoded block below this one still provides a minimum LIBRARY_PATH
;; floor for the libgccjit / gcc-driver case even when the snapshot is
;; missing.
(let ((snapshot (expand-file-name "env-snapshot.el" user-emacs-directory)))
  (when (file-readable-p snapshot)
    (load snapshot nil 'nomessage 'nosuffix)))

;; native-comp needs the brew gcc + libgccjit on LIBRARY_PATH at runtime
;; so libgccjit can locate gcc's internal helpers (crt0.o, libgcc.a, ...).
;; A daemonized Emacs launched via LaunchAgent or `brew services start'
;; does NOT inherit a shell's PATH/LIBRARY_PATH, and emacs-plus@30 does
;; not bake the paths into the binary. Without this block, every
;; .eln compile under ~/.emacs.d/eln-cache/ triggers
;;   ⛔ Warning (native-compiler): libgccjit.so: error: error invoking gcc driver
;; and the affected lisp file silently falls back to interpreted lisp.
;;
;; Apple Silicon brew prefix is /opt/homebrew; Intel Mac would be
;; /usr/local. Hardcoded here to keep early-init fast (no `brew --prefix'
;; subprocess on every Emacs start).
(when (eq system-type 'darwin)
  (let ((extra-lib-paths
         (mapconcat #'identity
                    '("/opt/homebrew/opt/gcc/lib/gcc/current"
                      "/opt/homebrew/opt/libgccjit/lib/gcc/current")
                    ":")))
    (setenv "LIBRARY_PATH"
            (if (getenv "LIBRARY_PATH")
                (concat extra-lib-paths ":" (getenv "LIBRARY_PATH"))
              extra-lib-paths))))

;; UTF-8 EVERYWHERE, set at the earliest possible moment. macOS's
;; LANG can default to a non-UTF-8 codepage in some scenarios
;; (LaunchAgents, brew services without a login shell, etc.), and the
;; per-buffer coding system is decided AT FILE OPEN, not retroactively.
;; If any of `org-clock-save.el', `recentf', or a desktop-restore
;; reopens an Org file BEFORE 20-bootstrap.el's own UTF-8 defaults
;; run, the buffer ends up in raw-text or undecided-unix — UTF-8 bytes
;; like 0xC3 0xBC (`ü') then display as octal escapes (`\303\274')
;; until you `revert-buffer-with-coding-system'.
;;
;; Setting `prefer-coding-system' + the two `default-*' coding system
;; variables HERE — before `init.el', before any module, before any
;; restore hook fires — guarantees every later file read picks UTF-8.
(prefer-coding-system 'utf-8-unix)
(setq default-buffer-file-coding-system 'utf-8-unix
      default-process-coding-system '(utf-8-unix . utf-8-unix))
(set-language-environment "UTF-8")

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

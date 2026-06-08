;;; core.el --- Core Emacs configuration -*- lexical-binding: t; -*-

(require 'org)

(defvar my/config-dir)
(defvar my/data-dir)
(defvar pixel-scroll-precision-use-momentum)
(defvar org-show-following-heading)
(defvar org-show-hierarchy-above)
(defvar org-show-siblings)
(defvar org-link-mailto-program)
(defvar org-duration-format)

(declare-function benchmark-init/deactivate "benchmark-init")
(declare-function pixel-scroll-precision "pixel-scroll")

(defun my/data-dir-repo-name ()
  "Return the basename of `my/data-dir' for display."
  (if (and (boundp 'my/data-dir) (stringp my/data-dir))
      (file-name-nondirectory (directory-file-name my/data-dir))
    "?"))

(defun my/data-dir-mode-line ()
  "Return the current private repo indicator for the mode line."
  (propertize
   (format " Repo:%s" (my/data-dir-repo-name))
   'help-echo
   (lambda (_window _object _pos)
     (if (and (boundp 'my/data-dir) (stringp my/data-dir))
         my/data-dir
       "my/data-dir is not bound"))))

(defun my/show-data-dir ()
  "Show the private data/config directory Emacs is currently bound to."
  (interactive)
  (message "Emacs private repo: %s"
           (if (and (boundp 'my/data-dir) (stringp my/data-dir))
               my/data-dir
             "not bound")))

(unless (member '(:eval (my/data-dir-mode-line)) global-mode-string)
  (setq global-mode-string
        (append (or global-mode-string '(""))
                '((:eval (my/data-dir-mode-line))))))

(use-package benchmark-init
  :ensure t
  :demand t
  :config
  (benchmark-init/activate)
  ;; Stop measuring once init is done (after-init-hook fires once the
  ;; literate config and all use-package :demand t loads have run).
  (add-hook 'after-init-hook #'benchmark-init/deactivate))

;; Print the init-time + GC count at the very end of startup so a
;; before/after comparison across changes is a single grep.
(add-hook 'emacs-startup-hook
          (lambda ()
            (message "==> Emacs startup: init-time=%s, GCs=%d"
                     (emacs-init-time) gcs-done)))

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold  (* 32 1024 1024)  ; 32 MB at runtime
                  gc-cons-percentage 0.1)
            (run-with-idle-timer 60 t #'garbage-collect)))

;;; -*- lexical-binding: t -*-
(message "Loading config... (first start may take a few minutes while packages install)")

;; GUI Emacs does not always inherit the shell PATH on a fresh macOS install.
;; Keep both common Homebrew prefixes visible without assuming CPU architecture:
;; Apple Silicon usually uses /opt/homebrew, Intel usually uses /usr/local.
;; On Linux/Windows this loop is a harmless no-op (the directories don't exist).
(dolist (dir '("/opt/homebrew/bin" "/usr/local/bin"))
  (when (file-directory-p dir)
    (add-to-list 'exec-path dir)
    (let ((path (or (getenv "PATH") "")))
      (unless (string-match-p
               (regexp-quote (concat dir path-separator))
               (concat path path-separator))
        (setenv "PATH" (concat dir path-separator path))))))

;; Install a brew package in the background and log it for clean uninstall.
;; macOS-only.  See the section above for how to extend this with Linux
;; / Windows branches — every call site routes through this function.
;; TYPE is "formula" or "cask", PACKAGE is the brew package name, BREW-ARGS are
;; the full brew arguments (e.g. "install" "--cask" "font-jetbrains-mono").
(defun my/brew-install-and-log (type package &rest brew-args)
  (if-let ((brew (executable-find "brew")))
      (let* ((log-file (expand-file-name "system-packages.log" user-emacs-directory))
             (entry    (format "%s:%s\n" type package))
             (proc     (apply #'start-process
                              (format "install-%s" package)
                              (format "*install-%s*" package)
                              brew brew-args)))
        (set-process-sentinel
         proc
         (lambda (p _e)
           (when (= (process-exit-status p) 0)
             (unless (and (file-exists-p log-file)
                          (with-temp-buffer
                            (insert-file-contents log-file)
                            (search-forward entry nil t)))
               (append-to-file entry nil log-file))))))
    ;; ADD-OTHER-OS HERE: branch on system-type + apt / dnf / pacman /
    ;; winget instead of silently giving up.  See the documentation
    ;; block at the top of this section for the recommended shape.
    (message "brew not found — cannot auto-install %s on this OS (see core.org `System Package Auto-Install')" package)))

;; Install a pip package in the background and log it for clean uninstall.
;; Cross-platform: pip3 is universal.  No OS-specific extension needed.
(defun my/pip-install-and-log (package)
  (if-let ((pip3 (executable-find "pip3")))
      (let* ((log-file (expand-file-name "system-packages.log" user-emacs-directory))
             (entry    (format "pip:%s\n" package))
             (proc     (start-process (format "install-%s" package)
                                      (format "*install-%s*" package)
                                      pip3 "install" "--break-system-packages" package)))
        (set-process-sentinel
         proc
         (lambda (p _e)
           (when (= (process-exit-status p) 0)
             (unless (and (file-exists-p log-file)
                          (with-temp-buffer
                            (insert-file-contents log-file)
                            (search-forward entry nil t)))
               (append-to-file entry nil log-file))))))
    (message "pip3 not found — cannot auto-install Python package %s" package)))

(use-package exec-path-from-shell
  :if (eq system-type 'darwin)
  :config
  (exec-path-from-shell-initialize))

(add-to-list 'default-frame-alist
             `(inhibit-double-buffering . ,(eq system-type 'gnu/linux)))
(tool-bar-mode -1)
(scroll-bar-mode -1)
(menu-bar-mode -1)
(setq inhibit-startup-screen t)
(setq-default line-spacing 3)
(add-to-list 'default-frame-alist '(internal-border-width . 12))
(defalias 'yes-or-no-p 'y-or-n-p)
(show-paren-mode 1)
(delete-selection-mode 1)
(column-number-mode 1)
(global-auto-revert-mode t)
(setq save-abbrevs 'silently)

(unless (find-font (font-spec :name "JetBrains Mono"))
  (when (executable-find "brew")
    (my/brew-install-and-log "cask" "font-jetbrains-mono"
                             "install" "--cask" "font-jetbrains-mono")
    (message "JetBrains Mono: installing in background — restart Emacs when done.")))

(when (find-font (font-spec :name "JetBrains Mono"))
  (set-face-attribute 'default nil :font "JetBrains Mono-13")
  (add-to-list 'default-frame-alist '(font . "JetBrains Mono-13")))

(use-package cyberpunk-theme
  :demand t
  :config
  ;; Disable any theme an earlier init step may have loaded — same fix as
  ;; the doom block above. Without this, stacking cyberpunk on top of
  ;; another loaded theme can hang Emacs while resolving face inheritance.
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme 'cyberpunk t))

(use-package doom-modeline
  :hook (after-init . doom-modeline-mode)
  :custom
  (doom-modeline-height 28)
  (doom-modeline-icon nil))

(use-package nyan-mode
  :ensure t
  :config
  ;; Rainbow trail
  (setq nyan-wavy-trail t)
  ;; Length of progress bar
  (setq nyan-bar-length 16)
  ;; Optional animation speed tweaks
  ;; (setq nyan-animation-frame-interval 0.2)
  ;; Activate globally
  (nyan-mode 1))

;; Enable globally for text-derived modes (org, markdown, text, ...).
(add-hook 'text-mode-hook #'visual-line-mode)
;; Org explicitly, in case org-mode is not yet derived from text-mode at load time.
(add-hook 'org-mode-hook  #'visual-line-mode)
;; Soft-wrap indicator in the fringe is distracting; rely on visual-line-mode alone.
(setq visual-line-fringe-indicators '(nil nil))

(setq scroll-conservatively 101
      scroll-margin 3
      maximum-scroll-margin 0.25
      scroll-preserve-screen-position t
      auto-window-vscroll nil)

(setq mouse-wheel-scroll-amount '(1 ((shift) . 5) ((control) . nil))
      mouse-wheel-progressive-speed nil)

;; pixel-scroll-precision-mode (Emacs 29+) for sub-line pixel scrolling.
;; Yamamoto has this built in — enabling it on top causes scroll conflicts,
;; so only activate on emacs-plus (detected by absence of mac-mouse-wheel-smooth-scroll).
(defun my/pixel-scroll-precision-no-boundary-bounce (orig event)
  "Call ORIG for EVENT, ignoring scroll boundary bounce signals."
  (condition-case nil
      (funcall orig event)
    (beginning-of-buffer nil)
    (end-of-buffer nil)))

(when (and (fboundp 'pixel-scroll-precision-mode)
           (not (boundp 'mac-mouse-wheel-smooth-scroll)))
  (pixel-scroll-precision-mode 1)
  (setq pixel-scroll-precision-use-momentum nil)
  ;; macOS sends trackpad momentum events past buffer edges causing a bounce.
  ;; Wrap the top-level handler to absorb boundary signals silently.
  (with-eval-after-load 'pixel-scroll
    (advice-add 'pixel-scroll-precision
                :around #'my/pixel-scroll-precision-no-boundary-bounce)))

(use-package magit
  :bind ("C-x g" . magit-status))

;; Runtime loader files live in user-emacs-directory, while config lives
;; under the selected private repo. gptel may freely touch the user's data
;; under my/data-dir but must never overwrite config, init.el, or
;; early-init.el.
(defvar my/gptel-protected-files
  (append
   (list (expand-file-name "init.el"        user-emacs-directory)
         (expand-file-name "early-init.el"  user-emacs-directory)
         (expand-file-name "secrets.el"     user-emacs-directory))
   (when (file-directory-p my/config-dir)
     (directory-files my/config-dir t "\\.org\\'")))
  "Files that gptel write tools may never overwrite.")

(defun my/gptel-protected-p (path)
  "Return t if PATH is a protected config file."
  (member (file-truename path)
          (mapcar #'file-truename my/gptel-protected-files)))

(defun my/config-org-write-guard ()
  "Abort any save that would overwrite a protected config file."
  (when (and buffer-file-name
             (my/gptel-protected-p (file-truename buffer-file-name)))
    (error "Save blocked: %s is a protected config file (buffer: %s)"
           buffer-file-name (buffer-name))))

(add-hook 'before-save-hook #'my/config-org-write-guard)

;; Block write-file targeting protected paths
(define-advice write-file (:before (filename &rest _) gptel-protect)
  (when (and filename
             (my/gptel-protected-p (expand-file-name filename)))
    (error "write-file blocked: %s is a protected config file" filename)))

;; Block linking any buffer to a protected file path
(define-advice set-visited-file-name (:before (filename &rest _) gptel-protect)
  (when (and filename
             (not (string-empty-p filename))
             (my/gptel-protected-p (expand-file-name filename)))
    (error "set-visited-file-name blocked: %s is a protected config file" filename)))

(use-package git-auto-commit-mode
  :config
  (setq gac-automatically-push-p nil
        gac-automatically-add-new-files-p t))

(add-hook 'org-mode-hook
          (lambda ()
            ;; Auto-commit any org buffer that lives anywhere under
            ;; my/data-dir (data/org/, wiki/, notes/, TOUR.org, ...).
            ;; Config files are protected separately by the write guard;
            ;; this hook only enables auto-commit for user data files.
            ;; `file-truename' on both sides handles the case where
            ;; my/data-dir is a symlink (e.g. to iCloud Drive).
            (when (and buffer-file-name
                       my/data-dir
                       (string-prefix-p
                        (file-name-as-directory (file-truename my/data-dir))
                        (file-truename buffer-file-name)))
              (git-auto-commit-mode 1))))

(defun my/beorg-sync ()
  "Mirror my/data-dir/data/org/ to beorg's iCloud folder."
  (let ((org-d (file-name-as-directory
                (expand-file-name "data/org" my/data-dir)))
        (beorg (expand-file-name
                "Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org"
                (getenv "HOME"))))
    (when (and (file-directory-p org-d)
               (file-directory-p beorg))
      (start-process "beorg-sync" " *beorg-sync*"
                     "rsync" "-a" "--delete"
                     org-d (file-name-as-directory beorg)))))

(add-hook 'after-init-hook #'my/beorg-sync)

(use-package which-key
  :ensure t
  :config (which-key-mode))

(use-package rainbow-delimiters
  :ensure t
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package ace-window
  :ensure t
  :bind ([remap other-window] . ace-window))

(use-package neotree
  :ensure t
  :config (setq neo-window-width 40)
  :bind ("<f1>" . neotree-toggle))

(use-package undo-tree
  :ensure t
  :config
  (setq undo-tree-auto-save-history nil)
  (global-undo-tree-mode 1))

(use-package expand-region
  :ensure t
  :bind ("C-=" . er/expand-region))

(global-set-key (kbd "C-x C-b") 'buffer-menu)

(use-package smex :ensure t)

(use-package ivy
  :ensure t
  :diminish ivy-mode
  :config
  (ivy-mode t)
  (setq ivy-initial-inputs-alist nil))

(use-package counsel
  :ensure t
  :bind (("M-x" . counsel-M-x)
         ("C-x x" . smex)))

(use-package swiper
  :ensure t
  :bind (("M-s" . swiper)))

(defun my/install-ripgrep ()
  "Install ripgrep automatically if possible."
  (unless (executable-find "rg")

    (cond

     ;; macOS
     ((and (eq system-type 'darwin)
           (executable-find "brew"))
      (message "Installing ripgrep via brew...")
      (start-process
       "install-rg"
       "*install-rg*"
       "brew" "install" "ripgrep"))

     ;; Debian / Ubuntu
     ((and (eq system-type 'gnu/linux)
           (executable-find "apt"))
      (message "Installing ripgrep via apt...")
      (start-process
       "install-rg"
       "*install-rg*"
       "sudo" "apt" "install" "-y" "ripgrep"))

     ;; Fedora
     ((and (eq system-type 'gnu/linux)
           (executable-find "dnf"))
      (message "Installing ripgrep via dnf...")
      (start-process
       "install-rg"
       "*install-rg*"
       "sudo" "dnf" "install" "-y" "ripgrep"))

     ;; Arch
     ((and (eq system-type 'gnu/linux)
           (executable-find "pacman"))
      (message "Installing ripgrep via pacman...")
      (start-process
       "install-rg"
       "*install-rg*"
       "sudo" "pacman" "-S" "--noconfirm" "ripgrep"))

     (t
      (message "Please install ripgrep manually.")))))

(my/install-ripgrep)

(use-package vertico
  :init
  (vertico-mode 1)

  :custom
  (vertico-cycle t))

(use-package savehist
  :init
  (savehist-mode 1))

(use-package marginalia
  :after vertico
  :init
  (marginalia-mode 1))

(use-package orderless

  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)

  (completion-category-overrides
   '((file (styles basic partial-completion)))))

(use-package consult

  :bind
  (;; Search current buffer
   ("C-s"     . consult-line)

   ;; Project-wide ripgrep search
   ("C-c s"   . consult-ripgrep)

   ;; Buffer switch
   ("C-x b"   . consult-buffer)

   ;; Recent files
   ("C-c r"   . consult-recent-file)

   ;; Yank history
   ("M-y"     . consult-yank-pop)

   ;; Goto line
   ("M-g g"   . consult-goto-line)

   ;; Org headings
   ("C-c h"   . consult-org-heading)

   ;; Imenu/symbols
   ("C-c m"   . consult-imenu)

   ;; Git grep
   ("C-c g"   . consult-git-grep)

   ;; Errors
   ("C-c e"   . consult-flymake)))

;; Embark warns when Consult is later loaded and `embark-consult' cannot be
;; required. Install the integration package via use-package so elpaca picks
;; it up; `:after (embark consult)' defers loading until both prerequisites
;; are ready.
(use-package embark-consult
  :ensure t
  :after (embark consult))

(use-package embark

  :bind
  (("C-."     . embark-act)
   ("C-;"     . embark-dwim)
   ("C-h B"   . embark-bindings))

  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :ensure t
  :after (embark consult)

  :hook
  (embark-collect-mode . consult-preview-at-point-mode))

(setq enable-recursive-minibuffers t)

(setq completion-ignore-case t
      read-buffer-completion-ignore-case t
      read-file-name-completion-ignore-case t)

(setq minibuffer-prompt-properties
      '(read-only t
                  cursor-intangible t
                  face minibuffer-prompt))

(add-hook 'minibuffer-setup-hook
          #'cursor-intangible-mode)

(global-set-key (kbd "C-c c") 'org-capture)
(global-set-key (kbd "C-c a") 'org-agenda)
(global-set-key (kbd "C-c l") 'org-store-link)

(global-set-key (kbd "C-c t") 'eshell)

(setq org-enforce-todo-dependencies t)
(setq org-cycle-separator-lines 0)
(setq org-blank-before-new-entry '((heading) (plain-list-item . auto)))
(setq org-insert-heading-respect-content nil)
(setq org-reverse-note-order nil)
(setq org-show-following-heading t)
(setq org-show-hierarchy-above t)
(setq org-show-siblings '((default)))
(setq org-special-ctrl-a/e t)
(setq org-special-ctrl-k t)
(setq org-yank-adjusted-subtrees t)
(setq org-id-method 'uuidgen)
(setq org-deadline-warning-days 30)
(setq org-table-export-default-format "orgtbl-to-csv")
(setq org-table-use-standard-references 'from)
(setq org-read-date-prefer-future 'time)
(setq org-tags-match-list-sublevels t)
(setq org-fold-catch-invisible-edits 'error)
(setq org-clone-delete-id t)
(setq org-cycle-include-plain-lists t)
(setq org-odd-levels-only nil)
(setq org-id-link-to-org-use-id 'create-if-interactive-and-no-custom-id)
(setq require-final-newline t)
(setq org-log-state-notes-insert-after-drawers nil)
(setq org-file-apps '((auto-mode . emacs)
                       ("\\.mm\\'"    . system)
                       ("\\.x?html?\\'" . system)
                       ("\\.pdf\\'"   . system)))

(setq org-link-mailto-program '(compose-mail "%a" "%s"))

(defvar bh/insert-inactive-timestamp nil)

(defun bh/toggle-insert-inactive-timestamp ()
  (interactive)
  (setq bh/insert-inactive-timestamp (not bh/insert-inactive-timestamp))
  (message "Heading timestamps are %s" (if bh/insert-inactive-timestamp "ON" "OFF")))

(defun bh/insert-inactive-timestamp ()
  (interactive)
  (org-insert-time-stamp nil t t nil nil nil))

(defun bh/insert-heading-inactive-timestamp ()
  (save-excursion
    (when bh/insert-inactive-timestamp
      (org-return)
      (org-cycle)
      (bh/insert-inactive-timestamp))))

(add-hook 'org-insert-heading-hook 'bh/insert-heading-inactive-timestamp 'append)

(defun bh/prepare-meeting-notes ()
  "Convert selected region to meeting notes format and copy to kill ring."
  (interactive)
  (save-excursion
    (save-restriction
      (narrow-to-region (region-beginning) (region-end))
      (untabify (point-min) (point-max))
      (goto-char (point-min))
      (while (re-search-forward "^\\( *-\\) \\(TODO\\|DONE\\): " (point-max) t)
        (replace-match (concat (make-string (length (match-string 1)) ?>) " " (match-string 2) ": ")))
      (goto-char (point-min))
      (kill-ring-save (point-min) (point-max)))))

(prefer-coding-system 'utf-8)
(set-charset-priority 'unicode)
(setq default-process-coding-system '(utf-8-unix . utf-8-unix))
(setq org-duration-format
      '((special . h:mm)))
(setq org-list-demote-modify-bullet
      '(("+" . "-") ("*" . "-") ("1." . "-") ("1)" . "-")))
(setq org-remove-highlights-with-change t)

(add-hook 'org-mode-hook
          (lambda ()
             (org-defkey org-mode-map "\C-c[" 'undefined)
             (org-defkey org-mode-map "\C-c]" 'undefined)
             (org-defkey org-mode-map "\C-c;" 'undefined)
             (org-defkey org-mode-map "\C-c\C-x\C-q" 'undefined))
          'append)

(run-at-time "00:59" 3600 'org-save-all-org-buffers)

(use-package ispell
  :ensure nil
  :init
  (unless (executable-find "aspell")
    (when (executable-find "brew")
      (my/brew-install-and-log "formula" "aspell" "install" "aspell")))
  :config
  (setq ispell-program-name "aspell"
        ispell-dictionary "german"))
(defun my/turn-on-flyspell-if-aspell-available ()
  "Enable Flyspell only when aspell is installed."
  (if (executable-find ispell-program-name)
      (turn-on-flyspell)
    (message "Flyspell skipped: %s not found yet; restart after brew install finishes."
             ispell-program-name)))
(add-hook 'org-mode-hook #'my/turn-on-flyspell-if-aspell-available 'append)

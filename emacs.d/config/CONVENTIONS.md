# Configuration Conventions

This file covers the general code rules for **non-bootstrap configuration**
under `emacs.d/config/`. It describes how the actual feature modules
(`30_core.org`, `40_org.org`, `50_apple_reminders.org`, `60_emacs-agent-runtime.org`,
`70_wiki.org`, `80_gtd.org`, plus any future ones) are organised, and
which guardrails apply when editing them.

The bootstrap subsystem has its own stricter rules in
[`modules/20_bootstrap/BOOTSTRAP.md`](modules/20_bootstrap/BOOTSTRAP.md).
The rules below DO NOT apply inside that folder — bootstrap earns extra
discipline because it provisions external state. Everything else is
configuration that runs once at startup against an already-installed
Emacs.

If you are an AI coding agent: **read this file in full before touching
non-bootstrap modules.** Then read the file header of any specific
module you are about to change.

---

## 1. How feature modules are actually shaped

Feature modules are **deliberately flat, sequential, and growable**.
They do not follow a layered architecture; they configure a specific
tool (or small group of tools) and any helper functions that go with
that tool.

A typical module is one `.org` file with a structure like this:

```
#+TITLE: <Tool> Configuration
#+PROPERTY: header-args:emacs-lisp :tangle yes :lexical t

Loaded by: [[file:../config.org][config.org]] ← [[file:~/.emacs.d/init.el][init.el]]

#+begin_src emacs-lisp
;;; NN_name.el --- One-line description -*- lexical-binding: t; -*-

(require '<base-features>)

;; Forward declarations for the byte-compiler
(defvar my/data-dir)
(declare-function my/bootstrap-ready-p "20.03.01_bootstrap")
(defvar some-package-feature-var)
(declare-function some-package-fn "some-package")
#+end_src

* Org-mode section A
#+begin_src emacs-lisp
(use-package package-a …)
#+end_src

* Org-mode section B
#+begin_src emacs-lisp
(setq feature-a-config …)
(defun my/feature-helper ()
  …)
#+end_src

* … as many sections as the tool needs …
```

Empirically the existing modules range from **27 lines (`80_gtd.org`,
a thin loader)** to **1571 lines (`40_org.org`, Org + agenda + capture
+ roam + GTD overlays)**. Both extremes are fine. Length is not a
problem on its own — see §3 on when to split.

---

## 2. Branch strategy

| Branch | Role |
|---|---|
| `main` | Active development. All new commits land here first. |
| `stable` | Frozen known-good snapshots. Updated only by explicit fast-forward when `main` reaches a verified-on-real-Mac state. |
| Tags | Semantic versioning on `stable` snapshots (e.g. `v2.1.0`). |

**Default for an AI session:** push to `main` only. Never touch
`stable`, never create tags, and never force-push unless the user
explicitly asks.

---

## 3. When to split a module

Splitting is a real cost: more cross-file declarations, two places to
search when something breaks, more numeric-prefix arithmetic. Splits
need a clear reason.

| Signal | Action |
|---|---|
| Two clearly independent tools share one file (e.g. "calendar setup" + "GTD overlay") | Split into separate `NN_*.org` files with adjacent numeric prefixes. |
| The module manages external state (filesystem, processes, network) AND has tight idempotency requirements | Treat as a subsystem; give it its own subdirectory with its own subsystem-doc — see `20_bootstrap/` as the worked example. |
| You keep introducing bugs because state from the top of the file leaks into helpers at the bottom in non-obvious ways | Split or restructure. |

**Not enough on its own:**

- "The file is long." `40_org.org` is long because Org-mode has many
  integration points; splitting would scatter related configuration
  across files and force readers to chase symbols.
- "I want each `use-package` in its own file." Use-package blocks
  belong with the configuration they affect; a small package
  almost never warrants its own file.

---

## 4. Numeric prefix and load order

`config.org`'s discovery walks `modules/` recursively. At each level,
files and subdirectories sort together by `string<`. The numeric
prefix on each filename decides load order; smaller loads first.

```
modules/
  !00_startfirst.el      ← source-loaded elpaca bootstrap (! sorts ahead of digits)
  00_startfirst.org      ← theme, fullscreen
  10_tasks.el            ← async-tasks framework
  20_bootstrap/          ← subdirectory; its contents slot in at this position
  20_bootstrap.org.old   ← retired legacy file (.org.old suffix → discovery skips it)
  30_core.org            ← base Emacs, magit, completion
  40_org.org             ← Org, agenda, GTD, capture, roam
  50_apple_reminders.org
  60_emacs-agent-runtime.org
  70_wiki.org
  80_gtd.org
```

**Filename convention:** `NN_name.org` or `NN_name.el`. Use
underscores, never dashes. Leave gaps between numbers (10, 20, 30)
so future modules can insert without renumbering.

A subdirectory participates in the same sort sequence by its bare
name. So a future `15_protection_layer/` would load between
`10_tasks.el` and `20_bootstrap/` without any change to the loader.

---

## 5. File header (mandatory)

Every module starts with this block, as Elisp comments inside the
first `#+begin_src emacs-lisp` block:

```elisp
;;; NN_name.el --- One-line description -*- lexical-binding: t; -*-

(require '<base-package>)              ;; required at compile / load time
(require '<another-base>)

(defvar my/data-dir)                   ;; owned elsewhere; forward decl
(declare-function my/bootstrap-ready-p "20.03.01_bootstrap")
(defvar third-party-package-var)        ;; from a package this file uses
(declare-function third-party-fn "third-party-package")
```

The block has three purposes:

1. **`require` calls** at the top of the file pull in the core
   dependencies that this module composes around. Use-package is
   reserved for packages where lazy loading and `:config` ergonomics
   matter; bare `require` is fine for built-in packages this module
   names explicitly.

2. **Forward declarations** (`defvar` without a value, `declare-function`)
   silence the byte-compiler for symbols defined in OTHER files this
   module references. Without them, the byte-compiler emits "reference
   to free variable" or "function not known to be defined" warnings
   that pollute the build log.

3. **`my/bootstrap-ready-p`** must be `declare-function`-ed in every
   file that uses the `(when (my/bootstrap-ready-p) …)` guard pattern
   from §7.

`lexical-binding: t` is mandatory on every `.el` file's first line.
The pre-set `#+PROPERTY: header-args:emacs-lisp :tangle yes :lexical t`
at the top of the `.org` propagates this into the tangled `.el`.

---

## 6. Naming convention

Elisp has no language-level access control; we enforce visibility
**socially** through naming + cross-file declarations:

| Form | Meaning |
|---|---|
| `my/feature-bar` (single dash before name) | Public. Callable from other files. |
| `my/feature--baz` (double dash before name) | Private. Only this file may call. |
| `my/-helper` (leading double dash, no module prefix) | Repo-wide private utility. Rare; prefer file-local. |
| `(provide 'NN_name)` | The file's feature name matches the basename. |

**Cross-file calls require `declare-function` at the top of the
calling file.** A missing declaration produces a byte-compiler
warning, which is our signal that someone called across file
boundaries without acknowledging the dependency.

**Calling a `--`-prefixed symbol from another file is forbidden.** If
you need it from outside, either promote it to a single-dash name or
wrap it in a new public function.

---

## 7. The `my/bootstrap-ready-p` guard pattern

Any code that reads `my/data-dir` MUST be guarded by
`(my/bootstrap-ready-p)`. Without the guard, the code would
type-error on the `:not-resolved` sentinel when bootstrap halts.

```elisp
(use-package org
  :ensure nil
  :config
  ;; Path-dependent settings only when bootstrap converged:
  (when (my/bootstrap-ready-p)
    (setq org-directory (expand-file-name "data/org/" my/data-dir)
          org-agenda-files (list (expand-file-name "data/org/" my/data-dir))))
  ;; Non-path settings: unconditional
  (setq org-startup-folded t
        org-log-done 'time))
```

Two practical rules:

- **Each `setq` / `:custom` / `let` that references `my/data-dir` MUST
  be wrapped.** Don't trust ordering — feature modules load BEFORE
  the bootstrap halt-check propagates.
- **Helpers and hooks that USE the variable at runtime should guard
  with `(stringp my/data-dir)` or `(my/bootstrap-ready-p)` at the top
  of their body**, so an interactive caller gets a clear `user-error`
  instead of a type crash.

This is the only architectural rule that crosses module boundaries.
It exists because the cost of a missing guard (silent type error
deep in third-party code) is much higher than the cost of an extra
`(when …)` wrapper.

---

## 8. Use-package conventions

```elisp
(use-package package-name
  :ensure t                   ;; t for elpaca-managed, nil for built-in
  :demand t                   ;; demand only when load order matters
  :init   (setq …)            ;; runs BEFORE the package loads (rare)
  :custom (var-name VALUE)    ;; preferred over `:config (setq …)' for
                              ;; declared customizable options
  :bind   (("C-c X" . cmd))   ;; key bindings
  :hook   ((mode-hook . cmd)) ;; hook installation
  :config                     ;; runs AFTER the package loads
  (setq runtime-var …)
  (some-init-call))
```

- **One `use-package` per package.** Don't bundle multiple packages
  into a single `use-package`.
- **`:custom` over `:config (setq …)`** when the option is declared
  with `defcustom` — `:custom` reuses the standard Emacs customisation
  pipeline.
- **`:demand t` only when you need the package present at file-load
  time** (typically because a subsequent block calls into it
  unconditionally). For everything else, lazy-loading via the
  autoloads the package ships is faster.

---

## 9. Idempotency where it matters

This rule applies whenever a module writes to external state — most
often directory creation:

```elisp
(unless (file-directory-p some-dir)
  (make-directory some-dir t))
```

Run the function twice → same final state. Run on a fresh install →
directory created. Run on a populated install → no-op.

Path-dependent directories MUST be created behind a
`(when (my/bootstrap-ready-p) …)` guard. Without the guard,
`make-directory` against the sentinel would crash.

What this rule does NOT cover: pure configuration (`setq`,
key-bindings, hooks). Those are inherently idempotent because they
overwrite themselves on each load.

---

## 10. Code style

- **No comments by default.** Identifier names and structure carry
  the meaning. Add a comment only when the *why* is non-obvious to
  a reader who knows Elisp but not this repo's history. Never
  explain *what* the code does — that is the code's job.

- **No clever one-liners.** This is config code maintained by humans
  plus AI sessions; readability beats density.

- **Avoid quoted lambdas (`'(lambda …)`).** Use `(lambda …)`
  directly. Emacs 27+ warns on the quoted form; it is wrong for
  byte-compilation.

- **All `#+begin_src emacs-lisp` blocks in `.org` files inherit
  `:tangle yes`** from the file's `#+PROPERTY: header-args:emacs-lisp`
  line. Add a per-block `:tangle no` only when you genuinely want the
  block as documentation (e.g. a copy of `early-init.el` for
  reference). A `:tangle yes` block silently dropped (because the
  property line is missing or stale) causes 32-byte tangle output, a
  silent corruption that breaks the module.

- **`lexical-binding: t`** in every file's first-line comment.

Function size: aim for 5–15 lines when the function does one thing.
Long `use-package` blocks, long capture-template forms, long
agenda-customisation blocks — those are configuration manifests, not
functions, and length is fine.

---

## 11. Refactoring rules

1. **No backward-compat shims when changing data shapes.** Ship only
   the new shape. The user cleans up legacy data manually when they
   want to.

2. **No autonomous side effects.** Background tasks (auto-update,
   auto-sync) fire only on explicit user command (`M-x my/<feature>-<action>`),
   never automatically at boot. Auto-fired background work is a
   frequent source of non-deterministic test failures and surprise
   log noise.

3. **Check existing community tools before building custom
   infrastructure.** Before writing more than ~50 lines of custom
   plumbing, search for an existing solution (`auth-source`,
   `persist.el`, `aio.el`, `exec-path-from-shell`, …).

4. **Minimal scope per task.** When asked to do X, do only X. Do not
   widen to "while I'm here" cleanups without explicit per-edit
   confirmation.

---

## 12. Verification before commit

```
1. Tangle: org-babel-tangle-file on the .org → produces fresh .el
2. Byte-compile: emacs --batch -L . -f batch-byte-compile <file>.el
   → no NEW warnings (pre-existing elpaca-resolution noise in
   batch-Q environments is acceptable)
3. Paren balance: emacs --batch ... '(check-parens)' → 0
```

For UI/UX changes, exercise the path in a real Emacs.

---

## 13. Commit conventions

- Use conventional commit prefixes: `fix:`, `feat:`, `refactor:`,
  `perf:`, `cleanup:`, `docs:`. Scope in parentheses when useful:
  `fix(org):`, `feat(gptel):`.

- **Title ≤ 70 characters.** Details in the body.

- **Body explains the WHY**, not the WHAT. Reference the failure
  mode or motivation, not the code change. The diff already shows
  the code change.

- **Always include `Co-Authored-By:` footers** when an AI agent
  contributed:
  ```
  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
  Co-Authored-By: Denis Butic <d.e.n.o@gmx.net>
  ```

- **Confirm before pushing risky operations.** Force-push,
  `git reset --hard`, deleting branches/tags — all require explicit
  user approval each time.

---

## 14. AI working conventions

1. **Read this file first.** Then any subsystem doc relevant to the
   task (e.g. `modules/20_bootstrap/BOOTSTRAP.md` if touching
   bootstrap). Then the file header of any file you are about to
   change.

2. **State your plan in one sentence before editing.** "I'll add a
   guard around `org-roam-db-autosync-mode` so it doesn't fire when
   `my/data-dir` is the sentinel." The user can correct course
   before tool calls are spent.

3. **Minimal-scope edits.** Do not refactor adjacent code on the
   side. If you notice an unrelated issue, mention it after
   completing the asked task — do not silently fix it.

4. **No new abstractions without explicit request.** Helper
   functions added "to make this cleaner" rarely pull their weight.
   If you find yourself wanting one, ask.

5. **Confirm before destructive actions.** Removing files, renaming
   functions used elsewhere, dropping support for a credential
   shape — all require explicit user approval.

6. **Verify before claiming success.** "Test passed" / "build green"
   claims must be backed by an actual command run in this session
   with the output shown, not assumed from the diff.

7. **Honest reports of failure.** Report exact errors. Do not
   paper over with "should work now" — that sentence has cost this
   codebase real time.

---

## 15. Subsystem-specific rules

| Subsystem | Folder | Doc |
|---|---|---|
| Bootstrap (provisioning) | `modules/20_bootstrap/` | [`BOOTSTRAP.md`](modules/20_bootstrap/BOOTSTRAP.md) |

A subsystem document **adds** rules on top of this file; it does
not replace them. The bootstrap doc adds three-layer architecture,
strict per-file size ceilings, and a list of forbidden patterns
that are specific to provisioning code.

If a new subsystem with comparable complexity emerges (a
self-managing async pipeline, a credential-rotation engine, etc.),
give it its own subdirectory + subsystem doc following the same
pattern.

---

## 16. Living document

This file IS subject to change, but only via explicit edits proposed
by the user. An AI agent does not silently update conventions. If a
convention turns out to be wrong or insufficient, raise it in
conversation; if the user agrees, edit this file in a dedicated
commit (`docs: clarify use-package :custom vs :config`).

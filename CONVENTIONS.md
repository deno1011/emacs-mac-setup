# Development Conventions

This document captures the rules, principles, and patterns we use to
develop this codebase. It is written for both human developers and AI
coding agents (Claude, Cursor, GitHub Copilot, etc.) who join an
existing session or pick up the codebase cold.

If you are an AI agent: **read this file in full before editing any
code in this repository.** The conventions below are not stylistic
preferences — they encode hard-won lessons about idempotency, race
conditions, and maintainability. Violating them silently is the
failure mode this document exists to prevent.

Subsystem-specific rules are kept in separate documents alongside
this one:

| Subsystem | Document |
|---|---|
| Bootstrap (`00.LL.SS_bootstrap-*.org`) | [`BOOTSTRAP.md`](BOOTSTRAP.md) |

The general rules below apply to every file in the repo. Subsystem
documents add extra requirements on top — never replace the general
rules, only layer over them.

---

## 1. Branch strategy

| Branch | Role |
|---|---|
| `main` | Active development. All new commits land here first. |
| `stable` | Frozen known-good snapshots. Only updated by explicit fast-forward when `main` reaches a state the maintainer has verified end-to-end on a real Mac. |
| Tags | Semantic versioning on `stable` snapshots (e.g. `v2.1.0`). |

**Default for an AI session:** push to `main` only. Never touch
`stable`, never create tags, and never force-push unless the user
explicitly asks.

When the user says "looks good, freeze it", that means:
`git push origin main:stable` (fast-forward only) plus optionally a
new tag.

---

## 2. Module structure

The default shape of an Elisp module in this repo is **flat and
top-to-bottom readable**:

```
;;; NN-feature.org — One-sentence description.
;;
;; (File header block — see §3.)

(use-package …)            ;; configuration of one tool or concern

(defvar my/feature-foo …)  ;; module-level state

(defun my/feature-bar …)   ;; public helpers

(defun my/feature--baz …)  ;; private helpers (double-dash)
```

One concern per file. The numeric filename prefix decides load order
(`config.org`'s discovery loop sorts files by `string<`).

**When to split a module:**

| Signal | Action |
|---|---|
| The file has clearly independent concerns (e.g. "calendar setup" + "GTD overlay") | Split into separate `NN-*.org` files with adjacent numeric prefixes. |
| The file's complexity warrants layered architecture (rare; bootstrap is the current case) | See subsystem document (e.g. `BOOTSTRAP.md`). |

**When NOT to split:**

| Signal | Why it's not enough |
|---|---|
| File is "long" (1000+ lines) | Length alone is fine. `40-org.org` is long because Org-mode has many integration points; splitting would scatter related configuration across files. |
| Single Aesthetic preference | The cost of a split is real (cross-file dependencies, two files to find things in). Splits need a reason. |

The bar to introduce internal layering inside a single file is high:
"I keep introducing bugs because state from the top of the file leaks
into helpers at the bottom in non-obvious ways" is the trigger, not
"this file is hard to scroll through".

---

## 3. File header (mandatory)

Every file MUST start with this block, as Elisp comments, before any
`require`:

```elisp
;;; NN-feature.el --- One-line description -*- lexical-binding: t -*-
;;
;; Public API (callable from other files):
;;   (my/feature-foo ARG)        → return value type / meaning
;;   (my/feature-bar)            → t / nil
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/feature--baz
;;   my/feature--cache
;;
;; Depends on (declared with `declare-function' below):
;;   my/other-feature-thing     ← NN-other-feature
```

The header is contract documentation. If you change the public API,
update the header in the same commit. If you add a private helper,
add it to the internal list so the next reader knows it exists. If a
file has no public API (it's pure side-effect configuration), the
Public API section may say `(none — load-time configuration only)`.

---

## 4. Public vs private symbols

Elisp has no language-level access control. We enforce visibility
**socially** through naming + cross-file declarations:

| Form | Meaning |
|---|---|
| `my/feature-bar` (single dash before name) | Public. Callable from any file. |
| `my/feature--baz` (double dash) | Private. Only this file may call. |
| `my/--utility-fn` (leading double dash, no module prefix) | Repo-wide private utility. Used rarely; prefer file-local. |

**Cross-file calls require a `declare-function` at the top of the
calling file.** The byte-compiler enforces this through warnings — a
missing declaration produces "the function `my/foo-bar' is not known
to be defined" at compile time, which is our signal that someone
called across file boundaries without declaring the dependency.

Example at the top of a file that uses another module's public API:

```elisp
(declare-function my/keychain-get "00.01.01_bootstrap-keychain")
(declare-function my/keychain-set "00.01.01_bootstrap-keychain")
```

**Calling a `--`-prefixed symbol from another file is forbidden.**
Period. If you need it from outside, promote it to a single-dash
name (and update the file header's Public API section), or wrap it
in a new public function.

---

## 5. Idempotency

**Any function that mutates external state — filesystem, processes,
network, OS-level configuration, persistent storage — must be
idempotent.**

Definition:

> Running the function twice produces the same final state as running
> it once. The second call is a no-op.

This rule applies to install scripts, bootstrap code, content
generators, anything that writes to disk, anything that calls into
a system service. It does NOT apply to read-only computations or
Emacs-internal state changes.

Concrete requirements:

1. **Read fresh state at point of use.** If a function checks whether
   the data folder exists, it reads the filesystem at that moment.
   It does NOT consult a "probe-data" plist filled by an earlier
   function. Shared mutable caches between operations are the
   single most common source of silent inconsistency in this
   codebase's history.

2. **No mutable shared globals between operations.** If two functions
   need the same external information, both should read it fresh.
   The cost (a few extra system calls) is negligible; the
   correctness gain is total.

3. **Return a structured result, not a side effect.** The convention:
   ```elisp
   :done      ; the function did real work and the state is now correct
   :skip      ; the state was already correct; nothing was done
   (:error "human-readable message")  ; the function could not converge
   ```
   The caller decides what to do with each result (continue, halt,
   log a warning). Low-level functions never call `display-warning`
   or `message` themselves — they return facts.

4. **State-checking predicates must agree with state-mutating writes.**
   If `my/foo-exists-p` returns `t`, a subsequent `my/foo-create` must
   return `:skip` (not `:done`, not an error). Test both directions
   when introducing or changing either side.

---

## 6. Error handling

There are exactly three error categories. Code MUST classify each
failure into one of them; "just return nil" is not acceptable.

| Category | When | What the function does |
|---|---|---|
| **Expected: nothing to do** | Pre-condition is already satisfied. | Return `:skip`. |
| **Expected: cannot proceed** | A required input is missing (no credential, no network, etc.). The user can fix this. | Return `(:error "human-readable message including the next action the user should take")`. |
| **Unexpected: system fault** | A system call failed in a way the function did not anticipate. | Let it signal an Elisp error (`(error ...)`). Do not swallow with `condition-case` at low levels. |

Top-level callers (the orchestrators, the interactive entry points)
wrap their work in a `condition-case` and turn uncaught errors into
a `(:error ...)` for the user. This keeps the user out of the
debugger but preserves the traceback in `*Messages*`.

---

## 7. Code style

- **No comments by default.** Identifier names and structure should
  carry the meaning. Add a comment only when the *why* is non-obvious
  to a reader who knows Elisp but not this repo's history (a hidden
  constraint, a subtle invariant, a workaround for a specific bug).
  Never explain *what* the code does — that is the code's job. Never
  reference the current task, fix, or callers ("used by X", "added
  for Y").

- **No clever one-liners.** This is config code maintained by humans
  plus AI sessions; readability beats density every time. `let*`
  bindings with descriptive names beat anonymous sub-expressions.

- **Avoid quoted lambdas (`'(lambda …)`).** Use `(lambda …)`
  directly. Emacs 27+ warns on the quoted form; it is wrong for
  byte-compilation.

- **All `#+begin_src elisp` blocks in `.org` files must have
  `:tangle yes`.** A missing `:tangle yes` causes the tangle output
  to be truncated to 32 bytes — a silent corruption that breaks the
  entire module.

- **`lexical-binding: t` in every file's first-line comment.** Default
  for all new Elisp files.

Function size: aim for 5–15 lines when the function does one thing.
This is not a hard rule — top-level configuration manifests (long
`use-package` blocks) are naturally longer and that's fine.

---

## 8. Object-oriented patterns (Elisp idioms)

Elisp has several object/struct-style mechanisms. The preferred set,
in order of priority:

1. **`cl-defstruct` for data shapes.** Use it whenever you pass around
   a bag of named fields. Avoid raw `plist`s for cross-file data —
   the compiler cannot help you catch typos in plist keys.

2. **`cl-defgeneric` + `cl-defmethod` for polymorphism.** If you need
   "this operation has multiple backends" (e.g., a Keychain backend
   and an env-var backend), use generic dispatch. Avoid if/cond
   chains keyed on a symbol.

3. **Plain `defun` + plain `defvar` for everything else.** Most of
   the code should be unsurprising functions and module-local state.

**Avoid EIEIO** (`defclass`, `:protection :private`) unless there is
a clear inheritance hierarchy. EIEIO works, but in 99% of cases the
combination of `cl-defstruct` + naming convention + file headers
delivers the same encapsulation with far less ceremony.

**Avoid closures for state-hiding** unless the data truly must be
unreachable from outside (rare). The double-dash naming convention
is simpler and equally effective for any reasonable threat model.

---

## 9. Refactoring rules

These rules exist to keep refactors small and reviewable.

1. **No backward-compat shims when changing data shapes.** Ship the
   new shape only. Do not auto-migrate legacy values. Do not maintain
   parallel readers for old and new. The user cleans up legacy data
   manually when they want to. Applies to credentials, plist schemas,
   file formats — everything.

2. **No autonomous side effects.** Background tasks (distro updates,
   service installation, etc.) fire only on explicit user command
   (`M-x my/update-distro`, etc.), never automatically at boot.
   Auto-fired background work is a frequent source of
   non-deterministic test failures and surprise log noise.

3. **Check existing community tools before building custom
   infrastructure.** Before writing more than ~50 lines of custom
   plumbing, search for an existing solution (`elpaca` for package
   management, `aio.el` for async, `auth-source` for Keychain
   access, `persist.el` for serialization). The pattern that
   motivated this rule: this codebase once carried three layers of
   custom package management when `elpaca` already provided them.

4. **Minimal scope per task.** When asked to do X, do only X. Do not
   widen to "while I'm here, let me also fix Y" without explicit
   per-edit confirmation. Even for changes that look like
   consistency-preserving cleanups.

---

## 10. Verification before commit

Before committing any code change:

```
1. Tangle: org-babel-tangle-file on the .org → produces fresh .el
2. Byte-compile: emacs --batch -L . -f batch-byte-compile <file>.el
   → no new warnings
3. Paren balance: emacs --batch ... '(check-parens)'
   → 0 (no error)
```

For race-condition or concurrency fixes, **build a shell-level
synthetic reproduction first** that demonstrates the bug
deterministically. The test for `my/keychain-multi-get` (100/100
corrupt before fix → 0/100 after) is the model — see the commit
`3c09a91` for the pattern.

For UI/UX changes, start a real Emacs and exercise the path.
Type-checking verifies code correctness, not feature correctness.

---

## 11. Commit conventions

- Use conventional commit prefixes: `fix:`, `feat:`, `refactor:`,
  `perf:`, `cleanup:`, `docs:`. Scope in parentheses when useful:
  `fix(install):`, `perf(bootstrap):`.

- **Title ≤ 70 characters.** Details go in the body.

- **Body explains the WHY**, not the WHAT. Reference the failure
  mode, not the code change. The diff already shows the code change.

- **Always include `Co-Authored-By:` footers** when an AI agent
  contributed to the commit:
  ```
  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
  Co-Authored-By: Denis Butic <d.e.n.o@gmx.net>
  ```

- **Confirm before pushing risky operations.** Force-push,
  `git reset --hard`, deleting branches, deleting tags — all
  require explicit user approval each time.

---

## 12. AI working conventions

When an AI agent picks up a task in this repo:

1. **Read this file first.** Then read any subsystem document (e.g.
   `BOOTSTRAP.md`) relevant to the task. Then read the file header
   of any file you are about to touch.

2. **State your plan in one sentence before editing.** "I'll change
   `my/secrets-readable-p` to also return the diagnostic message
   when `nil`." The user can correct course before you spend tool
   calls.

3. **Minimal-scope edits.** Do not refactor adjacent code on the
   side. If you notice an unrelated issue, mention it after
   completing the asked task — do not silently fix it.

4. **No new abstractions without explicit request.** Helper
   functions added "to make this cleaner" rarely pull their weight.
   If you find yourself wanting one, ask first.

5. **Confirm before destructive actions.** Removing files, renaming
   functions used in other files, dropping support for a credential
   shape — all require explicit user approval in the same session.

6. **Verify before claiming success.** "Test passed" / "build green"
   claims must be backed by an actual command run in this session
   and shown in the output, not assumed from the diff.

7. **Honest reports of failure.** If a tangle/build/test fails,
   report the exact error. Do not paper over with "should work now"
   — that sentence has cost this codebase real time.

---

## 13. Living document

This file IS subject to change, but only via explicit edits proposed
by the user. An AI agent does not silently update the conventions.
If a convention turns out to be wrong or insufficient, raise it in
conversation; if the user agrees, edit this file in a dedicated
commit (`docs: clarify error-return contract`).

The same rule applies to subsystem documents (`BOOTSTRAP.md`,
future additions).

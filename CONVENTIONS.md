# Development Conventions

This document captures the rules, principles, and patterns we use to develop
this Emacs distribution. It is written for both human developers and AI
coding agents (Claude, Cursor, GitHub Copilot, etc.) who join an existing
session or pick up the codebase cold.

If you are an AI agent: **read this file in full before editing any code in
this repository.** The conventions below are not stylistic preferences —
they encode hard-won lessons about idempotency, race conditions, and
maintainability. Violating them silently is the failure mode this document
exists to prevent.

---

## 1. Branch strategy

| Branch | Role |
|---|---|
| `main` | Active development. All new commits land here first. |
| `stable` | Frozen known-good snapshots. Only updated by explicit fast-forward when `main` reaches a state the maintainer has verified end-to-end on a real Mac. |
| Tags | Semantic versioning on `stable` snapshots (e.g. `v2.1.0`). |

**Default for an AI session:** push to `main` only. Never touch `stable`,
never create tags, and never force-push unless the user explicitly asks.

When a user says "looks good, freeze it", that means:
`git push origin main:stable` (fast-forward only) + optionally a new tag.

---

## 2. Layered architecture

All non-trivial subsystems follow a three-layer model. Layers are physical
file boundaries, not just conceptual:

```
LAYER 3 — Business logic
  One main file. Defines the public entry points the rest of the system
  calls (e.g. `my/bootstrap`). Reads top-to-bottom like pseudo-code.
  No system calls, no string-mangling — only calls into Layer 2.
  Target size per file: 50–200 lines.

LAYER 2 — Domain operations
  One file per domain concept (secrets, repo, identity, …). Each function
  describes ONE thing from the user's world: "is the data folder healthy?",
  "is the API key set?". Composes Layer-1 primitives, returns structured
  results (see §6). Knows nothing about UI or user interaction.
  Target size per file: 50–150 lines.

LAYER 1 — System primitives
  One file per kind of resource (Keychain, git, process, file). Each
  function wraps ONE system call (`security`, `git`, `call-process`,
  `file-exists-p`). Returns `:ok` / `:error` with message. No business
  logic, no inter-file dependencies inside Layer 1.
  Target size per file: 30–100 lines.
```

**The strict rule: Layer N may only call Layer N−1.** Layer 1 never calls
Layer 2. Layer 2 never calls Layer 3. If you ever feel like calling
"upward", that means the abstraction is wrong — stop and discuss.

**File numbering encodes layer and load order.** Files inside the bootstrap
subsystem use this scheme:

```
00.010_bootstrap-keychain.org    ← Layer 1, loaded first
00.020_bootstrap-git.org         ← Layer 1
00.030_bootstrap-process.org     ← Layer 1
00.040_bootstrap-secrets.org     ← Layer 2
00.050_bootstrap-repo.org        ← Layer 2
00.060_bootstrap-identity.org    ← Layer 2
00.100_bootstrap.org             ← Layer 3, loaded last
```

`config.org`'s discovery loop sorts files by `string<`, so `00.010 <
00.020 < … < 00.100 < 10-…`. Every bootstrap-layer file loads before
any feature module (`10-`, `20-`, `30-`, …) and the main `00.100` loads
after its primitives are in place.

Existing feature modules (`30-core.org`, `40-org.org`, etc.) sit at
file-name level — they are not part of the layer model and may call into
the bootstrap's public Layer-3 surface (currently `my/data-dir` and
`my/api-key-fetch`).

---

## 3. One module per file

Every `.org` (or vendored `.el`) module owns exactly one concern. If a file
needs to grow past ~200 lines for one concern, consider splitting the
concern into sub-concerns first. Large files defeat the point of the layer
model: they bury implicit cross-dependencies that the next reader (human or
AI) has no way to spot.

**Antipattern we are explicitly moving away from:** the legacy
`20-bootstrap.org` at ~4000 lines, bundling Keychain primitives, Bitwarden
CLI, git-crypt, GitHub identity, a widget-based form, an orchestrator, and
starter-data generation in one file. That structure produced the race
conditions and silent failures that motivated this rewrite.

---

## 4. File header (mandatory)

Every file MUST start with this block (Elisp comment lines, before any
`require`):

```elisp
;;; 00.040_bootstrap-secrets.el --- Secret access for bootstrap -*- lexical-binding: t -*-
;;
;; Layer 2 — Domain operations.
;;
;; Public API (callable from other files):
;;   (my/secrets-readable-p)         → t / nil
;;   (my/api-key-fetch KEY)          → string or nil
;;   (my/api-key-set KEY VALUE)      → :ok or (:error MSG)
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/secrets--read-keychain
;;   my/secrets--validate-key-name
;;
;; Depends on (declared at top of file with `declare-function'):
;;   my/keychain-get        ← 00.010_bootstrap-keychain
;;   my/keychain-set        ← 00.010_bootstrap-keychain
```

The header is contract documentation. If you change the public API, update
the header in the same commit. If you add a private helper, add it to the
internal list so the next reader knows it exists.

---

## 5. Public vs private symbols

Elisp has no language-level access control. We enforce visibility
**socially** through naming + cross-file declarations:

| Form | Meaning |
|---|---|
| `my/foo-bar` (single dash) | Public. Callable from any file. |
| `my/foo--internal-thing` (double dash) | Private. Only this file may call. |
| `my/--utility-fn` (leading double dash, no module prefix) | Repo-wide private utility. Used rarely; prefer file-local. |

**Cross-file calls require a `declare-function` at the top of the calling
file.** The byte-compiler enforces this through warnings — a missing
declaration produces "the function `my/foo-bar' is not known to be
defined" at compile time, which is our signal that someone called across
file boundaries without declaring the dependency.

Example at top of a Layer-2 file that uses Layer-1 keychain primitives:

```elisp
(declare-function my/keychain-get "00.010_bootstrap-keychain")
(declare-function my/keychain-set "00.010_bootstrap-keychain")
```

**Calling a `--`-prefixed symbol from another file is forbidden.** Period.
If you need it from outside, promote it to a single-dash name (and update
the file header's Public API section), or wrap it in a new public function.

---

## 6. Idempotency contract

Every `ensure-*` and every operation that mutates external state MUST
satisfy:

> Running the function twice produces the same final state as running it
> once. The second call is a no-op.

This is non-negotiable. Bootstrap, install scripts, content generators —
all of them get re-run by users (or by the orchestrator on every Emacs
launch) and silently breaking on the second call is the single most
common bug class we have hit.

Concrete rules:

1. **Read fresh state at point of use.** Do not depend on a shared
   "probe-data" plist filled at startup. Each `ensure-*` function reads
   what it needs from the source of truth (Keychain, disk, process) at
   the moment it runs. The performance cost is negligible (~17 ms per
   Keychain read on macOS); the correctness gain is total.

2. **No mutable shared globals between operations.** The legacy
   `my/-bootstrap-probe-data` plist that all 8 orchestrator steps read
   from was the root cause of multiple silent failures in this codebase
   (race conditions in the parallel filler, stale entries after the
   form rewrote secrets). The new architecture does NOT have an
   equivalent shared cache.

3. **Return a structured result, not a side effect.** The convention is:
   ```elisp
   :done      ; the function did real work and the state is now correct
   :skip      ; the state was already correct; nothing was done
   (:error "human-readable message")  ; the function could not converge
   ```
   The Layer-3 orchestrator decides what to do with each result
   (continue, halt, log a warning). Layer-1/2 functions never call
   `display-warning` or `message` themselves — they return facts.

4. **State-checking predicates must agree with state-mutating writes.**
   If `my/foo-exists-p` returns `t`, then a subsequent `my/foo-create`
   must return `:skip` (not `:done`, not an error). Test both directions.

---

## 7. Error handling pattern

There are exactly three error categories. Code MUST classify each failure
into one of them; "just return nil" is not acceptable.

| Category | When | What the function does |
|---|---|---|
| **Expected: nothing to do** | Pre-condition for the operation is already satisfied. | Return `:skip`. |
| **Expected: cannot proceed** | A required input is missing (e.g., no Keychain entry, no network). The user can fix this. | Return `(:error "human-readable message with the next action the user should take")`. |
| **Unexpected: system fault** | A system call failed in a way the function did not anticipate. | Let it signal an Elisp error (`(error ...)`). Do not swallow with `condition-case` at Layer 1 or 2. |

Layer 3 (business logic) wraps the orchestrator in a `condition-case` and
turns uncaught errors into a `(:error ...)` for the top-level caller. This
keeps the user out of the debugger but preserves the traceback in
`*Messages*`.

---

## 8. Code style

- **No comments by default.** Identifier names and structure should carry
  the meaning. Add a comment only when the *why* is non-obvious to a reader
  who knows Elisp but not this repo's history (a hidden constraint, a
  subtle invariant, a workaround for a specific bug). Never explain *what*
  the code does — that is the code's job. Never reference the current
  task, fix, or callers ("used by X", "added for Y").

- **Function length: target 5–15 lines.** A function much longer than that
  is probably mixing two concerns. The exceptions are the Layer-3
  orchestrator entry point and form-style top-level definitions, which
  read like manifests.

- **No clever one-liners.** This is config code maintained by humans plus
  AI sessions; readability beats density every time. `let*` bindings with
  descriptive names beat anonymous sub-expressions.

- **Avoid quoted lambdas (`'(lambda …)`).** Use `(lambda …)` directly.
  Emacs 27+ warns on the quoted form; it is wrong for byte-compilation.

- **All `#+begin_src elisp` blocks in `.org` files must have `:tangle yes`.**
  A missing `:tangle yes` causes the tangle output to be truncated to
  32 bytes — a silent corruption that breaks the entire module.

- **`lexical-binding: t` in every file's first-line comment.** Default for
  all new Elisp files.

---

## 9. Object-oriented patterns (Elisp idioms)

Elisp has several object/struct-style mechanisms. The preferred set, in
order of priority:

1. **`cl-defstruct` for data shapes.** Use it whenever you pass around a
   bag of named fields. Avoid raw `plist`s for cross-file data — the
   compiler cannot help you catch typos in plist keys.

2. **`cl-defgeneric` + `cl-defmethod` for polymorphism.** If you need
   "this operation has multiple backends" (e.g., a Keychain backend and
   an env-var backend for secrets), use generic dispatch. Avoid
   if/cond chains keyed on a symbol.

3. **Plain `defun` + plain `defvar` for everything else.** Most of the
   code should be unsurprising functions and module-local state.

**Avoid EIEIO** (`defclass`, `:protection :private`) unless there is a
clear inheritance hierarchy. EIEIO works, but in 99% of cases the
combination of `cl-defstruct` + naming convention + file headers
delivers the same encapsulation with far less ceremony.

**Avoid closures for state-hiding** unless the data truly must be
unreachable from outside (rare). The double-dash naming convention is
simpler and equally effective for any reasonable threat model.

---

## 10. Refactoring rules

These rules exist to keep refactors small and reviewable.

1. **No backward-compat shims when changing data shapes.** Ship the new
   shape only. Do not auto-migrate legacy values. Do not maintain
   parallel readers for old and new. The user cleans up legacy data
   manually when they want to. This applies to credentials, plist
   schemas, file formats — everything.

2. **No autonomous side effects.** Background tasks (distro updates,
   daemon-service installation) fire only on explicit user command
   (`M-x my/update-distro`, etc.), never automatically at boot. Auto-fired
   background work is a frequent source of non-deterministic test
   failures and surprise log noise.

3. **Check existing community tools before building custom infrastructure.**
   Before writing more than ~50 lines of custom plumbing, search for an
   existing solution (`elpaca` for package management, `aio.el` for async,
   `auth-source` for Keychain access, `persist.el` for serialization).
   The pattern that motivated this rule: this codebase once carried three
   layers of custom package management when `elpaca` already provided them.

4. **Minimal scope per task.** When asked to do X, do only X. Do not widen
   to "while I'm here, let me also fix Y" without explicit per-edit
   confirmation. Even for changes that look like consistency-preserving
   cleanups.

---

## 11. Verification before commit

Before committing any code change:

```
1. Tangle: org-babel-tangle-file on the .org → produces fresh .el
2. Byte-compile: emacs --batch -L . -f batch-byte-compile <file>.el
   → no new warnings
3. Paren balance: emacs --batch ... '(check-parens)'
   → 0 (no error)
```

For race-condition or concurrency fixes, **build a shell-level synthetic
reproduction first** that demonstrates the bug deterministically. The
test for `my/keychain-multi-get` (100/100 corrupt before fix → 0/100
after) is the model.

For UI/UX changes, start a real Emacs and exercise the path. Type-checking
verifies code correctness, not feature correctness.

---

## 12. Commit conventions

- Use conventional commit prefixes: `fix:`, `feat:`, `refactor:`, `perf:`,
  `cleanup:`, `docs:`. Scope in parentheses when useful: `fix(install):`,
  `perf(bootstrap):`.

- **Title ≤ 70 characters.** Details go in the body.

- **Body explains the WHY**, not the WHAT. Reference the failure mode,
  not the code change. The diff already shows the code change.

- **Always include `Co-Authored-By:` footers** when an AI agent
  contributed to the commit. Format:
  ```
  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
  Co-Authored-By: Denis Butic <d.e.n.o@gmx.net>
  ```

- **Confirm before pushing risky operations.** Force-push, `git reset
  --hard`, deleting branches, deleting tags — all require explicit user
  approval each time.

---

## 13. Repository layout (target)

After the bootstrap rewrite, the layout will be:

```
emacs-mac-setup/
├── install.sh                  ← Foreground install (idempotent ensure-* functions)
├── uninstall.sh
├── README.md
├── CONVENTIONS.md              ← This file
├── !STARTHERE.md
│
└── emacs.d/
    ├── early-init.el
    ├── init.el
    ├── secrets.el.template
    └── config/
        ├── config.org
        └── modules/
            ├── !00_startfirst.el            ← Source-loaded elpaca bootstrap
            ├── 00.010_bootstrap-keychain.org   ← Layer 1
            ├── 00.020_bootstrap-git.org        ← Layer 1
            ├── 00.030_bootstrap-process.org    ← Layer 1
            ├── 00.040_bootstrap-secrets.org    ← Layer 2
            ├── 00.050_bootstrap-repo.org       ← Layer 2
            ├── 00.060_bootstrap-identity.org   ← Layer 2
            ├── 00.100_bootstrap.org            ← Layer 3 (main entry)
            ├── 10-tasks.el
            ├── 30-core.org
            ├── 40-org.org
            ├── 50-apple-reminders.org
            ├── 60-gptel.org
            ├── 70-wiki.org
            └── 80-gtd.org
```

The legacy `20-bootstrap.org` is renamed to `20-bootstrap.org.old` during
the rewrite — the `.old` suffix removes the `.org` extension that
`config.org`'s discovery loop matches on, so the file is preserved on
disk for reference but never loaded.

---

## 14. AI working conventions

When an AI agent picks up a task in this repo, the expectation is:

1. **Read this file first.** Then read the file header of any file you
   are about to touch.

2. **State your plan in one sentence before editing.** "I'll change
   `my/secrets-readable-p` to also return the diagnostic message when
   `nil`." The user can correct course before you spend tool calls.

3. **Minimal-scope edits.** Do not refactor adjacent code on the side.
   If you notice an unrelated issue, mention it after completing the
   asked task — do not silently fix it.

4. **No new abstractions without explicit request.** Helper functions
   added "to make this cleaner" rarely pull their weight. If you find
   yourself wanting one, ask first.

5. **Confirm before destructive actions.** Removing files, renaming
   functions used in other files, dropping support for a credential
   shape — all require explicit user approval in the same session.

6. **Verify before claiming success.** "Test passed" / "build green"
   claims must be backed by an actual command run in this session and
   shown in the output, not assumed from the diff.

7. **Honest reports of failure.** If a tangle/build/test fails, report
   the exact error. Do not paper over with "should work now" — that
   sentence has cost this codebase real time.

---

## 15. Living document

This file IS subject to change, but only via explicit edits proposed by
the user. An AI agent does not silently update the conventions. If a
convention turns out to be wrong or insufficient, raise it in
conversation; if the user agrees, edit this file in a dedicated commit
(`docs: clarify Layer-2 error-return contract`).

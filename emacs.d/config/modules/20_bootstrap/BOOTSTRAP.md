# Bootstrap Subsystem Conventions

This document is the **complete** ruleset for the bootstrap subsystem —
everything in `modules/20_bootstrap/`. It is self-contained: it bundles
the general code conventions that apply here plus the bootstrap-specific
discipline. There is nothing else you need to read to work in this
folder.

If you are an AI coding agent editing any file under `20_bootstrap/`:
**this document is the rule set. Read it in full before changing code.**

For non-bootstrap configuration (feature modules at `30_*`, `40_*`,
etc.), see [`../../CONVENTIONS.md`](../../CONVENTIONS.md). The rules
THERE are looser; the rules HERE are deliberately stricter because the
bootstrap manages external state and silent failures are catastrophic.

---

## 1. Why bootstrap is treated specially

The bootstrap subsystem provisions external state: macOS Keychain
entries, the cloned data folder on disk, the `gh` CLI's authenticated
session, the brew-installed Emacs binary, the LaunchAgent plist. None
of this is internal Elisp state — every value involved lives outside
Emacs and survives across launches.

This creates four concerns that feature modules do not face:

| Concern | Why it matters in bootstrap |
|---|---|
| **Idempotency** | The bootstrap runs on every Emacs launch. The second run, the tenth run, must produce the same final state as the first. |
| **Race conditions** | Provisioning code shells out to `security`, `gh`, `git`, `brew`. Parallel invocations are common; their interleaving must not corrupt state. |
| **Partial-failure survivability** | If the user closed Emacs mid-bootstrap last time, the next run picks up cleanly from any half-state. |
| **Silent-failure prevention** | The user cannot "see" Keychain or daemon state — if the bootstrap thinks the data folder is healthy when it isn't, the user finds out only when Org-mode can't find its files. |

These four concerns are the reason the bootstrap subsystem earns the
extra structural discipline below. Feature modules face none of them
and stay flat (per `CONVENTIONS.md`).

---

## 2. Three-layer architecture

All bootstrap code is organised into three layers. **Layers are
physical file boundaries**, not just conceptual groupings; the layer
is encoded in the filename (see §3) so a file's role is visible
without opening it.

```
LAYER 1 — System primitives          (filename prefix 20.01.NN)
  One file per kind of resource (Keychain, git, gh, process, file).
  Each function wraps ONE external command or OS call
  (`security`, `git`, `gh`, `call-process`, `file-exists-p`).
  Returns `:ok` / `:error` with a message, or a string/nil for
  read primitives. No business logic. No inter-file dependencies
  inside Layer 1.
  Target size: 30–100 lines per file. Hard ceiling: 150.
  Loads FIRST (lowest numeric prefix in the bootstrap range).

LAYER 2 — Domain operations          (filename prefix 20.02.NN)
  One file per domain concept (secrets, repo, identity, daemon, …).
  Each function describes ONE thing from the user's world: "is the
  data folder healthy?", "is the API key set?". Composes Layer-1
  primitives, returns structured results. Knows nothing about UI or
  user interaction. MAY mutate the state it is responsible for
  ensuring (e.g. `my/data-dir-resolve' may setq `my/data-dir`).
  Target size: 50–150 lines per file. Hard ceiling: 200.

LAYER 3 — Business logic             (filename prefix 20.03.NN)
  One main file. Defines the public entry point the rest of the
  system calls (`my/bootstrap`). Reads top-to-bottom like
  pseudo-code: ensure A, ensure B, ensure C. No system calls, no
  string-mangling — only calls into Layer 2.
  Target size: 50–200 lines. Hard ceiling: 300.
  Loads LAST (highest numeric prefix in the bootstrap range).
```

**The strict rule: Layer N may only call Layer N−1.**

- Layer 1 never calls Layer 2 or Layer 3.
- Layer 2 never calls Layer 3.
- If you ever feel like calling "upward", the abstraction is wrong —
  stop and discuss.

**Why these specific ceilings.** The rewrite is a reaction to the
legacy `20_bootstrap.org` at ~4000 lines, which silently bundled
Keychain primitives, Bitwarden integration, git-crypt handling,
GitHub identity, a form widget, the orchestrator, and starter-data
generation in one file. That structure produced race conditions
and silent failures that took days to debug. Tight per-file ceilings
make the bundling impossible to repeat.

---

## 3. File numbering scheme

The filename prefix has THREE numeric segments separated by dots:

```
   20 . LL . SS _name.org
   │    │    │
   │    │    └── sub-index (01, 02, …) — order within the layer
   │    └────── layer (01 = Layer 1, 02 = Layer 2, 03 = Layer 3)
   └─────────── subsystem (20 = bootstrap; sits between the
                pre-init modules at 00_/10_ and the feature
                modules at 30_ and beyond)
```

`config.org`'s discovery loop sorts files by `string<`, which gives
the load order:

```
00_…  →  10_…  →  20.01.NN  →  20.02.NN  →  20.03.NN  →  30_…  →  …
```

The bootstrap loads AFTER `00_startfirst.org` (theme, elpaca) and
`10_tasks.el` (async-tasks framework), and BEFORE the feature
modules at `30_` and up. Within the bootstrap, Layer-1 primitives
load first, then Layer-2 domain operations, then the Layer-3 main
file.

**Example shape** (illustrative, not prescriptive):

```
20.01.01_bootstrap_<resource-1>.org    ← Layer 1 primitive
20.01.02_bootstrap_<resource-2>.org    ← Layer 1 primitive
20.02.01_bootstrap_<domain-1>.org      ← Layer 2 domain operation
20.02.02_bootstrap_<domain-2>.org      ← Layer 2 domain operation
20.03.01_bootstrap.org                 ← Layer 3 main entry
```

Adding a new file within a layer takes the next sub-index
(`20.02.NN+1_…`). Inserting between two existing files is
intentionally awkward — it forces a renumbering discussion instead
of silent ambiguity.

**The layer is visible in the filename. There is no other way to
tell which layer a file belongs to.** A file at `20.02.NN_*` is
Layer 2 by definition; if it acts like Layer 1 or Layer 3, the
filename is wrong, not the rule.

**Filename word separator: underscore (`_`).** Match the rest of
the repo. Symbol names in Elisp keep their kebab-case convention
(`my/data-dir-resolve`); only filenames use underscores.

---

## 4. Public contract with the rest of the codebase

The bootstrap exposes exactly these symbols to feature modules:

| Symbol | Type | Used by |
|---|---|---|
| `my/data-dir` | defvar, absolute string path OR `:not-resolved` sentinel | `30_core`, `40_org`, `50_apple_reminders`, `60_emacs-agent-runtime`, `70_wiki`, `80_gtd` (~40 call sites) |
| `my/api-key-fetch` | function `(KEY-NAME) → string or nil` | `60_emacs-agent-runtime` (6 call sites) |
| `my/bootstrap-ready-p` | function `() → t / nil` | guard around path-dependent setup in every feature module |
| `my/bootstrap` | interactive command | M-x by the user to re-run the orchestrator |
| `my/api-key-set` | interactive command | M-x focused on API key rotation |
| `my/credential-set` | interactive command | M-x form over every bootstrap credential |

Everything else inside the bootstrap is implementation detail.
Feature modules do NOT see, reference, or depend on:

- Keychain accessors (`my/keychain-get`, `my/keychain-set`, …)
- git / gh / git-crypt / repo-clone helpers
- The credential descriptors / store routine
- Orchestrator internals (`my/bootstrap--ensure-steps`, halting,
  formatting)
- Any internal `:not-resolved` handling beyond the published
  contract on `my/data-dir`

**Changing the public contract requires updating all callers in the
same commit.** Adding a new public function is fine when there's a
real need; introducing a new public symbol that's only needed once
is not — wrap the use-site instead.

---

## 5. Forbidden patterns

These patterns are explicitly forbidden in the bootstrap subsystem.
Each one cost real debugging time in the legacy implementation;
re-introducing any of them is regression.

1. **No shared mutable probe-cache.** Do not introduce a global
   plist that one early step fills and later steps read from. This
   was the legacy `my/-bootstrap-probe-data` antipattern. It caused
   the parallel `multi-get` race, the misleading "data folder
   already a clone" cascade, and several other silent-failure
   classes. Each `ensure-*` reads its own state fresh at call time.

2. **No auto-fired background tasks at boot.** The legacy bootstrap
   spawned `distro-config-update` and `emacs-daemon-service-setup`
   as fire-and-forget on every launch. These produced
   non-deterministic log noise and "did it run yet?" debugging
   sessions. Background tasks fire only from explicit user
   commands.

3. **No multi-tier secret-source fallback.** Keychain is the single
   source of truth. There is no Bitwarden-fallback, no env-var
   fallback, no on-demand fetch tier. If a credential is missing,
   the bootstrap returns `(:error MSG)` with the exact `security
   add-generic-password` line the user should run.

4. **No backward-compat shims for credential or schema changes.**
   When the credential layout changes, ship only the new shape.
   Old Keychain entries stay where they are; the user cleans them
   up when they want to.

5. **No silent skip.** A function that decides "nothing to do"
   returns `:skip` and logs nothing. A function that decides
   "cannot proceed" returns `(:error MSG)`. A function NEVER
   returns `nil` to mean "I gave up because something looked
   wrong" — that's the silent-failure mode this document is
   designed to prevent.

6. **No widget forms.** User input goes through `read-string` /
   `read-passwd` / `completing-read`. The 460-line legacy widget
   form stays retired.

---

## 6. Required patterns

These patterns ARE required in the bootstrap subsystem (general code
rules below also apply on top):

1. **`provide` at the end of each file, `require` at the top of any
   file that uses the provided feature.** Even though `config.org`'s
   discovery loop loads files in numeric order, explicit
   `require` / `provide` documents the dependency graph and protects
   against future re-ordering. The provided symbol matches the
   feature, e.g., `(provide 'my-bootstrap-keychain)` for the
   keychain Layer-1 file.

2. **`declare-function` for every cross-file call.** Layer 2 files
   declare the Layer 1 functions they use. Layer 3 declares the
   Layer 2 functions it uses. Missing declarations produce
   byte-compiler warnings, which are our signal of accidental
   cross-layer leaks.

3. **Each `ensure-*` returns exactly one of:** `:done`, `:skip`, or
   `(:error MSG)`. This is the universal contract for Layer-2
   operations. No exceptions, no "also returns the value on
   success".

   Layer-1 wrappers around external commands return:
   - `:ok` / `(:error MSG)` for write/action commands
   - `string` or `nil` for read commands
   - Custom result symbols when the operation has more than two
     outcomes (e.g. `my/gh-auth-status` returns `:ok`,
     `:not-authenticated`, `:no-gh`, or `(:error MSG)`)

4. **`(:error MSG)` payloads carry the literal repair command** the
   user can paste into Terminal. For Keychain misses:
   ```
   FIX: security add-generic-password \\
          -s emacs_credentials -a <ACCOUNT> \\
          -w "<value>"
   ```
   The Layer-3 `my/bootstrap--halt` block displays the error
   payload verbatim in the *Warnings* buffer.

5. **`cl-defstruct` for any structured result that crosses a file
   boundary.** Raw plists or alists do not cross files in this
   subsystem — they are too easy to typo and the compiler cannot
   help.

---

## 7. File header (mandatory)

Every file starts with this block, as Elisp comments inside the
first `#+begin_src emacs-lisp` block:

```elisp
;;; 20.LL.SS_bootstrap_FEATURE.el --- One-line description -*- lexical-binding: t -*-
;;
;; Public API (callable from Layer N+1):
;;   (my/feature-foo ARG)        → return value type / meaning
;;   (my/feature-bar)            → t / nil
;;
;; Internal (DO NOT call from other files; prefix with `--'):
;;   my/feature--baz
;;   my/feature--cache
;;
;; Depends on (declared with `declare-function' below):
;;   my/other-feature-thing     ← 20.XX.YY_bootstrap_other-feature
```

The header is contract documentation. Update it in the same commit
that changes the public API or the internal list.

---

## 8. Naming convention

Elisp has no language-level access control; we enforce visibility
**socially** through naming + cross-file declarations:

| Form | Meaning |
|---|---|
| `my/feature-bar` (single dash before name) | Public. Callable from any file. |
| `my/feature--baz` (double dash) | Private. Only this file may call. |
| `my/--utility-fn` | Repo-wide private utility. Rare; prefer file-local. |

**Calling a `--`-prefixed symbol from another file is forbidden.**
If you need it from outside, promote it to a single-dash name AND
update the file header's Public API section, OR wrap it in a new
public function.

Symbol names keep kebab-case (`my-bootstrap-keychain`,
`my/bootstrap-ready-p`). Only filenames use underscores.

---

## 9. Idempotency contract

Every `ensure-*` and every operation that mutates external state
MUST satisfy:

> Running the function twice produces the same final state as
> running it once. The second call is a no-op.

Concrete rules:

1. **Read fresh state at point of use.** Each `ensure-*` reads what
   it needs from the source of truth at the moment it runs. No
   shared probe-data plist.

2. **No mutable shared globals between operations.** If two
   functions need the same external information, both read it
   fresh. The cost (a few extra system calls) is negligible; the
   correctness gain is total.

3. **Return a structured result, not a side effect.** Use the
   tagged-result conventions in §6.3. Low-level functions never
   call `display-warning` or `message` themselves — they return
   facts. Only the Layer-3 orchestrator surfaces them.

4. **State-checking predicates must agree with state-mutating
   writes.** If `my/foo-exists-p` returns `t`, a subsequent
   `my/foo-create` MUST return `:skip` (not `:done`, not an
   error). Test both directions.

---

## 10. Error handling

Three error categories. Every failure is classified into one of them;
returning bare `nil` is not acceptable.

| Category | When | What the function does |
|---|---|---|
| **Expected: nothing to do** | Pre-condition already satisfied. | Return `:skip`. |
| **Expected: cannot proceed** | A required input is missing (no credential, no network, etc.). The user can fix it. | Return `(:error "human message including the next action to take")`. |
| **Unexpected: system fault** | A system call failed in a way the function did not anticipate. | Let it signal an Elisp error (`(error …)`). Do not swallow with `condition-case` at Layer 1 or Layer 2. |

The Layer-3 orchestrator wraps the orchestrator body in
`condition-case` and turns uncaught errors into a structured result
for the user. This keeps the user out of the debugger but preserves
the traceback in `*Messages*`.

---

## 11. Code style

- **No comments by default.** Identifier names and structure carry
  the meaning. Add a comment only when the *why* is non-obvious — a
  hidden constraint, a subtle invariant, a workaround for a
  specific bug. Never explain *what* the code does.

- **No clever one-liners.** `let*` bindings with descriptive names
  beat anonymous sub-expressions.

- **Avoid quoted lambdas (`'(lambda …)`).** Use `(lambda …)`
  directly. Emacs 27+ warns; it is wrong for byte-compilation.

- **All `#+begin_src emacs-lisp` blocks in `.org` files inherit
  `:tangle yes`** from the file's `#+PROPERTY` header. A block
  silently dropped from tangle output is a silent corruption that
  breaks the entire module.

- **`lexical-binding: t`** on every file's first-line comment.

Function size: 5–15 lines for ordinary operations. The Layer-3
orchestrator entry point and step-list defvars can be longer
because they read like manifests.

---

## 12. Object-oriented patterns (Elisp idioms)

Priority order:

1. **`cl-defstruct` for data shapes.** Whenever you pass around a
   bag of named fields. Avoid raw plists for cross-file data.

2. **`cl-defgeneric` + `cl-defmethod` for polymorphism.** When you
   need backend dispatch (e.g., Keychain backend vs env-var
   backend). Avoid if/cond chains keyed on a symbol.

3. **Plain `defun` + plain `defvar` for everything else.**

**Avoid EIEIO** unless a clear inheritance hierarchy is needed —
overkill for everything in the current bootstrap.

**Avoid closures for state-hiding** — `--`-prefixed naming is
simpler and equally effective for the threat model.

---

## 13. Refactoring rules

1. **No backward-compat shims when changing data shapes.** Ship the
   new shape only. Applies to credentials, plist schemas, file
   formats — everything.

2. **No autonomous side effects.** Background tasks fire only on
   explicit user command.

3. **Check existing community tools before building custom
   infrastructure.** Search for an existing solution before writing
   more than ~50 lines of custom plumbing (`auth-source`,
   `aio.el`, `exec-path-from-shell`, …).

4. **Minimal scope per task.** When asked to do X, do only X.

---

## 14. Verification before commit

```
1. Tangle: org-babel-tangle-file on the .org → produces fresh .el
2. Byte-compile: emacs --batch -L modules -L modules/20_bootstrap \
                       -f batch-byte-compile <file>.el
   → no NEW warnings
3. Paren balance: emacs --batch ... '(check-parens)' → 0
```

For race-condition / concurrency fixes, **build a shell-level
synthetic reproduction first** that demonstrates the bug
deterministically. The test for `my/keychain-multi-get` (100/100
corrupt before fix → 0/100 after) is the model — see commit
`3c09a91`.

For integrated bootstrap tests:

```bash
emacs --batch -Q -L ~/.emacs.d/config/modules/20_bootstrap \
  --eval '(progn
            (load "20.01.01_bootstrap_keychain" nil t)
            (load "20.01.02_bootstrap_git" nil t)
            (load "20.01.03_bootstrap_gh" nil t)
            (load "20.02.01_bootstrap_repo" nil t)
            (load "20.02.02_bootstrap_repo_clone" nil t)
            (load "20.02.03_bootstrap_secrets" nil t)
            (load "20.02.04_bootstrap_identity" nil t)
            (load "20.03.01_bootstrap" nil t)
            (message "my/bootstrap-ready-p = %S" (my/bootstrap-ready-p)))'
```

Expected output on a populated Mac:
```
Bootstrap: data-folder resolution=done; data-folder clone=skip;
           github identity=skip; secrets readable=done
my/bootstrap-ready-p = t
```

---

## 15. Branch strategy

| Branch | Role |
|---|---|
| `main` | Active development. |
| `stable` | Frozen known-good snapshots. |
| Tags | Semver on stable. |

**Default for an AI session:** push to `main` only. Never touch
`stable`, never create tags, and never force-push unless explicitly
asked.

---

## 16. Commit conventions

- Prefixes: `fix:`, `feat:`, `refactor:`, `perf:`, `cleanup:`,
  `docs:`. Scope: `fix(bootstrap):`, `perf(loader):`.
- Title ≤ 70 chars; details in body.
- Body explains the WHY, not the WHAT.
- Always include `Co-Authored-By:` footers for AI-assisted commits.
- Confirm before risky operations (force-push, reset --hard,
  delete branches/tags).

---

## 17. Legacy file

`20_bootstrap.org.old` at the repo's modules level (NOT inside this
subdirectory) is the retired pre-rewrite monolith. The `.old` suffix
makes the discovery loop skip it. Kept on disk for history lookups
(e.g. how the old form widget worked); never loaded.

The matching tangled `20-bootstrap.el` was deleted at rewrite time.

---

## 18. Lessons encoded (commits worth reading)

If you are writing new bootstrap code and find yourself about to do
something that resembles one of these, **stop and re-read the
relevant commit before proceeding.**

| Commit | Lesson |
|---|---|
| `3c09a91` | `my/keychain-multi-get` race — three-write subshells interleave, corrupting the parallel-read alist. Rule encoded: §5.1 (no probe-cache) and §6.5 (cl-defstruct for cross-file data). |
| `fc9a1df` | Step 3's misleading "BW missing username/repo" warning when Keychain had every value. Rule encoded: §5.1 (no shared cache) and §5.5 (no silent skip). |
| `49cba8f` | `git pull --ff-only` race against itself when install.sh and the bootstrap distro-updater both ran. Rule encoded: §5.2 (no auto-fired background tasks). |
| `8d70142` | `/Applications/Emacs Plus.app` placement creating duplicate Launchpad icons. Rule encoded: general "one source of truth" principle. |
| `90f6242` | LIBRARY_PATH unset for libgccjit at LaunchAgent daemon start. Rule encoded: §6.4 (forward-declare environment dependencies before any consumer fires). |

When in doubt, read the commit body. The legacy rationale is in
git history; the current rules are what was learned from it.

---

## 19. AI working conventions

When an AI agent picks up a task in this subsystem:

1. **Read this file first.** Then read the file header of any
   file you are about to change.

2. **State your plan in one sentence before editing.** "I'll add
   `my/git-crypt-unlock` to Layer 1 with the same buffer-merge
   pattern as the existing primitives." The user can correct
   course before tool calls.

3. **Minimal-scope edits.** Do not refactor adjacent code on the
   side.

4. **No new abstractions without explicit request.** Helper
   functions added "to make this cleaner" rarely pull their
   weight.

5. **Confirm before destructive actions.** Removing files,
   renaming functions used in other files, dropping support for a
   credential shape — all require explicit user approval.

6. **Verify before claiming success.** "Test passed" must be
   backed by an actual command run in the session, with output
   shown.

7. **Honest reports of failure.** Report exact errors. Do not
   paper over with "should work now".

---

## 20. Living document

This file is updatable but only via explicit edits proposed by the
user. An AI agent does not silently change the conventions. If a
convention turns out to be wrong, raise it in conversation; if the
user agrees, edit in a dedicated `docs(bootstrap): …` commit.

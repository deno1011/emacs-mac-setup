# Bootstrap Subsystem Conventions

This document covers rules that apply **only** to the bootstrap
subsystem — the files matching `20.LL.SS_bootstrap-*.org` under
`emacs.d/config/modules/`. General code rules live in
[`CONVENTIONS.md`](CONVENTIONS.md) and apply on top of everything
here; subsystem rules never replace general rules, only add to them.

If you are an AI agent editing a `20.LL.SS_bootstrap-*.org` file:
**read `CONVENTIONS.md` first, then this file.**

---

## 1. Why bootstrap is treated specially

The bootstrap subsystem provisions external state: macOS Keychain
entries, the cloned data folder on disk, the gh CLI's authenticated
session, the brew-installed Emacs daemon binary, the LaunchAgent
plist. None of this is internal Elisp state — every value involved
lives outside Emacs and survives across launches.

This has consequences that feature modules (Org, gptel, GTD, etc.)
do not have to deal with:

| Concern | Why it matters in bootstrap |
|---|---|
| **Idempotency** | The bootstrap runs on every Emacs launch. The second run, the tenth run, must produce the same final state as the first. |
| **Race conditions** | Provisioning code calls out to `security`, `gh`, `git`, `brew`. Parallel invocations are common; their interleaving must not corrupt state. |
| **Partial-failure survivability** | If the user closed Emacs mid-bootstrap last time, the next run must pick up cleanly from any half-state. |
| **Silent-failure prevention** | The user has no way to "see" Keychain or daemon state — if the bootstrap thinks the data folder is healthy when it isn't, the user finds out only when Org-mode can't find its files. |

These four concerns are the reason the bootstrap subsystem earns the
extra structural discipline below. Feature modules do not face them
and stay flat (per `CONVENTIONS.md` §2).

---

## 2. Three-layer architecture

All bootstrap code is organized into three layers. Layers are
physical file boundaries, not just conceptual groupings. **The layer
is encoded in the filename** (see §3) so a file's role is visible
without opening it.

```
LAYER 1 — System primitives (filename prefix 20.01.NN)
  One file per kind of resource (Keychain, git, process, file).
  Each function wraps ONE system call (`security`, `git`,
  `call-process`, `file-exists-p`). Returns `:ok` / `:error` with
  a message. No business logic. No inter-file dependencies inside
  Layer 1.
  Target size: 30–100 lines per file. Hard ceiling: 150.
  Loads FIRST (lowest numeric prefix in the bootstrap range).

LAYER 2 — Domain operations (filename prefix 20.02.NN)
  One file per domain concept (secrets, repo, identity, daemon, …).
  Each function describes ONE thing from the user's world: "is the
  data folder healthy?", "is the API key set?". Composes Layer-1
  primitives, returns structured results.
  Knows nothing about UI or user interaction.
  Target size: 50–150 lines per file. Hard ceiling: 200.

LAYER 3 — Business logic (filename prefix 20.03.NN)
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
- If you ever feel like calling "upward", that means the
  abstraction is wrong — stop and discuss.

**Why these specific ceilings:** the bootstrap rewrite is a
reaction to the legacy `20_bootstrap.org` at ~4000 lines, which
silently bundled Keychain primitives, Bitwarden integration,
git-crypt handling, GitHub identity, a form widget, the
orchestrator, and starter-data generation. That structure produced
race conditions and silent failures that took days to debug.
Tight per-file ceilings make the bundling impossible to repeat.

---

## 3. File numbering scheme

The filename prefix has THREE numeric segments separated by dots:

```
   20 . LL . SS _name.org
   │    │    │
   │    │    └── sub-index (01, 02, …) — order within the layer
   │    └────── layer (01 = Layer 1, 02 = Layer 2, 03 = Layer 3)
   └─────────── subsystem (20 = bootstrap; sits between the
                pre-init modules at 00- / 10- and the feature
                modules at 30- and beyond)
```

`config.org`'s discovery loop sorts files by `string<`, which gives
the load order:

```
00-…  →  10-…  →  20.01.NN  →  20.02.NN  →  20.03.NN  →  30-…  →  …
```

The bootstrap subsystem loads AFTER `00_startfirst.org` (theme,
elpaca) and `10_tasks.el` (async-tasks framework), and BEFORE the
feature modules at `30-` and up. Within the bootstrap, Layer-1
primitives load first, then Layer-2 domain operations, then the
Layer-3 main file. Each file `provide`s its feature; consumers in
higher layers `require` it. The declarative `require` graph
documents dependencies on top of the numeric ordering.

**Example shape** (illustrative, not prescriptive — the actual files
in each layer emerge from the rewrite as we identify the concerns):

```
20.01.01_bootstrap_<resource-1>.org    ← Layer 1 primitive
20.01.02_bootstrap_<resource-2>.org    ← Layer 1 primitive
20.02.01_bootstrap_<domain-1>.org      ← Layer 2 domain operation
20.02.02_bootstrap_<domain-2>.org      ← Layer 2 domain operation
20.03.01_bootstrap.org                 ← Layer 3 main entry
```

Adding a new file within a layer takes the next sub-index
(`20.02.NN+1_…`). Inserting a file between two existing ones is
intentionally awkward — it forces a renumbering discussion instead
of silent ambiguity.

**The layer is visible in the filename. There is no other way to
tell which layer a file belongs to.** A file at `20.02.NN_*` is
Layer 2 by definition; if it acts like Layer 1 or Layer 3, the
filename is wrong, not the rule.

---

## 4. The public contract with the rest of the codebase

The bootstrap exposes exactly **two symbols** to the rest of the
Emacs configuration:

| Symbol | Type | Used by |
|---|---|---|
| `my/data-dir` | string (existing directory path) | `30_core.org`, `40_org.org`, `50_apple_reminders.org`, `60_gptel.org`, `70_wiki.org`, `80_gtd.org` (~40 call sites) |
| `my/api-key-fetch` | function `(KEY-NAME) → string or nil` | `60_gptel.org` (6 call sites) |

Everything else inside the bootstrap is implementation detail.
Feature modules do NOT see, reference, or depend on:

- Keychain accessors (`my/keychain-get`, `my/keychain-set`, …)
- BW / git-crypt / gh-auth helpers
- Form widgets
- Orchestrator internals
- The probe-data plist (in any future form)

**Changing the public contract requires updating all callers in
the same commit.** Adding a new public function is fine when there's
a real need; introducing a new public symbol that's only needed once
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
   classes. Each `ensure-*` function reads its own state fresh at
   the moment it runs.

2. **No auto-fired background tasks at boot.** The legacy bootstrap
   spawned `distro-config-update` and `emacs-daemon-service-setup`
   as fire-and-forget on every launch. These produced
   non-deterministic log noise and "did it run yet?" debugging
   sessions. Background tasks fire only from explicit user
   commands (`M-x my/update-distro`, etc.).

3. **No multi-tier secret-source fallback.** Keychain is the single
   source of truth for secrets. There is no Bitwarden-fallback, no
   env-var-fallback, no on-demand-fetch tier. If a credential isn't
   in Keychain, the bootstrap returns
   `(:error "credential X missing; M-x my/set-credential X")` —
   it does not try four backends in sequence.

4. **No backward-compat shims for credential or schema changes.**
   When the credential layout changes, ship only the new shape.
   Old Keychain entries stay where they are; the user cleans them
   up if and when they want to.

5. **No silent skip.** A function that decides "nothing to do"
   returns `:skip` and logs nothing. A function that decides
   "cannot proceed" returns `(:error MSG)`. A function NEVER
   returns `nil` to mean "I gave up because something looked wrong"
   — that's the silent-failure mode the rest of this document is
   designed to prevent.

---

## 6. Required patterns

These patterns ARE required in the bootstrap subsystem (general
code-style requirements from `CONVENTIONS.md` apply on top):

1. **`provide` at the end of each file, `require` at the top of any
   file that uses the provided feature.** Even though `config.org`'s
   discovery loop loads files in numeric order, explicit
   `require`/`provide` documents the dependency graph and protects
   against future re-ordering.

2. **`declare-function` for every cross-file call.** Layer 2 files
   declare the Layer 1 functions they use. Layer 3 declares the
   Layer 2 functions it uses. Missing declarations produce
   byte-compiler warnings, which are our signal of accidental
   cross-layer leaks.

3. **`cl-defstruct` for any structured result that crosses a file
   boundary.** Raw plists or alists do not cross files in the
   bootstrap subsystem — they are too easy to typo and the
   compiler can't help.

4. **Each `ensure-*` function returns exactly one of `:done`,
   `:skip`, `(:error MSG)`.** This is the universal contract for
   Layer 2 and Layer 3 operations. No exceptions, no "also returns
   the value on success".

---

## 7. Legacy file

During the rewrite, the old `emacs.d/config/modules/20_bootstrap.org`
is renamed to `20_bootstrap.org.old`. The `.old` suffix removes the
`.org` extension that `config.org`'s discovery loop matches on, so
the file is preserved on disk for reference (history, lookup of how
the old form-widget worked, etc.) but never loaded into Emacs.

The matching tangled output `20_bootstrap.el` is deleted at the
same time. If the rewrite ever needs to be reverted (it won't, but
in principle), the procedure is: delete the new `20.LL.SS_*` files,
rename `20_bootstrap.org.old` back to `20_bootstrap.org`, re-tangle.

---

## 8. Anti-patterns from the legacy implementation

For the avoidance of doubt, these specific legacy patterns are
explicitly NOT to be reintroduced:

- A monolithic `20_bootstrap.org` file at >500 lines.
- A `my/-bootstrap-probe-data` plist or any equivalent shared
  mutable cache filled at startup and consumed by later steps.
- A widget-based interactive form spanning ~500 lines for setup —
  if user input is needed, use `read-string` / `read-passwd`
  prompts (~5 lines per field).
- A three-tier API-key fallback (BW → Keychain → on-demand).
- A `my/bootstrap-orchestrate` dispatcher with cond-based step
  routing and shared state passed through arguments.
- A `start-distro-config-update-task` / `start-daemon-service-task`
  pair fired from `(my/bootstrap)` at every Emacs launch.

Each of these was a sincere attempt to solve a real problem;
none of them survived contact with reality. The current rewrite
exists because removing each one in isolation would have been a
larger and more dangerous change than starting over.

---

## 9. Lessons encoded (commits worth reading)

These commits document the exact failure modes the rules above
prevent. If you are writing new bootstrap code and find yourself
about to do something that resembles one of these, **stop and
re-read the relevant commit before proceeding.**

| Commit | Lesson |
|---|---|
| `3c09a91` | `my/keychain-multi-get` race — three-write subshells interleave, corrupting the parallel-read alist. Rule encoded: §5.1 (no probe-cache) and §6.3 (cl-defstruct for cross-file data). |
| `fc9a1df` | Step 3's misleading "BW missing username/repo" warning when Keychain had every value the orchestrator needed. Rule encoded: §5.1 (no shared cache) and §5.5 (no silent skip). |
| `49cba8f` | `git pull --ff-only` race against itself when install.sh and the bootstrap distro-updater both ran. Rule encoded: §5.2 (no auto-fired background tasks). |
| `8d70142` | `/Applications/Emacs Plus.app` placement creating duplicate Launchpad icons because two install paths placed two apps. Rule encoded: general "one source of truth" principle. |

When in doubt, read the commit body. The legacy rationale is
preserved in git history; the current rules are what was learned
from it.

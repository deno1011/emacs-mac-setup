# Branch Status: feature/gptel

Status: superseded for current development.

This branch contains earlier gptel experiments for the public setup repository.
It was reviewed before starting the current agent-runtime work, but it should
not be used as the direct base for the next implementation steps.

## Why This Branch Is Superseded

- It contains useful gptel and Ollama experiments.
- It also changes several paths toward an older `~/emacs-config/org/` layout.
- The current live configuration uses the private repo layout:
  `~/emacs/config/` and `~/emacs/data/org/`.
- Continuing directly from this branch would mix useful gptel work with stale
  path/layout changes.

## Continuation Path

Current work continues in:

- `deno1011/emacs-mac-setup:gptel-agent-runtime`

This new branch incorporates the refined agentic logic and the Planner Loop while respecting the current private data repo layout.

If this branch is resumed later, first rebase it onto `stable` or start a fresh
setup branch from `stable`, then cherry-pick only the still-relevant gptel
changes.

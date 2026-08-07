# Agent Instructions

Instructions for coding agents (Cursor, Claude Code, Codex, etc.) working on
this repository. Treat this file as mandatory policy for every coding session.

## Understand Before You Code (MANDATORY)

Orient yourself before changing anything. Read in depth — don't skim.
Only read git-tracked files (skip `.gitignore` matches; use
`git ls-files` when unsure). Do not implement until these steps are done:

1. **Read `README.md`** — project overview and quick-start.
2. **Read `steering.md`** when present — project-specific directives for
   all agents and skills; keep that policy there, not in this file.
3. **Explore the codebase** — map the source tree, entry points, and
   where tests live before editing anything.
4. **Check git state** — run `git log --oneline -20` and
   `git status --short --branch`.


## Git Workflow

- Branch from `main` as `feature/<descriptive-name>`.
- **Never commit directly** to `main`.
- **Conventional commits:** `<type>: <description>` (e.g. `feat:`, `fix:`,
  `refactor:`, `docs:`, `test:`, `chore:`).
- **Commit discipline:** only commit files relevant to the current change.
- **Never add `Co-Authored-By` lines.** No AI attribution in commits — ever.
- **Feature branches are local-only** — do not push them to origin.
- **Land locally:** squash-merge the feature branch into `main`, then delete
  the feature branch.
- **Push only when asked.** Never force-push or amend unless explicitly
  requested. Only `main` is pushed to the remote.

## Scope Discipline

- Focus on one coherent change per session.
- Do not include unrelated "while here" fixes.
- Priority: fix broken behavior before adding new behavior.

## Session Completion

A session is not complete until:

1. Verification passes with no regressions — use the project's documented
   test/lint commands (see `README.md`); if none exist, say so and skip.
2. Changes are committed with a clear conventional commit message.
3. The feature branch is squash-merged into `main` locally and deleted.
4. `git status` shows a clean working tree.
5. You provide a brief handoff note summarizing what was done and what remains.

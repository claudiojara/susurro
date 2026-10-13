# Susurro: agent instructions

Native Swift macOS dictation app. Source of truth for the plan: `openspec/changes/dictation-mvp/tasks.md` (SDD change
`dictation-mvp`, hybrid store: openspec files plus engram project `susurro`).

## When the user says "continúa" / "sigue" / "continue"

Resume the plan without asking what to do:

1. Sync: `git checkout main && git pull --ff-only`. If open PRs exist (`gh pr list`), finish them first: wait for green
   CI, then squash-merge.
2. Recover context: engram `mem_context` for project `susurro`, then read `tasks.md`.
3. Pick the next PR in `tasks.md` order whose tasks are still `- [ ]` (manual VERIFY items that need a person, such as
   WS5.8, do not block: list them for the user and move on).
4. Run it through the SDD workflow (`~/.claude/skills/_shared/sdd-orchestrator-workflow.md`): delegate the apply to an
   `sdd-apply` agent (Strict TDD with Swift Testing, stacked PRs under 800 authored lines each), then review with the
   lens triage (full 4R over 400 changed lines), delegate the fixes, and merge once CI is green.
5. Keep chaining to the next PR until a decision needs the user. Delegate design doubts to a Fable agent at xhigh
   effort instead of stopping.
6. Report briefly in Spanish (no voseo): what merged, what is next, and anything the user must test by hand.

## Rules

- GitHub account: `claudiojara`. Prefix every `gh` and `git push` with `GH_TOKEN=$(gh auth token --user claudiojara)`.
  Never run `gh auth switch`.
- Conventional commits, no AI attribution in commits. PR bodies end with the Claude Code footer.
- Authorized: merge PRs once CI is green (squash, delete the branch).
- Artifacts, code, comments and PRs in English.
- `make lint test build` is the local gate; `make run` launches the app. Rebuilding with an ad hoc signature makes
  macOS forget the Microphone and Accessibility grants (see `docs/running.md`).
- `docs/research/` is local only and never committed or referenced in public artifacts.

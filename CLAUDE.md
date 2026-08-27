@AGENTS.md

## Claude Code specifics

- Always-on rules live in `.claude/rules/` (auto-loaded): verification bar and the privacy invariant. Everything else is read-on-demand from `.claude/docs/` — open the one file the task needs, don't bulk-read the directory.
- **Compact work:** invoke the in-repo `midnight-compact` skill for patterns (its `examples/` are compiler-validated — start from the closest one, e.g. `rock-paper-scissors.md` for commit-reveal; its `reference/gotchas.md` before debugging), and use the Midnight Expert plugins' compile/verify loop for anything generated — model priors about this language are unreliable; the compiler is the referee. If the plugin isn't installed yet, install it first (command in AGENTS.md §Setup).
- **UI work:** read `.claude/docs/design.md` first, build with tokens only, then run `scripts/design-gate.sh` and include its output in your summary. A red gate is a finding, not an obstacle — fix the system value, don't exempt the screen.
- **Contract changes:** recompile before claiming done; paste the compiler result. Simulator tests accompany every circuit change.
- Machine-local pointers (research corpus, local search index, private notes) live in `CLAUDE.local.md` — gitignored, may be absent on other machines; never move its contents into tracked files.

## Bootstrap checklist (delete this section once the scaffold exists)

1. `compact update`, then `compact compile --version` (the compile syntax is already pinned in AGENTS.md §Commands, confirmed against official Midnight CI).
2. Start local net (`midnight-local-dev`), confirm node/indexer/proof-server ports respond.
3. Scaffold `contracts/slip.compact` (commit–reveal skeleton per `.claude/docs/architecture.md`) until it compiles clean — this is day-one done.
4. `swift package init` MidnightKit + Rust staticlib target per `.claude/docs/midnightkit.md`.
5. Xcode app target `Slip/` with the token set from `.claude/docs/design.md` as `DesignTokens.swift`.

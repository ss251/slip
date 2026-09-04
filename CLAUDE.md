@AGENTS.md

## Claude Code specifics

- Always-on rules live in `.claude/rules/` (auto-loaded): verification bar and the privacy invariant. Everything else is read-on-demand from `.claude/docs/` — open the one file the task needs, don't bulk-read the directory.
- **Compact work:** use the Midnight Expert plugins as the single path — `compact-core` skills for patterns and `compact-core:compact-dev` to write, then `/midnight-verify` for anything generated. Model priors about this language are unreliable and examples anywhere (ours, upstream, or official) may predate the installed language version; the compiler is the only referee. We deliberately do **not** vendor a community Compact skill: it duplicated a slice of the official suite with pre-0.26 examples and needed a companion note explaining where it was wrong — a reference that needs correcting is a liability.
- **UI work:** read `.claude/docs/design.md` first, build with tokens only, then run `scripts/design-gate.sh` and include its output in your summary. A red gate is a finding, not an obstacle — fix the system value, don't exempt the screen.
- **Contract changes:** recompile before claiming done; paste the compiler result. Simulator tests accompany every circuit change.
- Machine-local pointers (research corpus, local search index, private notes) live in `CLAUDE.local.md` — gitignored, may be absent on other machines; never move its contents into tracked files.


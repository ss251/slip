# Midnight tooling — mandatory, not optional

Three sources must be live and used for any Midnight/Compact work. None is a
nice-to-have; skipping them is how this repo previously shipped stale facts.

## 1. kapa MCP (`mcp__midnight__search_midnight_knowledge_sources`)

**Consult it before asserting anything Midnight-specific.** Model priors on this
ecosystem are unreliable and the SessionStart hook says so explicitly.

It is project-scoped in `.mcp.json`, so it **only binds in a session launched from
this repo** — `cd ~/Developer/slip && claude`. A session started elsewhere has no
kapa, and subagents inherit the parent's binding, so spawning one is not a
workaround (verified 2026-09-03).

If you are in a session without it, you have two honest options: relaunch, or run a
headless query from the repo —

```
claude -p "<question>" --allowedTools "mcp__midnight__search_midnight_knowledge_sources"
```

The `--allowedTools` flag is required; without it the call is blocked on a
permission prompt headless mode cannot answer.

Keep it current: `claude mcp list` from the repo must show `midnight … ✔ Connected`.

## 2. Midnight Expert plugins

`midnight-expert`, `compact-core`, `compact-examples`, `midnight-tooling`,
`midnight-verify`. The single documented path for Compact: write with
`compact-core:compact-dev`, then verify with `/midnight-verify` — the agents compile
and execute against the real compiler rather than recalling syntax.

Update from remote before a build session:

```
claude plugin marketplace update midnight-expert
claude plugin update <plugin>@midnight-expert     # for each of the five
```

## 3. MIDSKILLS (`.agents/skills/`, symlinked into `.claude/skills/`)

30 community skills — Compact, on-chain logic, midnight-js, indexer, RPC, wallets,
security, storage, transactions, plus worked example dApps. Pinned by commit in
`.agents/skills/SOURCE.md`; `scripts/freshness-gate.sh` warns when upstream moves.

Re-vendor with `npx skills add Kali-Decoder/Midnight-skills -y`, then update the
commit in SOURCE.md.

**Read its LOCAL DELTA before trusting an example.** Its Compact samples declare
`language_version >= 0.22`; we build on 0.23.0.

## The rule that outranks all three

**The compiler is the referee.** kapa, the Expert plugins and MIDSKILLS are all
hints. Anything generated goes through `/midnight-verify` and an actual compile
before it is believed or shown to the user. Compilation alone is not correctness —
code must compile *and* execute.

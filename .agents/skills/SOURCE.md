# Vendored: MIDSKILLS (Midnight Skills)

- **Upstream:** https://github.com/Kali-Decoder/Midnight-Skills
- **Pinned at commit:** `295089ff1dcb1c8101c677ae1d87609131cfa0bd`
- **Vendored:** 2026-09-03 via `npx skills add Kali-Decoder/Midnight-skills -y`
  (the `skills` CLI is `vercel-labs/skills`, verified before install)
- **Layout:** 30 skills in `.agents/skills/`, symlinked into `.claude/skills/` so
  Claude Code discovers them. One upstream repo, one commit — hence one SOURCE.md
  for the set rather than 30 copies.

## Why it is here

The one-stop community knowledge layer for Midnight: Compact language, on-chain
logic, midnight-js, indexer, RPC, wallets, security, storage, transactions, plus
a dozen worked example dApps.

## LOCAL DELTA — read before trusting an example

Its Compact examples declare `pragma language_version >= 0.22`; **we build on
language 0.23.0** (compiler 0.31.1, runtime 0.16.0, ledger 8). The pragma is a
`>=` bound so those examples still compile, but they predate our language and may
use superseded idioms.

**The compiler is the referee, not this skill set.** Anything generated from these
examples goes through `/midnight-verify` before it is believed. The same rule that
got the ADAvault skill removed from this repo applies here: a stale reference is
worse than none if it is trusted blindly.

Check freshness by COMMIT against upstream HEAD, never by a version file —
`scripts/freshness-gate.sh` does this automatically.

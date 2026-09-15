# Compact crib

Working notes for Midnight's contract language. The compiler is the referee — model priors are unreliable here; when in doubt, compile a micro-contract (the Midnight Expert plugin's verify loop does exactly this).

## Mental model (one line)

`secret → witness → circuit → assert → disclose() → ledger`
Private data enters via **witnesses** (implemented host-side, returning `[newPrivateState, value]`), circuits run locally and prove themselves, `assert` gates validity, and **only what passes through `disclose()` reaches the public ledger**.

## Program anatomy

```compact
pragma language_version >= 0.23;      // verified 2026-08-31 on compiler 0.31.1 / language 0.23.0
import CompactStandardLibrary;         // always

export ledger round_commitments: ...;  // public, on-chain state
witness playerPick(): ...;             // private input, host-implemented

export circuit sealPick(...): [] {
  // compute commitment from witness…
  round_commitments = disclose(commitment);   // deliberate + commented
}
```

- All ledger state is on-chain and public whether or not it is exported; `export` on a ledger field only generates the JS/TS binding so a host can read it back by name. `export circuit` = externally callable; plain circuits are internal.
- The compiler emits TypeScript types + zkir + proving keys per circuit; keep generated artifacts in `build/` (tracked or LFS'd — decide at first compile).
- Toolchain via the `compact` CLI (`compact update` to switch versions). Pin the exact compile command in AGENTS.md once verified.

## Patterns Slip depends on

- **Commit–reveal:** commitment = hash/commit over `{choice, salt}` (stdlib provides persistent/transient commit + hash primitives — check current names in the stdlib reference before use). Reveal circuit re-derives and asserts equality. The RPS example in the official samples is the canonical tiny version of this pattern.
- **One seal per member per round:** a `seals: Map` keyed on the public member id, reset each round via `seals.resetToDefault()` and guarded by `assert(!seals.member(publicMemberId))`. This is a reset-per-round guard, not a Zswap-style nullifier.
- **Deadline discipline:** seal circuits assert before-deadline; reveal circuits assert after. Time source = ledger/block context, not device clock.
- **Membership (optional v1.5):** Merkle root of crew in ledger; membership witness proves inclusion without listing members.

## Rules that bite

- Every witness-derived value that reaches ledger state **must** pass `disclose()` — the compiler enforces awareness; our repo adds a comment per disclose (see `.claude/rules/privacy.md`).
- No floats; integer types are sized (`Uint<n>`) — size them to the domain, they cost circuit rows.
- Circuit size ⇒ k ⇒ params size and proving time. Slip's circuits measure k13-k14 (`sealPick` is k=14); if a change balloons constraints, stop and re-budget (`midnightkit.md`).
- Keep circuits few: every exported circuit is another proving key users may need.

## Version discipline (enforced, not remembered)

`scripts/freshness-gate.sh` is the source of truth. Two rules it encodes, both learned the hard way:
- **The compiler decides the runtime version, not npm.** Pin `@midnight-ntwrk/compact-runtime` to `compact compile -- --runtime-version`. npm `latest` runs ahead of released compilers; a doc's hardcoded ceiling is written against *its* compiler, not yours.
- **A vendored example is a pattern, not a fact.** Examples drift against the language in both directions — many are written for 0.26+, which our supported 0.23 compiler rejects outright. The compiler is the referee; the Midnight Expert verify loop is how you ask it.

## References (fetchable as raw markdown)

- Docs index for agents: `https://docs.midnight.network/llms.txt` — every page below it serves plain `.md`.
- Compact language + stdlib reference: `https://docs.midnight.network/compact` (stdlib exports page lists commit/hash/token primitives with signatures).
- Tutorials worth mirroring: the bulletin-board series (contract → API → deploy) and the private-party tutorial in the official docs; `midnightntwrk/example-bboard`; the awesome-dapps list for sample contracts (RPS commit-reveal, prediction-market sample).
- Midnight Academy (free, account-gated): 101/201/301 courses + a Wallet SDK course — the 301 track builds a full DApp end to end.

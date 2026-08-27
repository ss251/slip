# Architecture

## System shape

```
iPhone (SwiftUI app)
 ├─ Slip UI  ── tokens/design system, no color/type literals
 ├─ MidnightKit (Swift + Rust staticlib)
 │    ├─ witness store   {choice, salt} — encrypted, device-only
 │    ├─ prover          Compact circuits proved ON DEVICE (no proof server)
 │    └─ params/keys     fetched on demand + cached (k≈10 needs ~200KB BLS params)
 └─ chain client ── submits {commitment, proof}; reads contract state via indexer

Midnight network (dev: `undeployed` local trio)
 └─ slip.compact — ONE contract: rounds, commitments, deadline, reveals, scores
```

The defining decision: **standard Midnight apps delegate proving to a proof server, which necessarily receives witness data. Slip's prover runs on the phone**, so the privacy claim ("nobody can see a sealed pick") is architecturally true, not policy-true.

## Contract interface (target shape — keep circuits few and small)

- `createSlip(question_commit, deadline, crew_root)` — steward opens a round.
- `sealPick(round, commitment)` — commitment = binding+hiding commit over `{choice, salt}`; one per member per round (nullifier prevents double-seal).
- `reveal(round, choice, salt)` — accepted only after deadline AND only if it re-derives the stored commitment.
- `settle(round, outcome)` — steward-only; scores computed from verified reveals.

Constraints that shape this design:
- **No contract-to-contract calls on the network yet** → everything above lives in one contract.
- Circuit size stays small (k≈10 class) → proving in ~100ms-class on device and tiny params. Don't add circuit complexity without re-checking `midnightkit.md` budgets.
- Public ledger state is public: question commitment, seal commitments, reveal results, scores. Sides are hidden **until reveal, then public to the crew and chain** — that's the product contract, don't accidentally promise more.

## Crew membership & invites (v1)

Invite link carries the contract address + round id (+ crew secret for membership proof if enabled). No backend service in v1: rendezvous is the chain itself; the app polls the indexer for roster/reveal state. Push/notifications come later and must not require witness-adjacent data.

## Disclosure ledger

Everything that intentionally becomes public, in one place. Update this list with every `disclose()`:

| What | When | Why |
|---|---|---|
| Seal commitment | on seal | binds the pick without revealing it |
| Choice + salt | on reveal (after deadline) | the whole point — verified against the seal |
| Outcome + scores | on settle | shared result |

## Local development

`undeployed` network via midnight-local-dev: node `ws://localhost:9944`, indexer `http://localhost:8088/api/v4/graphql`, proof server `http://localhost:6300`. The proof server exists for tooling/CLI parity only — the app path must never depend on it. Preprod/testnet deploys are a milestone step, not the daily loop.

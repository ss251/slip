# Slip — agent guide

Sealed group predictions with friends. Everyone commits a hidden pick to a shared question; picks are cryptographically sealed on each person's iPhone and revealed simultaneously at a deadline. Nobody — friends, servers, or the app's authors — can peek or edit a sealed pick, and that claim is proved, not promised.

Built on [Midnight](https://docs.midnight.network) (a privacy blockchain whose Compact language compiles to zero-knowledge circuits) with **on-device proof generation** via MidnightKit, our Swift/Rust proving layer.

**Status:** pre-alpha, building in the open (Wave 1 milestone: 2026-09-16). Expect scaffolding to land fast; this file is the map.

## Tech stack

- **iOS app** — Swift 6 / SwiftUI, iOS 17+ baseline with iOS 26 features (Liquid Glass chrome) where available.
- **MidnightKit** — Swift package wrapping Rust (`midnight-zk`, `midnight-ledger`) as a static library for `aarch64-apple-ios(-sim)`; runs the Compact JS runtime under JavaScriptCore. Proofs are generated on the phone; no proof server.
- **Contract** — one Compact smart contract (`contracts/slip.compact`): commit–reveal with per-round nullifiers. A compiling contract is the heartbeat of this repo; never merge with a broken compile.
- **Local network** — Midnight `undeployed` mode for all development: node `ws://localhost:9944`, indexer `http://localhost:8088/api/v4/graphql`, proof server `http://localhost:6300` (used by tooling only — the app itself never calls one).

## Repository layout (target)

```
contracts/        slip.compact + compiled artifacts (TS types, zkir, keys)
MidnightKit/      Swift package: prover FFI, key/params management, wallet (later)
Slip/             SwiftUI app
scripts/          design-gate.sh, install-hooks.sh (run once: wires pre-push gates)
docs/design/      the eight target screens as PNGs — UI work matches these, pixel-close
docs/how-slip-works.html  interactive end-to-end explainer (self-contained)
.claude/docs/     deep references — read the relevant one before working in that area
.claude/skills/   in-repo Compact skill (validated examples + gotchas)
```

## Setup

1. Compact toolchain: install the `compact` CLI, then `compact self update && compact update`. Verified stack as of 2026-08-31: **CLI 0.5.2 · compiler 0.34.0 · language 0.26.0 · ledger 9.1.0.0-rc.3 · runtime 0.19.0**. The toolchain moves fast and breaks — re-run `compact check` / `compact self check` before a build session, and treat any pre-0.26 language example (including vendored ones) as suspect until it compiles.
2. Local network + proof server: Docker-based `midnight-local-dev` (see `.claude/docs/resources.md`).
3. Xcode 26 / Swift 6 toolchain; Rust with `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets for MidnightKit work.
4. AI assistance: install the official **Midnight Expert** plugins (`claude plugin marketplace add https://midnightntwrk.expert`) — they verify generated Compact against the real compiler. This repo also ships a knowledge skill at `.claude/skills/midnight-compact/` (vendored from adavault/midnight-skill, MIT): 30 compiler-validated example contracts — including commit-reveal and prediction-market shapes — plus a long gotchas reference. Use the skill for patterns, the plugin for verification. The docs index for LLMs is `https://docs.midnight.network/llms.txt`.

## Commands

Canonical shapes (compile syntax confirmed against official Midnight CI and the vendored skill; CI pins the toolchain via `midnightntwrk/setup-compact-action`, version in `.github/workflows/ci.yml`):

- Compile contract: `compact compile contracts/slip.compact build/slip` (sanity: `compact compile --version`)
- Contract tests: simulator-based TS tests (see `.claude/docs/testing.md`)
- App build/tests: `xcodebuild -scheme Slip test` (snapshot tests need a booted iOS 26 simulator)
- Design gate (run on any UI diff): `scripts/design-gate.sh Slip/`

## Hard constraints — do not design around these, design *with* them

- **Single contract.** The network does not support contract-to-contract calls yet (arriving in a future quarter). Everything lives in one Compact contract.
- **The witness never leaves the device.** A pick is `{choice, salt}` witness data. It must never be logged, sent, persisted unencrypted, or included in analytics (there are none). Only the zero-knowledge proof and the commitment travel. This is the product; treat any violation as a release blocker.
- **Wave 1 is unitless.** No tokens, no stakes, no monetary value — points and banter only. Do not add value transfer without reading `.claude/docs/roadmap.md`.
- **Reveals must verify.** A reveal that doesn't match its commitment is rejected by the contract, not smoothed over by the client.

## Conventions

- **Design:** every color/type/spacing value comes from the token set in `.claude/docs/design.md` — no literals in views. 44×44pt minimum hit regions, Dynamic Type support, Reduce Motion fallbacks. One accent (seal red) with one meaning. `scripts/design-gate.sh` enforces the mechanical subset.
- **Swift:** Swift 6 strict concurrency; SwiftUI-first; no third-party UI dependencies without discussion.
- **Compact:** every witness-derived value written to ledger goes through `disclose()` deliberately — each `disclose` gets a one-line comment saying what is being revealed and why that's intended.
- **Commits:** conventional, atomic (`feat(contract): …`, `fix(kit): …`). PRs describe *what changed and how it was verified*.

## Testing

Evidence over assertion, always: paste command output, not "should work." Layers: contract simulator tests (happy path, adversarial, and privacy-leak probes) → Rust/Swift FFI round-trip tests → snapshot tests (iOS 26: render via `drawHierarchyInKeyWindow`, mark suites `@Suite(.serialized)`) → an on-device proving benchmark. Details: `.claude/docs/testing.md`.

## Deep references (read on demand, not preemptively)

| File | Read before… |
|---|---|
| `.claude/docs/product.md` | changing UX, copy, or scope |
| `.claude/docs/architecture.md` | touching data flow, contract interface, or sync |
| `.claude/docs/compact.md` | writing/reviewing any Compact |
| `.claude/docs/midnightkit.md` | FFI, proving, keys/params, performance work |
| `.claude/docs/design.md` | any UI work (tokens, laws, motion, gate) |
| `.claude/docs/testing.md` | adding features (tests land with them) |
| `.claude/docs/resources.md` | needing official docs/examples/community tools |
| `.claude/docs/roadmap.md` | scoping questions, milestone planning |

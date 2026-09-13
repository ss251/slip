# Slip — agent guide

Sealed group predictions with friends. The current app proves a single-player local round: enroll, create, seal, reveal, settle and dispute. The circuit checks that an opening matches the original commitment. Invite import adopts local metadata only: the steward must enroll a member before the round opens, and tapping a link does not establish on-chain membership. Connected crews are planned; a shared deadline creates an opening window, not guaranteed simultaneous arrivals. The proof does not establish that nobody saw an unlocked phone.

Built on [Midnight](https://docs.midnight.network) (a privacy blockchain whose Compact language compiles to zero-knowledge circuits) with **on-device proof generation** via MidnightKit, our Swift/Rust proving layer.

**Status:** pre-alpha, private repository being prepared for public release (Wave 1 milestone: 2026-09-16). Publication remains owner-controlled; this file is the map.

## Tech stack

- **iOS app** — Swift 6 / SwiftUI, iOS 17+ baseline with iOS 26 features (Liquid Glass chrome) where available.
- **MidnightKit** — Swift package wrapping Rust (`midnight-zk`, `midnight-ledger`) as a static library for `aarch64-apple-ios(-sim)`; runs the Compact JS runtime under JavaScriptCore (verified 2026-09-04 — see `.claude/docs/midnightkit.md`). Proofs are generated on the phone; no proof server.
- **Contract** — one Compact smart contract (`contracts/slip.compact`): commit–reveal with per-round nullifiers. A compiling contract is the heartbeat of this repo; never merge with a broken compile.
- **Local network** — Midnight `undeployed` mode for all development: node `ws://localhost:9944`, indexer `http://localhost:8088/api/v4/graphql`, proof server `http://localhost:6300` (used by tooling only — the app itself never calls one).

## Repository layout

```
contracts/        slip.compact; build/ generated JS, ZKIR and keys; test/ Node referee
MidnightKit/      Swift package: thread-confined JS runtime and native local prover
Slip/             SwiftUI app: App/, DesignSystem/, Models/, Screens/, Sealing/
SlipTests/        Swift Testing suites and 120 key-window PNG references
project.yml       XcodeGen source of truth; Slip.xcodeproj/ is generated and ignored
scripts/          design/freshness/handoff gates, hooks, captures, app parameter staging
SECURITY.md       privacy invariant, release blockers and private reporting
CONTRIBUTING.md   development workflow, verification gates and contribution rules
docs/design/v6/   30 canonical app-rendered boards; earlier versions are historical
docs/how-slip-works.html  interactive planned connected-flow explainer
docs/phase4-sources.md   kapa, Expert/MIDSKILLS and executable-reference evidence
.claude/docs/     deep references; .claude/rules/ includes privacy and mandatory tooling
.agents/skills/   vendored MIDSKILLS; read SOURCE.md LOCAL DELTA first
handoff/          ignored live work order, state, heartbeat and owner-only requests
```

## Setup

1. Compact toolchain: install the `compact` CLI, then `compact self update && compact update`. Verified stack as of 2026-08-31: **CLI 0.5.2 · compiler 0.31.1 · language 0.23.0 · ledger 8 · runtime 0.16.0** — the stack Midnight's networks actually run. Newer compilers exist (0.34.0 / ledger 9) but no public network supports them yet, so building on them means no deployable target. The toolchain moves fast and breaks. **`scripts/freshness-gate.sh` enforces this** (pre-push + CI): it fails on drift we control — a `compact-runtime` pin that isn't what our compiler emits, a CI pin that isn't the local compiler, a pragma above the installed language, docs advertising a stack we no longer run — and warns when the compiler, CLI, or a vendored skill has moved upstream. Rule it encodes: **the compiler decides the runtime version, not npm** (`compact compile -- --runtime-version`).
2. Local network + proof server: Docker-based `midnight-local-dev` (see `.claude/docs/resources.md`).
3. Xcode 26 / Swift 6 toolchain; Rust with `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets for MidnightKit work.
4. MCP servers (docs + source lookup): committed in `.mcp.json`, so nothing to install — but they bind at session start, and the Midnight/kapa one needs a one-time OAuth via `/mcp` that its docs page omits. See `.claude/docs/resources.md` §MCP servers.
5. AI assistance: install the official **Midnight Expert** plugins (`claude plugin marketplace add https://midnightntwrk.expert`) — they verify generated Compact against the real compiler. They are the single documented path for Compact work: 15 focused skills (security, privacy/disclosure, ledger, witness-ts, circuit costs, patterns, language ref, debugging), an examples plugin, and verification agents that compile and execute against the real compiler rather than recalling syntax. The docs index for LLMs is `https://docs.midnight.network/llms.txt`.

## Commands

Canonical shapes (compile syntax confirmed against official Midnight CI and the vendored skill; CI pins the toolchain via `midnightntwrk/setup-compact-action`, version in `.github/workflows/ci.yml`):

- Freshness/drift check: `sh scripts/freshness-gate.sh` (add `--no-network` for a fast local-only run)
- Compile contract: `compact compile contracts/slip.compact contracts/build` (sanity: `compact compile -- --version`; add `--skip-zk` while iterating; only when contract/artifact changes are authorized)
- Contract tests: simulator-based TS tests (see `.claude/docs/testing.md`)
- App preparation: `sh scripts/prepare-app-params.sh /path/to/existing/params` stages checksum-verified k13/k14 public files without network; then `xcodegen generate`.
- App build/tests: `xcodebuild -scheme Slip -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` (serialized key-window snapshots; dated iOS 27.0, 18.6 and 17.5 evidence and limits are in `docs/runtime-compatibility.md`; those runs do not validate later changes)
- Design gate (run on any UI diff): `scripts/design-gate.sh Slip/`

## Hard constraints — do not design around these, design *with* them

- **Single contract.** Cross-contract calls exist in Compact 0.33.0+ but not on any network we can reach, and not in our compiler (0.31.1). Midnight DevRel, 2026-08-31: "0.34.0 is not currently supported by our networks... we are steadily working towards making contract to contract calls available to everyone." We use none of it, and a cross-contract-reachable circuit cannot call witnesses anyway — ours must.
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

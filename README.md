# Slip

Sealed predictions with friends. Pick a side, keep it hidden, then prove that your opening matches your seal.

Slip is an iOS pre-alpha for the AkinDo Buildathon, Wave 1 (2026-09-16). The current app is an **offline, single-player local round**: real Compact execution and native proof generation, with no wallet, transaction submission, indexer or connected crew. Group play is the product being built, not a shipped network feature.

Built on [Midnight](https://docs.midnight.network) and [Compact](https://docs.midnight.network/compact), using the `midnightntwrk` cryptography and ledger libraries through **MidnightKit**, our Swift/Rust layer.

## Try the local round

1. Create a question with two sides and hold to seal a pick. Enrollment, creation and sealing are proved locally.
2. Open the local sample. This explicitly advances a sample clock to the opening window; it does not change the device clock or open a shared round early.
3. Call the outcome after the sample's opening window. Reveal, settlement and an optional challenge each execute the existing circuit and produce a native proof.
4. See the public opening, outcome, local score and per-step timings. A challenge voids the outcome; the original opening remains intact.

The actor retains the original device secret and pick only in memory. The circuit re-derives the same salt for reveal and rejects a flipped pick. Before opening, the pick is hidden by its commitment. On reveal the choice is deliberately public; the secret and derived salt stay local. There is no remote proving fallback, analytics or persistence. **Terminating the app loses this local session.** A proof of a matching opening is not a claim that nobody saw the unlocked phone.

## Evidence, not a proof-server demo

`ContractRuntime` executes compiler-generated JavaScript under JavaScriptCore. `Prover.prove(circuit:proofData:)` converts the private runtime transcript to a preimage in memory and generates the proof natively. Runtime input is never written out by the app.

Historical physical-device benchmark (2026-09-03, iPhone 15 Pro/A17 Pro): `sealPick` proving-key load **24 ms**, proof generation **1,776 ms**, **4,480 bytes**, peak RSS **290 MB**. This is the real k14 circuit, not the earlier tiny-circuit benchmark. Source: [MidnightKit measurements](.claude/docs/midnightkit.md). No physical-device run was performed for the current app changes.

Current app gate (2026-09-05, iPhone 17 Pro simulator / iOS 27): **34 tests passed**, including six real-circuit proving cases, the complete lifecycle, and circuit-level mismatch rejection followed by recovery. One complete-round run measured:

| Circuit | Prepare / replay | Key load | Prove | Proof bytes |
|---|---:|---:|---:|---:|
| `enrollMember` | 16.9 ms | 14 ms | 466 ms | 4,480 |
| `createSlip` | 23.3 ms | 14 ms | 471 ms | 4,480 |
| `sealPick` | 26.9 ms | 27 ms | 827 ms | 4,480 |
| `reveal` | 29.1 ms | 28 ms | 1,073 ms | 4,480 |
| `settle` | 30.7 ms | 14 ms | 820 ms | 4,480 |
| `dispute` | 33.6 ms | 14 ms | 584 ms | 4,480 |

These are single-run observations on the host CPU, not phone latency promises or a performance budget. Preparation includes runtime initialization and replay of accepted steps; key/prove durations come from `Proof`. Reproduce the public-only `LOCAL_ROUND_PROOF` measurements with `LocalRoundServiceTests`. Local execution/proving does **not** establish network acceptance. Source decisions and version caveats: [Phase 4 sources](docs/phase4-sources.md).

## Build and test

Swift 6/SwiftUI, an iOS 17 deployment target, and Liquid Glass where available. Current verification uses Xcode 27 beta and the iPhone 17 Pro iOS 27 simulator. iOS 17/26 runtime behavior and archive compatibility still need owner validation; the deployment setting alone is not compatibility evidence.

Prerequisites: Xcode, XcodeGen 2.45+, Compact compiler **0.31.1** (language **0.23.0**, runtime **0.16.0**, ledger **8**), Node/npm, generated contract artifacts, and the matching simulator native archive. No network services are needed to run the local app.

**Fresh-clone limitation:** the native archive and its external Rust source are not distributed by this repository yet. `MidnightKit/Vendor/libslip_prove_ffi.a` and generated `contracts/build/` artifacts are ignored. Obtain the matching build inputs from the maintainer; CI's missing-archive warning/skip is not a passing MidnightKit test.

With the build inputs available:

```sh
sh scripts/install-hooks.sh
# Only if the simulator archive is missing, with the external prover source available:
# sh scripts/sync-prover.sh aarch64-apple-ios-sim

# On a fresh checkout, generate contracts/build using the pinned compiler:
cd contracts
npm ci
npm run build
node test/link-build.mjs
cd ..

# Existing official public parameter files, not a server or witness export:
sh scripts/prepare-app-params.sh /path/to/existing/params
xcodegen generate
xcodebuild -scheme Slip -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
scripts/design-gate.sh Slip/
cd MidnightKit
xcodebuild test -scheme MidnightKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Parameter staging checks the official k13/k14 SHA-256 values and has no download fallback. Open the generated `Slip.xcodeproj`, choose Slip and a simulator, then Run. Repository signing uses personal team `L594CGSH6A`; contributors must use their own authorized signing configuration for any later device work.

## Design and documentation

The [30 v5 boards](docs/design/v5/) map to 24 routes and state variants. Snapshot tests use serialized key-window rendering, 1× standard-range PNGs, light/dark, XL, AX1 and AX5. The 120 references total **11,566,897 bytes** after pixel-identical lossless compression; the comparison threshold remains **0.012**. Re-recording is explicit; see [testing](.claude/docs/testing.md).

The [interactive explainer](docs/how-slip-works.html) distinguishes the current local build from the planned connected flow. It is an illustration, not a transaction receipt.

Agents and contributors: start with [AGENTS.md](AGENTS.md), then the relevant `.claude/docs/` reference. Midnight-specific work requires kapa, Midnight Expert and MIDSKILLS, plus compiler/test verification. Commits must include their source and gate evidence. Private owner handoffs are intentionally not published.

## License

Apache-2.0

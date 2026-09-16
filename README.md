# Slip

Sealed predictions with friends. Pick a side, keep it hidden, then prove that your opening matches your seal.

Slip is an iOS pre-alpha for the AkinDo Buildathon, Wave 1 (2026-09-16). By default, the app runs an **offline, single-player local round** with real Compact execution and native proof generation. Experimental undeployed-network components can also assemble and prove `sealPick` on device for handoff to a trusted developer relay. Connected crews are not shipped, and an authenticated physical-iPhone → relay → devnet run has not yet been demonstrated.

Built on [Midnight](https://docs.midnight.network) and [Compact](https://docs.midnight.network/compact), using the `midnightntwrk` cryptography and ledger libraries through **MidnightKit**, our Swift/Rust layer.

<table>
  <tr>
    <td><img src="docs/design/v6/01-home.png" width="220" alt="Design preview of the Slip home feed"></td>
    <td><img src="docs/design/v6/04-sealed-ticket.png" width="220" alt="Design preview of a sealed ticket"></td>
    <td><img src="docs/design/v6/06b-verdict.png" width="220" alt="Design preview of a crew verdict"></td>
  </tr>
  <tr>
    <td align="center">seal on your phone</td>
    <td align="center">the proof travels, never the pick</td>
    <td align="center">opened together, called later</td>
  </tr>
</table>

Design previews of the intended crew flow. The sealed witness stays on device; a verified opening deliberately publishes the choice. For the current working loop and its evidence boundaries, use the [three-minute demo runbook](docs/demo.md).

## Try the local round

1. Create a question with two sides and hold to seal a pick. Enrollment, creation and sealing are proved locally.
2. Open the local sample. This explicitly advances a sample clock to the opening window; it does not change the device clock or open a shared round early.
3. Call the outcome after the sample's opening window. Reveal, settlement and an optional challenge each execute the existing circuit and produce a native proof.
4. See the public opening, outcome, local score and per-step timings. A challenge voids the outcome; the original opening remains intact.

The actor retains the original device secret and pick only in memory. The circuit re-derives the same salt for reveal and rejects a flipped pick. Before opening, the pick is hidden by its commitment. On reveal the choice is deliberately public; the secret and derived salt stay local. This default local flow has no remote proving fallback, analytics or pick persistence. The optional network path persists its device identity in Keychain and relay configuration in UserDefaults. **Terminating the app loses this local session.** A proof of a matching opening is not a claim that nobody saw the unlocked phone.

An incoming `slip://join/…` link currently imports public round metadata and may save
relay/contract setup. It does **not** enroll the device on chain, authenticate that
metadata, or rebuild the running sealing service. The steward must enroll each
member before opening the round; `enrollMember` rejects enrollment while a slip is
open. Share-invite UI and a complete connected join/reveal flow remain unimplemented.
A saved network configuration takes effect on a later launch, while local round
metadata remains session-only. Do not treat tapping an invite as proof of joining a
shared on-chain round.

The configured network component is still experimental: its adapter currently omits
the question commitment required by the app’s receipt validation, so submission can
be followed by a failed UI result. Confirmation is queried once and is not durably
reconciled. Component submission evidence below does not establish a working
connected app round.

## Native proof and network evidence

`ContractRuntime` executes compiler-generated JavaScript under JavaScriptCore. `Prover.prove(circuit:proofData:)` converts the private runtime transcript to a preimage in memory and generates the proof natively. Runtime input is never written out by the app.

Physical-device run (2026-09-05, iPhone 15 Pro / A17 Pro, iOS 26.6.1, this app build): the sealing and round-flow suites pass on the phone (13 tests, 2 suites) and the complete local lifecycle proves all six circuits with real, round-bound proofs (3 tests). Earlier standalone benchmark (2026-09-03, same phone): `sealPick` key load **24 ms**, prove **1,776 ms**, **4,480 bytes**, peak RSS **290 MB** — see [MidnightKit measurements](.claude/docs/midnightkit.md).

App runtime audit (2026-09-06, iPhone 15 Pro simulator / iOS 27.0, c4a043e): **96 tests in 19 suites passed after 130.395 seconds**, including six real-circuit proving cases, the complete lifecycle, circuit-level mismatch rejection followed by recovery, and the network-component boundary. One complete-round run on 2026-09-05 measured:

| Circuit | Prepare / replay | Key load | Prove | Proof bytes |
|---|---:|---:|---:|---:|
| `enrollMember` | 16.9 ms | 14 ms | 466 ms | 4,480 |
| `createSlip` | 23.3 ms | 14 ms | 471 ms | 4,480 |
| `sealPick` | 26.9 ms | 27 ms | 827 ms | 4,480 |
| `reveal` | 29.1 ms | 28 ms | 1,073 ms | 4,480 |
| `settle` | 30.7 ms | 14 ms | 820 ms | 4,480 |
| `dispute` | 33.6 ms | 14 ms | 584 ms | 4,480 |

Same lifecycle on the physical iPhone 15 Pro (iOS 26.6.1), one run, `LocalRoundServiceTests` on device:

| Circuit | Execute | Key load | Prove | Proof bytes |
|---|---|---|---|---|
| `enrollMember` | 15.6 ms | 13 ms | 777 ms | 4,480 |
| `createSlip` | 22.2 ms | 13 ms | 779 ms | 4,480 |
| `sealPick` | 28.4 ms | 26 ms | 1,493 ms | 4,480 |
| `reveal` | 27.9 ms | 26 ms | 1,845 ms | 4,480 |
| `settle` | 34.5 ms | 13 ms | 1,046 ms | 4,480 |
| `dispute` | 38.9 ms | 16 ms | 1,016 ms | 4,480 |

Physical-device component run (`NetworkSealingServiceTests`, iPhone 15 Pro, stub relay): `sealPick` executed against an embedded post-create contract state in **9 ms**, then assembled and proved in process in **1,641 ms**, producing a **5,238-byte** proved/pre-binding transaction. The planted device-secret pattern was absent from the handed-off bytes. The stub only acknowledged submit and confirm; this run had no HTTP relay, steward wallet, node or indexer.

Authenticated host relay demo (2026-09-05): a fresh local contract was deployed and prepared, Slip's native prover assembled the 5,238-byte `sealPick` transaction in **1,107 ms**, and the proved/pre-binding bytes crossed the bearer-authenticated steward relay. The node returned `SucceedEntirely` at block 2128; relay confirmation and an independent indexer read both found the exact expected commitment. This establishes the host producer → authenticated relay → local devnet path, not physical-iPhone provenance. The tooling proof service handled setup calls and the wallet's separate DUST balancing transaction; Slip's `sealPick` proof came from the native prover. See [Phase 6 sources](docs/phase6-sources.md) and [Phase 7 sources](docs/phase7-sources.md).

Both tables are single-run observations (host CPU, then the phone), not latency promises or a performance budget. Preparation includes runtime initialization and replay of accepted steps; key/prove durations come from `Proof`. Reproduce the public-only `LOCAL_ROUND_PROOF` measurements with `LocalRoundServiceTests`. Local execution/proving does **not** establish network acceptance. Source decisions and version caveats: [Phase 4 sources](docs/phase4-sources.md).

## For judges: architecture and Midnight integration in ten minutes

**One contract, two ledgers.** [`contracts/slip.compact`](contracts/slip.compact) declares the public ledger state — round `status`, `questionCommit`, the four deadlines, `roundId`, the `crew` set, `seals: Map<memberId, commitment>`, `reveals`, the two tallies, `outcome`, `disputedBy` — and exactly two witnesses that make up the private state: `localSecretKey()` and `localPick()`. The pick's salt is not a witness; `pickSaltOf` derives it in-circuit from the device secret, so the host can never supply a weak one. Six circuits: `enrollMember`, `createSlip`, `sealPick`, `reveal`, `settle`, `dispute`. Every `disclose()` carries a comment saying what becomes public and why; the commitment itself is never disclosed, it becomes public by being written into `seals`.

**Proving happens on the phone.** MidnightKit links `midnight-zk` and `midnight-ledger` as a Rust static library for `aarch64-apple-ios` and runs the compiler's JavaScript output under JavaScriptCore. There is no proof server in the sealing path; the [architecture note](.claude/docs/architecture.md#system-shape) explains why that matters on mobile specifically and where the trust boundary sits. The [disclosure ledger](.claude/docs/architecture.md#disclosure-ledger) lists every data flow that leaves the device.

**Evaluate it.**

```sh
# 1. The technical gate: the contract compiles (compiler 0.31.1, language 0.23.0)
compact compile contracts/slip.compact contracts/build

# 2. Contract simulator tests, including the privacy-leak probe
(cd contracts && npm test)

# 3. The app and MidnightKit suites (real proofs for every circuit)
xcodebuild -scheme Slip -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -jobs 4 -parallel-testing-enabled NO test
```

CI runs the same three gates plus the design gate on every push; the run for the submitted commit is linked from the AKINDO entry. The [demo runbook](docs/demo.md) reproduces the video's local round tap by tap, and [`docs/phase7-sources.md`](docs/phase7-sources.md) is the dated evidence matrix for the relay and devnet claims. What is built and what is planned is stated plainly on the [How Slip works page](docs/how-slip-works.html).

## Build and test

Swift 6/SwiftUI, a **17.0 deployment minimum with simulator validation on iOS 17.5**, and Liquid Glass where available. **The Debug suite passed on iOS 27.0, 18.6 and 17.5.** Canonical pixel references belong to iOS 27.0.0: 97 tests passed with all 120 comparisons. iOS 18.6 and 17.5 each passed 96 tests with one explicit comparison skip naming the reference and running runtimes, and zero failures.

Both older runtimes have reviewed light/dark captures of the pre-iOS 26 material tab bar. The iOS 18.6 local rehearsal took 180.05 seconds. The iOS 17.5 local lifecycle reached standings in 180.07 seconds through accessibility presses and the unchanged timed seal action; its seal proof took **1.000 s**. Coordinate HID and scroll reachability were not verified by that harness. The physical iOS 26.6.1 results above cover proving components and the local lifecycle, not a full UI or signed archive audit. See [runtime compatibility](docs/runtime-compatibility.md) for the exact evidence and limits, and [contribution guidance](CONTRIBUTING.md#verify-the-change) for shared-machine build limits.

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
xcodebuild -scheme Slip -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -jobs 4 -parallel-testing-enabled NO test
scripts/design-gate.sh Slip/
cd MidnightKit
xcodebuild test -scheme MidnightKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -jobs 4 -parallel-testing-enabled NO
```

Parameter staging checks the official k13/k14 SHA-256 values and has no download fallback. Open the generated `Slip.xcodeproj`, choose Slip and a simulator, then Run. Repository signing uses personal team `L594CGSH6A`; contributors must use their own authorized signing configuration for any later device work.

To reproduce the host relay component after the generated artifacts, e2e dependencies,
native CLI and local Docker services are available:

```sh
(cd contracts && npm run devnet:up)
(cd contracts/e2e && npm ci)
node --test scripts/steward-relay.test.mjs
node scripts/phase7-live-relay-demo.mjs
```

The self-contained demo creates its bearer token internally and never prints it; the
operator-only serve mode instead prints a one-time setup token to its trusted local
terminal. The demo uses the proof service for contract setup and the wallet's separate
DUST proof, never for Slip's native `sealPick` proof. Set `SLIP_PROVE_CLI` only when the
native CLI is not at the documented default path. This host component test is not a
substitute for an authenticated physical-device run.

## Design and documentation

The [30 canonical v6 boards](docs/design/v6/) are losslessly compacted copies of the reviewed app snapshots, produced on 2026-09-05 after the Luma pass. They cover 24 routes plus three dark and three AX1 boards; v5 Paper boards are historical. Snapshot tests use serialized key-window rendering, 1× standard-range PNGs, light/dark, XL, AX1 and AX5. The 120 references total **11,138,645 bytes** after pixel-identical lossless compression; the comparison threshold remains **0.012**. Re-recording is explicit; see [testing](.claude/docs/testing.md).

The [How Slip works page](docs/how-slip-works.html) walks the flow with the app's own screens and states plainly what is built and what is planned. It is an illustration, not a transaction receipt.

See [CHANGELOG.md](CHANGELOG.md) for the dated Wave 1 capability history and its verification evidence.

Start with [CONTRIBUTING.md](CONTRIBUTING.md) for development and verification requirements, and [SECURITY.md](SECURITY.md) for the privacy invariant and private vulnerability reporting. [AGENTS.md](AGENTS.md) maps the repository and its deeper references. Midnight-specific work requires kapa, Midnight Expert and MIDSKILLS, plus compiler/test verification. Commits must include their source and gate evidence. Private owner handoffs are intentionally not published.

## Built with, credited

Slip is built on [Midnight](https://midnight.network). The pieces of the ecosystem it stands on, and their licenses, are listed in [NOTICE](NOTICE):

- **midnight-zk** and **midnight-ledger** (Apache-2.0) — the proving system and ledger 8 crates, linked into MidnightKit as a Rust static library for iOS.
- **Compact** compiler 0.31.1, `compact-runtime` 0.16.0 and **midnight-js** 4.1.1 (Apache-2.0) — the contract toolchain and the simulator and e2e dependencies.
- **Kuira SDK** by Kuira Labs (Apache-2.0) — the extracted Compact runtime bundle that MidnightKit runs under JavaScriptCore, with four local patches marked in the file.
- **midnight-node**, **indexer-standalone** and **proof-server** images — the local `undeployed` network used for development and the relay evidence; the app itself never calls a proof server.
- **Midnight Expert** plugins and the **kapa** documentation MCP (MIT), and **MIDSKILLS** by Kali-Decoder (MIT, vendored in `.agents/skills`) — used to write and verify Compact against the real compiler.

Built for the AKINDO Midnight Buildathon, Wave 1.

## License

Apache-2.0

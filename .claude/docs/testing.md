# Testing

Evidence over assertion. Every feature lands with its tests; every summary quotes real output.

## Layers

1. **Contract (simulator)** — TypeScript tests against the compiled contract using the Compact simulator, before any network:
   - happy path per circuit (seal → reveal → settle);
   - adversarial: double-seal (nullifier), reveal-before-deadline, reveal that doesn't match its seal, non-member seal, non-steward settle;
   - **privacy probes:** assert the raw choice/salt never appears in public state or emitted data for every hidden case;
   - property-style checks where cheap (score conservation across a round).
2. **MidnightKit** — Rust unit tests for FFI surface; Swift round-trip test (commit → proof → local verify); a *bench test* asserting proving-time and peak-RSS budgets per circuit (fails on regression, numbers in `midnightkit.md`).
3. **App (SwiftUI)** — unit tests for round state machine; snapshot tests for every screen in light theme + Dynamic Type XL.
   - iOS 26 gotcha: snapshots must render via `drawHierarchyInKeyWindow`, and snapshot suites are `@Suite(.serialized)` — parallel window access flakes.
   - Unreachable states get `#if DEBUG` launch arguments so tests/screenshots can force them.
4. **End-to-end (local net)** — against `undeployed`: two simulated devices complete a full round (create → both seal → deadline → reveal → settle). This is the demo-critical path; keep it green.
5. **Design gate** — `scripts/design-gate.sh Slip/` on any UI diff (see `design.md`).

## App-only simulator verification

The local app has no network or persistence path. Proof tests exercise both legal
picks against the bundled runtime and prover; snapshot data is explicitly synthetic.
Never capture a real user's private pick or pass witness data through launch flags.

Build/install the app on the simulator, then use the checked-in capture script:

```sh
xcodebuild -scheme Slip -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
sh scripts/capture-app-screens.sh /tmp/slip-screens
SLIP_CAPTURE_VARIANT=accessibility sh scripts/capture-app-screens.sh /tmp/slip-screens-ax
SLIP_CAPTURE_VARIANT=accessibility-max sh scripts/capture-app-screens.sh /tmp/slip-screens-ax5
```

Install the built `Slip.app` with `xcrun simctl install booted /path/to/Slip.app`
before capture. The script captures all 24 routes in light and dark using
`xcrun simctl io booted screenshot`. Accessibility variants also enable Reduce Motion,
reduced transparency and Increase Contrast. These initial-scroll captures do not
replace manual swipe, hold-cancellation, peek-release and inactive-scene checks.

After reviewing actual simulator pixels against the 30 v5 boards, deliberately
record the key-window references, then run again without recording:

```sh
TEST_RUNNER_SLIP_RECORD_SNAPSHOTS=1 xcodebuild -scheme Slip -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -scheme Slip -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The 120 references cover light, dark, XL, AX1 and AX5. Suites are serialized and
render through `drawHierarchyInKeyWindow`; only the explicit environment variable
opts into recording. Keep simulator capture and test runs sequential, not concurrent.
Runtime-specific coverage must be reported honestly: an iOS 27 test pass does not
establish iOS 17 deployment or iOS 26 Liquid Glass compatibility.

## Dependency pinning

Before installing the simulator harness, run `compact compile -- --runtime-version` and pin `@midnight-ntwrk/compact-runtime` to exactly that. Never `@latest`. A mismatch fails at contract load with `CompactError: Version mismatch`, and `scripts/freshness-gate.sh` fails the push before you get there.

## Loop

Daily work runs entirely on the local trio (node 9944 / indexer 8088 / proof server 6300 for tooling). Deploying to a public test network is a milestone event with its own checklist in `roadmap.md`, not part of the inner loop.

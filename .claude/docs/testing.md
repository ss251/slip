# Testing

Evidence over assertion. Every feature lands with its tests; every summary quotes real output.

## Layers

1. **Contract (simulator)** — TypeScript tests against the compiled contract using the Compact simulator, before any network:
   - happy path per circuit (seal → reveal → settle);
   - adversarial: double-seal (nullifier), reveal-before-deadline, reveal that doesn't match its seal, non-member seal, non-steward settle;
   - **privacy probes:** assert the raw choice/salt never appears in public state or emitted data for every hidden case;
   - property-style checks where cheap (score conservation across a round).
2. **MidnightKit** — Swift round-trip tests (commit → proof → local verify) and native lifecycle tests. Current suites record timings and check valid durations; they do not enforce per-circuit upper latency or peak-RSS budgets. Those performance gates are planned. Measurements in `midnightkit.md` are observations, not an automated regression gate; the Rust prover source is external, so this tree does not establish Rust unit-test coverage.
3. **App (SwiftUI)** — unit tests for round state machine; snapshot tests for every screen in light theme + Dynamic Type XL.
   - iOS 26 gotcha: snapshots must render via `drawHierarchyInKeyWindow`, and snapshot suites are `@Suite(.serialized)` — parallel window access flakes.
   - Unreachable states get `#if DEBUG` launch arguments so tests/screenshots can force them.
4. **Planned connected end-to-end gate (local net)** — against `undeployed`: two devices complete a full round (create → both seal → deadline → reveal → settle). This is a required future connected-flow gate, not a currently demonstrated app capability. Existing local proofs, host relay runs and phone stub-relay tests do not establish it.
5. **Design gate** — `scripts/design-gate.sh Slip/` on any UI diff (see `design.md`).

## September 14 static-review changes

The rejoin-identity, cached-ticket invalidation and bounded relay-response regressions
in `RoundJoinTests.swift` and `RelayBoundaryReviewTests.swift` were written during a
static-only review and have not been executed. Design/freshness gates establish only
source conventions and pinned versions. Historical runtime results below do not
validate these later changes. They need an explicitly authorized future runtime pass.

`NetworkSealAdapterTests.submittedReceiptReachesFlow` is also unrun. Its
`withKnownIssue` marks the adapter’s missing question commitment at the presentation
validation gate; proving and submission checks remain outside that marker. A future
suite result that reports this known issue is not evidence of a working connected
round. Establish real round binding before removing the marker.

The unrun `defaultSessionBoundsDrippingResponse` regression is separately opt-in via
`SLIP_TEST_RELAY_DEADLINES=1`: it uses a synthetic URLProtocol stream to exercise the
real 120-second resource timeout and has a three-minute test limit. Its presence or
normal-suite skip is not deadline-enforcement evidence.

## App-only simulator verification

The default local-round service does not submit transactions or persist private picks. The optional network service submits proved transactions to a steward relay, stores its identity root in Keychain and relay configuration in UserDefaults. These are separate paths. Local proof tests exercise both legal
picks and all six lifecycle circuits against the bundled runtime and prover. The
mismatch test flips only the reveal witness, expects circuit rejection, then checks
that replaying the accepted prefix allows the original opening. Local sample time
is explicit and is not evidence of network acceptance. See `docs/phase4-sources.md`.
Snapshot data is explicitly synthetic.
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
swift scripts/optimize-snapshots.swift
xcodebuild -scheme Slip -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The 120 references cover light, dark, XL, AX1 and AX5 at 1× standard range (8-bit),
with point/pixel dimensions asserted. The comparison threshold remains 0.012.
The compression script preserves decoded pixels, removes invalidated Apple iDOT
offset metadata, and enforces a total below 15 MB. Suites are serialized and
render through `drawHierarchyInKeyWindow`; only the explicit environment variable
opts into recording. Keep simulator capture and test runs sequential, not concurrent.
Runtime-specific coverage must be reported honestly: an iOS 27 test pass does not
establish iOS 17 deployment or iOS 26 Liquid Glass compatibility.

For the real-result view layouts, DEBUG-only fixtures seed synthetic public results
without executing or proving anything. Every capture displays a fixture banner.
Terminate between launches, choose light/dark and optionally add `--accessibility-max
--reduce-motion --reduce-transparency --contrast`:

```sh
xcrun simctl launch booted com.sailesh.slip --slip-local-fixture settled-won --screen 07-standings --appearance light
xcrun simctl io booted screenshot /tmp/slip-local-standings-light.png
```

Fixture values: `sealed`, `revealed`, `settled-won`, `settled-lost`, `disputed`,
`mismatch`, `parametersMissing`. No secret, salt or private choice is accepted from
launch arguments. `--preview` takes precedence and selects canonical board data.
Fixture screenshots establish layout only; the native circuit tests establish the
local behavior. Manual scroll/gesture checks remain a separate owner check.
Use `sh scripts/capture-local-results.sh /tmp/slip-results` for the 24 normal-size
light/dark captures, or prefix with `SLIP_CAPTURE_VARIANT=accessibility-max` for
the same routes with AX5 and all reduced-effects paths.

## Dependency pinning

Before installing the simulator harness, run `compact compile -- --runtime-version` and pin `@midnight-ntwrk/compact-runtime` to exactly that. Never `@latest`. A mismatch fails at contract load with `CompactError: Version mismatch`, and `scripts/freshness-gate.sh` fails the push before you get there.

## Loop

Daily work runs entirely on the local trio (node 9944 / indexer 8088 / proof server 6300 for tooling). Deploying to a public test network is a milestone event with its own checklist in `roadmap.md`, not part of the inner loop.

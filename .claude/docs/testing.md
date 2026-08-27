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

## Loop

Daily work runs entirely on the local trio (node 9944 / indexer 8088 / proof server 6300 for tooling). Deploying to a public test network is a milestone event with its own checklist in `roadmap.md`, not part of the inner loop.

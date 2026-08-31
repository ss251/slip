# MidnightKit — on-device proving layer

The moat and the hard engineering. Goal: a clean Swift package any iOS app could adopt; Slip is its first consumer.

## Verified feasibility (from our spike — treat as ground truth until re-measured)

- `midnight-zk` / `midnight-zkir` cross-compile to `aarch64-apple-ios` and `aarch64-apple-ios-sim` **with zero upstream patches**; real PLONK+KZG prove+verify ran in the iOS Simulator (~115 ms at k=5).
- Mac (arm64) bench as an upper-bound proxy: **k=13 ≈ 69 ms / 27 MB peak; k=15 ≈ 207 ms / 106 MB** — Slip's k≈10-class circuits are comfortably phone-sized.
- Params/keys: a k≈10 circuit needs only **~197 KB** of BLS params (`bls_midnight_2p10`); a full
  wallet-grade key set is ~32.7 MiB — fetch-on-demand + cache, never bundle the lot.
- **Slip's own circuits, measured from `build/slip` (not assumed):** 20.8 MB of prover keys across
  6 circuits, in two size classes — `sealPick` and `reveal` at 5.0 MB, the other four at 2.7 MB;
  verifier keys are 4 KB each; ZKIR is 8-16 KB per circuit. **`k` is not recorded in any artifact**
  (ZKIR is instruction-level JSON; k is chosen at key generation), so the "k≈10-class" label above
  is inherited from the spike's generic benchmarks and has never been measured for this contract —
  the 5.0 MB prover keys suggest it is higher. Treat 20.8 MB as the real number that matters: it is
  the on-device download, and it grows with every circuit added. Escrow was measured to roughly
  double it.
- Open: our compile emits **ZKIR v2** (`"version": {"major": 2, "minor": 0}`) while toolchain 0.33.0
  added ZKIR v3 support. Unclear whether v2 is the intended default for 0.34.0 — check before
  assuming the on-device prover must handle v3.
- The Compact JS runtime (`compact-runtime` IIFE) runs under **JavaScriptCore with a small Buffer shim** — no embedded Node, no QuickJS.
- Crypto stack is BLS12-381/JubJub (halo2-descended `midnight-proofs`).

## Build rules

- Rust staticlib with default features **off** — strip `reqwest`/`aws-lc`-class deps out of the iOS build or the lib balloons and drags in unwanted networking/TLS.
- Stable C ABI surface between Rust and Swift; Swift side is `async` and cancellable.
- Thread pool: cap rayon threads and pin QoS (`userInitiated`) — default pools invite priority inversion and, at high k, memory pressure (Jetsam). Watch peak RSS in the bench test on every change.

## Responsibilities (in order of build)

1. **Prover:** `commit(choice, salt) → (commitment, proof)` and `reveal(...) → proof` for slip.compact's circuits; local verify for tests.
2. **Params manager:** lazy download + integrity check + cache of per-circuit keys/params.
3. **Chain client:** submit tx via node, read state via indexer GraphQL.
4. **Key/identity (later):** WebAuthn PRF extension is available on iOS 18+ for passkey-derived keys (shipping precedent exists in Midnight's ecosystem wallets); Keychain-wrapped seed is the fallback path.

## Non-goals (v1)

No embedded wallet UI, no token transfers, no Android. Keep the package headless and small; the app owns UX.

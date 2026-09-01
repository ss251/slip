# MidnightKit — on-device proving layer

The moat and the hard engineering. Goal: a clean Swift package any iOS app could adopt; Slip is its first consumer.

## Verified feasibility (from our spike — treat as ground truth until re-measured)

- `midnight-zk` / `midnight-zkir` cross-compile to `aarch64-apple-ios` and `aarch64-apple-ios-sim` **with zero upstream patches**; real PLONK+KZG prove+verify ran in the iOS Simulator (~115 ms at k=5).
- Mac (arm64) bench as an upper-bound proxy: **k=13 ≈ 69 ms / 27 MB peak; k=15 ≈ 207 ms / 106 MB** — Slip's k≈10-class circuits are comfortably phone-sized.
- **`sealPick` is k=14 — measured, and the old k≈10 guess was wrong by 15x on params.**
  A k=14 circuit needs `bls_midnight_2p14` = **3.0 MB** of BLS params, not the ~197 KB a
  k=10 circuit needs. Params double per k (k10 197 KB, k13 1.5 MB, k14 3.0 MB, k15 6.0 MB)
  and are fetched from `https://srs.midnight.network/bls_midnight_2p{k}`.
- **Measured on host (M-series, release build) proving Slip's REAL sealPick circuit** with a
  real preimage exported from the simulator: **keygen 953 ms, prove 779 ms, proof 4480 bytes**.
  This is the first end-to-end proof of an actual Compact circuit here — everything before it
  was a 3-multiplication toy at k=5.
- **PROVEN ON iOS (simulator, iPhone 17 Pro, 2026-09-01).** Slip's real `sealPick`
  circuit, real proving keys, real witness data, inside the iOS runtime:
  **keygen 1050 ms, prove 968 ms, proof 4480 bytes, wall 2.02 s.** Only ~24% slower
  than host (779 ms), so the runtime itself costs little. The product's central
  claim — the proof is generated on the phone — is now demonstrated, not asserted.
- **Memory is the open risk: RSS 219 MB -> 448 MB across the prove.** That 229 MB
  delta is far above what the k=13/k=15 bracket suggested. Harmless on a simulator
  with the Mac's RAM; on a real iPhone, sustained 448 MB in a foreground app is
  Jetsam territory, especially mid-range hardware. Measure peak RSS *continuously*
  on device (sample during the MSM), not before/after — the peak is what Jetsam reacts to.
- **Load artifacts from the app bundle, never a host path.** `open()` on a host
  `/Volumes/...` path from inside the simulator sandbox **blocks forever**: 0% CPU,
  no crash, no timeout, all samples parked in `open`. It looks exactly like a
  pathologically slow prover and is not one. This cost hours; `sample <pid>` on the
  test host found it in seconds because simulator processes are native macOS
  processes. Fixtures now ship as test-bundle resources.
- **One Rust staticlib only.** Two libs that each pull `midnight-curves` both embed
  blst and collide on duplicate symbols when force-loaded. MidnightKit must expose
  prove/verify/keys from a single crate.
- **Toolchain trap:** Homebrew's rustc has no iOS targets; rustup's stable was too
  old for the ledger tree. Symptom is `can't find crate for core`, which blames the
  wrong thing. Pin via `rust-toolchain.toml` and keep rustup current.
- **Not a suspect: blst assembly.** Its `build.rs` selects asm on `CARGO_CFG_TARGET_ARCH`
  alone, so `aarch64-apple-ios-sim` gets the same assembly as `aarch64-apple-darwin`;
  there is no simulator special case. The portable-C fallback is ~2-5x, not orders of
  magnitude. Also `server.o` in the archive is blst's own amalgamated C, not aws-lc.
- **The device risk is memory, not time.** The spike's Mac numbers bracket us: k=13 = 69 ms /
  27 MB peak, k=15 = 207 ms / 106 MB peak. At k=14 expect peak RSS in the tens of MB, and iOS
  kills apps for memory (Jetsam) long before users complain about a second of latency. Watch
  peak RSS at least as closely as wall time on device.
- **Slip's own circuits, measured (not assumed):** 22 MB of prover keys across
  6 circuits on compiler 0.31.1, in two size classes — `sealPick` and `reveal` at 5.1 MB,
  the other four at ~3.1 MB (0.34.0 produced 21 MB; the move back cost ~1 MB);
  verifier keys are 4 KB each; ZKIR is 8-16 KB per circuit. **`k` is not recorded in any artifact**
  (ZKIR is instruction-level JSON; k is chosen at key generation), so the "k≈10-class" label above
  is inherited from the spike's generic benchmarks and has never been measured for this contract —
  the 5.0 MB prover keys suggest it is higher. Treat 20.8 MB as the real number that matters: it is
  the on-device download, and it grows with every circuit added. Escrow was measured to roughly
  double it.
- **ZKIR v2 — the only option on our compiler.** 0.31.1 emits v2 and has no
  `--feature-zkir-v3` flag (that arrived in 0.33.0). Measured on 0.34.0 before we moved
  back: v3 quadrupled prover keys, 21 MB -> 87 MB. If the supported toolchain ever
  reaches 0.33+, that flag stays off unless the number is re-measured.
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

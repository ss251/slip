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
- **PROVEN ON A PHYSICAL iPhone 15 Pro (A17 Pro), 2026-09-03**, loading the
  compiler-emitted proving key: **pk load 24 ms, prove 1776 ms, wall 1.81 s,
  proof 4480 bytes, peak RSS 290 MB.**
- **Never run keygen at runtime.** `compactc` already emits `keys/<circuit>.prover`;
  regenerating it cost **1173 ms on every prove** for nothing. Loading it is a 24 ms
  file read — a 49x reduction on that step and −32% wall (2.66 s -> 1.81 s). The file
  is tagged (`midnight:prover-key[v7](...)`) so it needs `tagged_deserialize`, and
  deserialization is lazy: the gzipped `MidnightPK` inflates on first use inside the
  prove window (which is why `prove` rises 1479 -> 1776 ms while the total falls).
- **Loading the key does NOT reduce peak memory** — measured 289 MB -> 290 MB. The
  serialized 5 MB key is not the in-memory key: `ProvingKey::read` recomputes the
  cosets, so you get the same ~40-50 MB PK either way, and the peak lives in the
  PROVE phase where PK cosets, advice cosets, permutation products and the quotient
  buffer coexist. Keygen transients are freed before that peak. Do not re-litigate this.
- **Memory does not currently need fixing.** Foreground Jetsam is ~2.0-2.2 GB even on
  4 GB devices, so 290 MB transient has ~2.5x headroom; ~100-150 MB is the realistic
  floor for k=14 with this library, so we are ~2x par, not 5x. The one lever that
  would halve it — dropping to k=13 — is **blocked**: it would require moving hashes
  to `transientHash`/`transientCommit`, which the API reference says are "not
  guaranteed to persist between upgrades" and "should not be used to derive state
  data". Every hash in `slip.compact` derives state (memberId, stewardAuth, the seal
  commitment, and the pick salt that must re-derive at reveal). A transient salt would
  make every unrevealed seal permanently unopenable after a protocol upgrade.
- **The real risk is latency on older silicon, not memory.** A13/A14 devices
  (iPhone SE 2/3, 11, 12) were ~6-9 s with runtime keygen; the key fix should put them
  near 3-4 s. Measure on the oldest supported device before promising a seal time.
- **App extensions are out of reach** (~120 MB cap vs our 290 MB peak). "Seal from the
  share sheet" is not possible without a fundamentally smaller circuit.
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


## CI coverage — MidnightKit is NOT covered, and this is a real gap

The Rust prover's source lives **outside this repo** (external volume, with the rest
of the spike), and the built archive is gitignored (~61 MB per architecture). A CI
runner can reach neither, so `MidnightKit/Vendor/*.a` is absent there and the lane
**emits a GitHub warning and skips** rather than pretending to pass.

That skip is deliberate and loud. A silently-green lane that tests nothing is the
failure mode this repo has already hit four times (blank design PNGs, a board gate
crashing on valid input, a privacy probe whose detector could never fire, a
freshness regex that silently matched nothing). If MidnightKit's lane ever reports
success, it must be because it ran.

What this means in practice: **MidnightKit is verified locally, not by CI.** Before
any release, run it yourself and paste the output:

```
sh scripts/sync-prover.sh aarch64-apple-ios-sim
cd MidnightKit && xcodebuild test -scheme MidnightKit \
  -destination 'platform=iOS Simulator,name=<a device that exists>'
```

To close the gap properly, the prover source has to become reachable by CI — either
vendored into this repo (the source is one `lib.rs` plus a `Cargo.toml`; only the
`target/` output is large) or published as a prebuilt xcframework release that CI
downloads. Until one of those happens, treat MidnightKit's green marks as unverified
by machinery.

`swift test` will never work here: it builds for the macOS host, which both misses
the iOS platform floor (`isolation()` needs macOS 10.15+, and the package declares
iOS only) and cannot link an `aarch64-apple-ios` archive. Always xcodebuild against
a simulator destination.


## Contract execution on device — JavaScriptCore, VERIFIED 2026-09-04

An earlier version of these notes claimed the Compact runtime "loads under JSC with a
small Buffer shim." That was never executed; LANE-C.md said `UNVERIFIED` and no
`JSContext` code existed. It is now verified by a test (`IosHost/IosHostTests/
JSCRuntimeTests.swift`, spike dir):

- `compact-runtime-iife.js` (Kuira's extracted bundle, 71.8 KB) loads under
  `JSContext` on the iPhone 17 Pro simulator in **54 ms**, exposing `__compactRuntime`
  with **114 exports**, calling **zero** natives at load time.
- Calling `__compactRuntime.persistentHash(new CompactTypeBytes(32), bytes)` routes
  into a host-registered native and the reply comes back parsed — full round trip.

**Why there is no WASM problem:** the bundle contains zero `WebAssembly` references.
Kuira's shim replaced the WASM on-chain runtime with **eight host callbacks**; that
is the entire native surface MidnightKit must provide:

```
__native_contractQuery        __native_persistentHash_aligned
__native_persistentCommit     __native_transientHash
__native_bigIntToValue        __native_valueToBigInt
__native_stateCreateWithNulls __native_stateSetOperation
```

**Naming trap:** the ESM shim file says `__native_persistentHash`; the IIFE that
actually runs says `__native_persistentHash_aligned`. Grep the IIFE for
`globalThis.__native_`, never the shim, for the real names.

**Wire contract:** everything crosses the bridge as **JSON text**. `persistentHash`
takes one string `{value:[[bytes]…], alignment}` and returns a string that is either
an array of byte arrays or `{error}`. Natives are plain functions on `globalThis`.

**Buffer:** JSC has none. The runtime uses only `Buffer.from(hex,'hex')`,
`Buffer.from(bytes)` and `.toString('hex')` — a ~15-line polyfill, mandatory.

**Still open (Day 1, deliverable 2 → Day 4 gate):** `__native_contractQuery` backed by
the ledger's `QueryContext` in Rust; then executing `sealPick` end-to-end in JSC and
proving the resulting preimage is **byte-identical** to one built in Node. Only that
diff makes on-device execution a fact rather than a demo.

Also: skip `proofDataIntoSerializedPreimage` (a raw WASM re-export with no JS body).
JS returns `proofData`; the preimage is built natively via `construct_proof`
(`ledger/src/construct.rs:502`), keeping preimage assembly and the `binding_input`
overwrite in one Rust process — which is also what Kuira does.

## On-device execution gate — PASSED 2026-09-04

`IosHostTests/JSCExecutionTests` (spike, external SSD) runs `enrollMember → createSlip →
sealPick` under JavaScriptCore through the 8 `__native_*` hooks into the real Rust ledger
VM (`slip-prove-ffi/src/{contract_query,crypto_natives}.rs`) and requires the resulting
`proofData` to be byte-identical to Node's golden (`contracts/build/sealPick-proofdata.json`).
Result: `IDENTICAL: true`, 3612 bytes both sides, 29/29 public-transcript ops, executed in
38 ms. Four LOCAL PATCHES to Kuira's runtime shim were needed (all marked `LOCAL PATCH`):
block time passed to the VM as a 3rd query arg; child contexts inherit block/callContext;
`StateValue.toJSON` canonical form; the transcript recorder stores the canonical
(Rust-serde) op shape the VM consumed. Next: build the proof preimage natively from
`proofData` (`ledger/src/construct.rs` `construct_proof`) and feed `slip_prove_circuit`.

## Execute → preimage → prove, all on device — PASSED 2026-09-05

`slip-prove-ffi/src/preimage.rs` ports the runtime's `proofDataIntoSerializedPreimage`
line for line (`slip_proof_data_into_preimage(json, key_location, out_path)` in the C
ABI). Host test: native bytes equal Node's `contracts/build/sealPick.preimage.bin`
(387 bytes). `JSCExecutionTests` now continues past byte-identity: the device's own
`proofData` → native preimage (identical to Node's) → `slip_prove_circuit` → rc 0,
pk load 27 ms, prove 1229 ms, proof 4480 bytes (iPhone 17 Pro simulator). The witness
never leaves the process. Remaining for MidnightKit: host JSC + the 8 natives + this
call behind `Prover`, and ship the two libraries (sim/device) via `scripts/sync-prover.sh`.

## Execution lives in MidnightKit now (2026-09-05)

`Sources/MidnightKit/Runtime/ContractRuntime.swift` hosts JavaScriptCore, loads the
runtime from the package's `JS/` resources (`buffer-polyfill.js`, `polyfills.js`,
`compact-runtime-iife.js` — Kuira's shim WITH our four `LOCAL PATCH`es, now tracked here
as the source of truth — and the compiled `slip-contract-iife.js` from
`contracts/build`), and installs the eight `__native_*` hooks over the Rust FFI.
`Prover.prove(circuit:proofData:)` calls `slip_prove_proof_data`: the preimage is built
in memory on the Rust side and never written to disk; the proof bytes come back in
`Proof.data`. Gate: `Tests/MidnightKitTests/ContractRuntimeTests.swift` — sealPick
executed on device must equal Node's golden `proofData` (fixture) and must prove
(4480 bytes). Measured on the iPhone 17 Pro simulator: execute 28 ms, prove 1.41 s.

Run: `cd MidnightKit && sh ../scripts/sync-prover.sh && xcodebuild test -scheme MidnightKit
-destination 'platform=iOS Simulator,name=<iPhone from simctl list>'`. The test reads
proving artifacts from `contracts/build/{zkir,keys,params}` (gitignored; `compact compile`
produces zkir+keys, `params/bls_midnight_2p14` is the k=14 SRS the proof server
downloads — copy it there once). The resource directory is `JS/`, not `Resources/`:
codesign rejects a SwiftPM bundle with a top-level directory of that name.

## Transaction-bound proving (2026-09-05)

A proof inside a transaction must commit to that transaction's binding input: ledger's
`Transaction::prove` passes `call.binding_input(binding_commitment)` (address, entry
point, transcript gas, and the transaction's Pedersen binding commitment — see
`ledger/src/verify.rs`), and the proof server simply sets `preimage.binding_input` to it
before proving (`proof-server/src/endpoints.rs`). A zero-bound proof is rejected on-chain
as `Malformed(InvalidProof)` — exactly what the Phase 6 devnet referee saw.

The native bridge now takes the overwrite: `slip_prove_proof_data_bound` (phone path)
and `slip_prove_preimage_bound` (host path), surfaced as
`Prover.prove(circuit:proofData:bindingInput:)` (big-endian hex field element; `nil`
keeps the zero binding for local demos only; bad hex → `.bindingInputInvalid`). Host CLI
`slip-prove --preimage … --binding 0x… --out …` (built with `cargo build --release
--features cli --bin slip-prove` in slip-prove-ffi) stands in for the proof server in a
Node `ProvingProvider`, so the devnet can verify a proof made by OUR prover. Evidence:
two bindings → two different 4,480-byte proofs (host test `binding_changes_the_proof`;
kit test `bindingInputIsInTheStatement`, gate 9/9). The remaining gap for a phone-only
submission is assembling the unproven transaction on device so the binding is known
before proving — that is the native tx-assembly work, tracked in HANDOFF.md.

## Native transaction assembly on device (2026-09-05)

`Prover.buildProvedCallTransaction(circuit:proofData:networkID:contractAddressHex:
contractState:blockTime:ttl:)` → `ProvedTransaction` (tagged ledger bytes). Backed by
`slip_build_proved_call_tx` in `slip-prove-ffi/src/tx_assembly.rs`: `proofData` + the
deployed contract's tagged `ContractState` (from the indexer) become a ledger-8
`PrePartitionContractCall`; `StandardTransaction::add_calls` partitions the transcript and
builds the preimage; `Transaction::prove` derives the binding input and drives OUR prover
through `ProvingProvider`. The output is a proved, UNBALANCED transaction — a wallet
(holding the fee keys) balances, signs and submits (prove → balance → bind). Nothing
private leaves memory; no proof server anywhere. Evidence: host test
`builds_and_proves_a_bound_call_tx` (5,238 bytes, 1.49 s); kit test
`assemblesProvedTransaction` on the iPhone 17 Pro simulator (5,236 bytes, 0.96 s; gate
10/10). Host CLI `slip-prove assemble …` produces the same bytes for the Node referee.
The ffi crate now has a local git repo on the SSD (`83d02ca`) and a tarball under
`handoff/evidence/`. Known follow-up: Thread Performance Checker priority-inversion
warnings from the `.userInitiated` prover thread waiting on rayon/blst workers.

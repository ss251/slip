# Phase 6: network-proof sources and evidence

Consulted 2026-09-05. Midnight facts below came from the native authenticated kapa
MCP, the pinned 4.1.1/ledger-8 source installed in this repository, Midnight Expert,
and MIDSKILLS. Model recall is not a source. The executable result is deliberately
recorded as a failed app-proof acceptance gate, not as network integration.

## Kapa queries

These queries were sent through native
`mcp__midnight__search_midnight_knowledge_sources`:

1. “For Midnight ledger 8 and midnight-js 4.1.1, is a bare proof plus commitment
   sufficient to construct a contract call, or which call-prototype fields and
   private transcript material are required?”
2. “When ledger 8 calls `ProvingProvider.prove` with `overwriteBindingInput`, may a
   proof generated earlier be returned unchanged, or must that binding input be in
   the proof statement at proof-generation time?”
3. “Which contract execution, private transcript, proving, wallet balancing and
   submission steps belong inside the trusted user-device boundary?”
4. “Does Midnight publish an official Swift/native wallet or transaction-assembly
   SDK, or is the supported application surface TypeScript/JavaScript?”
5. “For Midnight ledger 8 with midnight-js 4.1.1 and wallet-sdk 1.2.0, describe the
   required prove, balance, sign, bind, submit and indexer-confirm sequence, and
   which private data must remain on the user’s trusted device.”
6. “What byte format must low-level `ProvingProvider.prove` return, how is a
   versioned proof serialized, and can raw proof bytes be wrapped without
   regenerating a proof or exposing private transcript data?”

## Official conclusions

- Execution, witness callbacks, private transcript handling and proof generation
  are one trusted-device domain. Only public transcripts, commitments/nullifiers,
  proofs and the finalized transaction cross to the network. A remote proof server
  sees the private proof request.
  [End-to-end architecture](https://docs.midnight.network/concepts/how-midnight-works/end-to-end-architecture),
  [security guidance](https://docs.midnight.network/guides/security-best-practices#proving-and-private-data).
- The supported high-level flow is execute locally → prove → balance → submit →
  wait for finality. `SucceedEntirely` means every segment succeeded.
  [Midnight.js API](https://docs.midnight.network/api-reference/midnight-js),
  [transaction user flow](https://github.com/midnightntwrk/midnight-architecture/blob/main/user-flows/dapp-user/dApp%20User%20Generating%20a%20Transaction.md).
- A ledger-8 call prototype needs the contract address and operation, guaranteed
  and fallible public transcripts, private transcript outputs, aligned input and
  output, communication randomness and circuit key location. Proof plus commitment
  cannot reconstruct it.
  [Ledger calls](https://docs.midnight.network/api-reference/ledger#calls),
  [ledger-8 construction source](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/ledger/src/construct.rs#L471-L576).
- The ledger computes the call’s final binding input after transaction assembly and
  passes it to the prover. A provider may not reuse a proof of a different public
  statement. Formatting raw bytes as a `ProofVersioned` value changes serialization,
  not cryptographic inputs.
  [ledger proving](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/ledger/src/prove.rs#L346-L372),
  [WASM provider adapter](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/ledger-wasm/src/tx.rs#L410-L457),
  [proof-server overwrite](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/proof-server/src/endpoints.rs#L284-L318).
- A user-side finalized transaction must be proved before it is balanced and bound.
  DUST balancing and its wallet proofs stay where the user’s wallet keys live.
  [DUST prove/balance/bind](https://docs.midnight.network/guides/dust-sponsorship#the-user-side-prove-balance-bind).
- The official SDK/API surface retrieved for this stack is TypeScript targeting
  Node.js and browsers. No supported Swift transaction/wallet interface appears in
  the official API index; Slip therefore needs its native ledger bridge to expose
  any iOS transaction assembly rather than inventing a Swift wire format.
  [official API index](https://docs.midnight.network/api-reference),
  [wallet developer guide](https://docs.midnight.network/sdks/official/wallet-developer-guide).

## Pinned 4.1.1 source audit

Installed versions are fixed by `contracts/e2e/package-lock.json`: midnight-js and
testkit 4.1.1, the umbrella wallet-sdk 1.2.0 (with wallet-sdk-facade 4.1.0 and
wallet-sdk-dust-wallet 4.2.0), compact-runtime 0.16.0 and ledger-v8 8.1.0.
The following installed source was read directly:

- `midnight-js-types/dist/proof-provider.d.ts:16-35` — `proveTx` maps an
  `UnprovenTransaction` to an unbalanced `UnboundTransaction`; `createProofProvider`
  adapts the lower-level provider.
- `ledger-v8/ledger-v8.d.ts:1943-1976,2255-2264,2330-2335` — exact call-prototype
  fields, low-level `check`/`prove` signature, optional binding overwrite and legal
  proof-stage transition.
- `midnight-js-contracts/dist/index.mjs:26-29,69-71,896-909,1330-1367` — executable
  call assembly uses fresh communication randomness; submission proves, balances,
  broadcasts and waits through the indexer. The unsubmitted result explicitly
  contains privacy-sensitive input, output and private transcript values.
- `wallet-sdk-facade/dist/index.js:357-385,416-427,450-458,486-489` — shielded,
  unshielded and DUST balancing, signing, binding, and the wallet’s separate proof
  operation for fee-balancing transactions.
- `midnight-js-types/dist/public-data-provider.d.ts:65-80,127-145` — latest contract
  state query and indefinite transaction-finality watcher; an application-level
  timeout is required.

## Native boundary audit

The protected native implementation outside this public repository was inspected
read-only. `slip-prove-ffi/src/preimage.rs:43-70` converts runtime `ProofData`, but
sets both `binding_input` and communication randomness to zero.
`slip-prove-ffi/src/lib.rs:116-128` proves that preimage immediately and returns raw
`proof.0` bytes. The committed C header exposes neither a binding-input argument nor
transaction assembly: `MidnightKit/Sources/CSlipProve/include/slip_prove_ffi.h`.

Ledger-8 independently confirms why this is not a network proof:

- `ledger/src/prove.rs:346-363` computes and supplies the assembled call binding.
- `ledger/src/verify.rs:1855-1881` verifies against the call’s recomputed public inputs.
- `transient-crypto/src/proofs.rs:130-135` defines the raw proof byte vector.
- `ledger/src/structure.rs:287-305` and `serialize/src/{serializable.rs,util.rs}`
  define the versioned envelope. A 4,480-byte raw proof becomes 4,508 bytes:
  25-byte `midnight:proof-versioned:` header, one-byte version, two-byte SCALE
  length, then the unchanged proof bytes.

## Executable referee

All values below are public sizes/statuses. No app-generated witness, runtime
`ProofData`, private transcript output, secret key or proof-byte content was exported
or printed. The temporary Node referee used a synthetic witness confined to its
scratch fixture source; the app persisted only the public diagnostic artifact.

1. A DEBUG simulator launch used the real app-owned `SealFlowModel` and native prover.
   The fresh export was approximately 6.1 KB of JSON with exactly `commitment` and
   `proof`; decoded sizes were 32 and 4,480 bytes. A forced failure removed the prior
   artifact, and a later successful launch created a new inode and modification time.
2. The local node, indexer and tooling-only proof server were recreated together after
   detecting an old indexer at height 2435 attached to a fresh node. All became healthy
   on the same undeployed chain.
3. A control transaction assembled by pinned midnight-js, using its standard proof
   path, returned a 4,508-byte `midnight:proof-versioned:` proof. The provider received
   a non-nil binding overwrite; the node returned `SucceedEntirely`; the indexer-decoded
   Slip state contained the seal commitment. This validates the devnet and harness.
4. Returning the raw app bytes from the custom provider was rejected locally before
   submission because the ledger envelope was absent.
5. Adding the exact 28-byte ledger envelope let the app proof reach the node. The
   custom seal provider used local `@midnight-ntwrk/zkir-v2` checking and did not call
   `/prove`. The node rejected it as `Malformed(InvalidProof)` (RPC custom error 115).
   The provider had received a non-nil binding overwrite, but the existing app proof
   had already been generated for binding zero and different call context. No rejected
   commitment appeared in the indexer.

The wallet still used its configured local tooling proof service for the separate
DUST balancing proof in these Node diagnostics. The iOS app made no network or proof-
server request.

## Skills consulted

Midnight Expert:

- `compact-core/skills/compact-witness-ts/SKILL.md`
- `compact-core/skills/compact-language-ref/SKILL.md`
- `compact-core/skills/compact-transaction-model/SKILL.md`
- `compact-core/skills/compact-privacy-disclosure/SKILL.md`
- `midnight-verify/skills/verify-by-execution/SKILL.md`
- `midnight-verify/skills/verify-correctness/SKILL.md`

MIDSKILLS: `.agents/skills/SOURCE.md` LOCAL DELTA first, then `midnightskill`,
`midnight-js`, `midnight-transactions`, `midnight-security`, and `indexer`. Their
examples are advisory; the pinned 0.23.0/compiler-0.31.1 build and executable
ledger-8 behavior are the referee.

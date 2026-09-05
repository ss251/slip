# Phase 6: network-proof sources and evidence

Consulted 2026-09-05. Midnight facts below came from the native authenticated kapa
MCP, the pinned 4.1.1/ledger-8 source installed in this repository, Midnight Expert,
and MIDSKILLS. Model recall is not a source. The first executable result below is the
historical zero-binding failure that established the missing boundary; the second is
the passing native-assembly referee that closes it on the local network.

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
7. “For Midnight ledger 8 and midnight-js 4.1.1, what is the exact low-level
   `ProvingProvider.prove(preimage, overwriteBindingInput)` signature, the type and
   meaning of `overwriteBindingInput`, and the serialized proof value it must return?”
8. “For Midnight ledger 8, how can JavaScript serialize a `ProofPreimage` in the
   tagged binary format accepted by the proof server or a native prover? Identify the
   ledger-v8 API method and the exact tag or framing.”
9. “In midnight-js 4.1.1 with ledger 8, when a contract transaction invokes
   low-level `ProvingProvider.prove`, how is `overwriteBindingInput` represented in
   JavaScript and how is that bigint converted to the big-endian field-element
   hexadecimal text expected by an external native prover?”
10. “In Midnight ledger 8 and midnight-js 4.1.1, when a custom `ProvingProvider`
    returns proof bytes, must the returned `Uint8Array` be tagged-serialized `Proof`
    or `ProofVersioned`, and what official API can serialize raw proof bytes into that
    accepted format?”
11. “In midnight-js 4.1.1 using ledger 8, what are the exact JavaScript APIs and
    transaction type transitions to deserialize a tagged proved-but-unbalanced
    transaction, balance it with `WalletProvider.balanceTx`, and submit it through
    `MidnightProvider.submitTx`? Include whether an explicit sign or bind call is
    needed.”
12. “In midnight-js 4.1.1, how should a client fetch the current deployed contract
    `ContractState` from the indexer/public data provider and obtain tagged bytes with
    `ContractState.serialize` for local transaction construction?”
13. “For Midnight local undeployed network with midnight-js 4.1.1, what exact network
    ID string must ledger transaction construction use, and what authoritative
    indexer or node field provides the current chain block timestamp in seconds for a
    contract circuit context and transaction TTL?”
14. “In Midnight indexer v4 used with midnight-js 4.1.1, what GraphQL query returns
    the latest block timestamp, what unit is the `Block.timestamp` integer, and how
    should that timestamp be converted for Compact `QueryContext`
    `block.secondsSinceEpoch` and ledger transaction TTL?”
15. “For Midnight ledger 8 and midnight-js 4.1.1, design a device-local Compact
    contract-call transaction assembler: which public chain context must be fetched
    coherently, which values must remain private in the device process, when is the
    binding input derived relative to transcript partitioning and proving, what are
    the proof public inputs including the separate communication commitment, and what
    steps balance, sign, bind, submit, and confirm the transaction?”
16. “In Midnight ledger 8 / midnight-js 4.1.1 transaction flow, is a proved
    transaction with proof marker `Proof` and binding marker `PreBinding` safe to
    treat as a public/network-boundary artifact, or must it remain inside a trusted
    wallet boundary until balancing, signing and binding are complete?”
17. “In the ledger-8 source, list every value hashed into a contract call proof's
    `binding_input`. Does the binding include the guaranteed transcript instruction
    count or length?”

## Official conclusions

Installed pinned-source citations in the next section are authoritative for 4.1.1.
GitHub links whose URL targets `main` are supplementary navigation and may describe a
newer implementation.

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
- The low-level ledger-8 provider receives an already tagged `ProofPreimage`, the
  circuit key location, and an optional non-negative JavaScript `bigint` binding
  overwrite. The bigint's ordinary `0x${value.toString(16)}` spelling is the
  big-endian field hex the native bridge accepts. The provider must return a tagged
  serialized `Proof` or `ProofVersioned`; raw PLONK bytes are not that value.
  [provider contract](https://docs.midnight.network/api-reference/ledger/type-aliases/ProvingProvider),
  [ledger adapter](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/ledger-wasm/src/tx.rs#L410-L457),
  [local prover conversion](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/zkir-wasm/src/lib.rs#L74-L160).
- A native proved/pre-binding transaction is already an `UnboundTransaction` and is
  deserialized with marker triple `('signature', 'proof', 'pre-binding')`. Wallet
  balancing owns input selection, signing, final binding and fee proof; callers do
  not prove or manually bind it again before `submitTx`. The pre-binding value remains
  a trusted-wallet handoff; only the finalized transaction crosses the network boundary.
  [supplementary current-main wallet adapter](https://github.com/midnightntwrk/midnight-js/blob/main/testkit-js/testkit-js/src/wallet/dapp-connector-wallet-adapter.ts#L44-L129),
  [transaction deserializer](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/ledger-wasm/src/tx.rs#L658-L752).
- `queryContractState(address)` returns the latest public `ContractState`; its
  canonical tagged `serialize()` bytes are suitable for the native ledger. For a
  coherent general transaction input, `queryZSwapAndContractState` additionally
  returns the Zswap state and ledger parameters anchored to one block.
  [supplementary current-main indexer provider](https://github.com/midnightntwrk/midnight-js/blob/main/packages/indexer-public-data-provider/src/provider.ts#L106-L205).
- Local network construction uses the exact ID `undeployed`. Indexer v4's `block`
  query returns its UNIX `timestamp`; wallet-sdk consumes that value with
  `new Date(block.timestamp)`, establishing milliseconds, whereas Compact's
  `secondsSinceEpoch` is seconds. The referee therefore captures the latest indexed
  value once and divides by 1,000 for both local execution and native assembly. This
  conversion is an inference from the two official APIs and was confirmed by the
  live value `1788592026004`.
  [network IDs](https://docs.midnight.network/sdks/official/midnight-js#configure-the-network),
  [latest-block query](https://github.com/midnightntwrk/midnight-indexer/blob/main/qa/tests/utils/indexer/graphql/block-queries.ts),
  [wallet block conversion](https://github.com/midnightntwrk/midnight-wallet/blob/main/packages/capabilities/src/validation/blockData.ts),
  [Compact block context](https://docs.midnight.network/api-reference/compact-runtime/type-aliases/BlockContext).
- `add_calls` first derives the communication commitment and partitions each
  pre-transcript using ledger parameters. Proof verification receives the derived
  binding input as its first public field, the communication commitment as a
  distinct second field, then the guaranteed and fallible public transcript fields.
  The call's input, output, private transcript outputs and communication randomness
  remain proof-construction material inside the private domain.
  [call construction](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/ledger/src/construct.rs#L99-L194),
  [proof public inputs](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/ledger/src/verify.rs#L1801-L1893),
  [end-to-end boundary](https://docs.midnight.network/concepts/how-midnight-works/end-to-end-architecture).
- A call binding covers the address, entry point, declared transcript costs/effects,
  guaranteed transcript instruction count and parent intent binding commitment. A
  proved/pre-binding transaction can still be modified during wallet balancing and
  retains binding randomness, so it is not the network boundary.
  [ledger-8 binding source](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/ledger/src/verify.rs#L1894-L1937),
  [ledger-8 lifecycle](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/spec/intents-transactions.md).

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
- `midnight-js-types/dist/public-data-provider.d.ts:65-84,127-145` — latest contract
  state query and indefinite transaction-finality watcher; an application-level
  timeout is required.
- `ledger-v8/ledger-v8.d.ts:1112-1200,2255-2264,2298-2428` — proof/signature/binding
  markers, exact low-level provider signature, transaction stage transitions and
  four-argument transaction deserialization.
- `midnight-js-types/dist/{proof-provider,wallet-provider,midnight-provider}.d.ts` —
  the proved/pre-binding value is the wallet's `UnboundTransaction`; balancing
  returns a finalized transaction and submission returns its transaction ID.
- `midnight-js-indexer-public-data-provider/dist/index.mjs:568-572,828-850` — latest
  state is hex-decoded into a runtime `ContractState`; its generated GraphQL schema
  exposes block timestamps in finalized transaction data.
- `midnight-js-types/dist/public-data-provider.d.ts:31-46,65-84` and
  `midnight-js-indexer-public-data-provider/dist/index.mjs:828-879` — state queries
  accept a block-hash fence, while the coherent state/Zswap/parameter tuple omits that
  block's hash/time and falls back to `LedgerParameters.initialParameters()` if the
  indexed action has none. Production transport must retain the explicit block fence
  and reject that silent fallback.
- `compact-runtime/dist/circuit-context.js:40-49,77-98` — explicit execution time is
  stored as `BigInt` Unix seconds. One captured second must be reused for proofData
  generation and native transcript replay.
- `wallet-sdk-facade/dist/index.js:357-490` — balancing and signing happen before
  `baseTransaction.bind()`; finalization also proves/binds the separate DUST
  balancing transaction. No extra bind belongs in the referee.

## Native boundary audit

The historical native bridge constructed a proof preimage from runtime `ProofData`,
then fixed its binding and communication randomness to zero and returned only raw
`proof.0` bytes. That explains the
first referee's `InvalidProof`: ledger-8 computes the assembled call binding in
`ledger/src/prove.rs:346-363` and the validator recomputes it in
`ledger/src/verify.rs:1855-1881`; the 4,508-byte versioned envelope can format, but
cannot rebind, a 4,480-byte proof.

The protected layer now exposes two source-proved paths:

- `Prover.prove(circuit:proofData:bindingInput:)` forwards big-endian field hex to
  the native preimage prover. This is a binding-aware low-level proof primitive; it
  does not freeze or validate a transaction skeleton by itself.
- `Prover.buildProvedCallTransaction(...)` and host `slip-prove assemble` keep the
  safer monolithic sequence inside ledger 8: construct the pre-partition call,
  partition its transcript, derive the binding, prove through the native
  `ProvingProvider`, and return tagged proved/pre-binding transaction bytes.

The current assembler is intentionally narrow. It uses a bundled verifier rather
than resolving the deployed operation, initial ledger parameters/cost model rather
than an associated-block value, zero communication randomness, and a partial query
context. Empty Zswap inputs are valid for Slip's current unitless call. These choices
passed the fresh undeployed `sealPick` referee but are not a general or production
transaction-assembly contract; the v2 design note records the required hardening.

## Executable referee

All values reproduced below are public sizes/statuses; no witness, runtime `ProofData`,
private transcript output, secret key or proof-byte content is printed. The app's DEBUG
diagnostic exported only its public proof and commitment. Separately, the host referee
wrote its own synthetic runtime `ProofData` to a mode-0600 scratch file solely for the
local native CLI, never sent it over the network, unlinked it immediately after use and
removed its mode-0700 directory. The synthetic witness remained host-local test material.

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

### Bound native acceptance

`scripts/phase6-live-referee.mjs` then exercised the transaction-aware native path:

1. Pinned midnight-js deployed Slip, enrolled a synthetic undeployed-network member,
   and opened a round through the standard provider path.
2. Deployment supplied the live contract address. The referee captured the indexer's
   latest block, queried `ContractState` at that exact block hash, serialized the
   pre-call state and reused that block second for local `sealPick` execution and native
   transcript replay. It did not exercise the future Zswap/ledger-parameter transport.
3. Runtime `ProofData` existed only in a mode-0600 file inside a mode-0700 temporary
   directory. It was never printed or sent over the network, was unlinked immediately
   after native assembly, and the directory was removed after the wallet stopped. The
   referee's artifact-freshness preflight compares only the compiler `contract/`,
   `zkir/`, `keys/` and `params/` subtrees; it never enumerates or reads build-root
   proofData/preimage scratch.
4. `slip-prove assemble` emitted a 5,238-byte proved/pre-binding transaction in
   1,339 ms on the first run, 1,129 ms on the preflight repeat and 1,276 ms with the
   final same-length privacy control. Ledger-v8
   deserialized it with the exact proof-stage markers; the genesis wallet balanced,
   signed and finalized it.
5. The node returned `SucceedEntirely` at blocks 1251, 1772 and 1923. Every indexer
   check exposed the exact
   locally computed commitment
   `e87cfcfb808dc9033999316359655f84ec7f06514f5ca709d904326148c533fe`,
   and the finalized payload did not contain the synthetic 32-byte witness pattern.

The precise result is: Slip's native prover generated the `sealPick` contract-call
proof with the binding derived by ledger 8, and the local network accepted it. The
tooling proof server still handled the standard setup calls and the wallet's separate
DUST proof; it did not generate the native seal proof. Node stood in for the app's JSC
execution side, using the same runtime `ProofData` encoding verified by
`MidnightKit/Tests/MidnightKitTests/ContractRuntimeTests.swift`.

The wallet still used its configured local tooling proof service for the separate
DUST balancing proof in these Node diagnostics. The iOS app made no network or proof-
server request.

### Reproduce the host referee

This remains a developer-machine gate, not a clean-clone CI promise. It requires the
undeployed node/indexer/tooling proof service, full compiler artifacts and the external
host `slip-prove` binary that is not distributed by this repository:

```sh
cd contracts
npm ci
npm run build
npm run devnet:up
cd e2e
npm ci
node link-build.mjs
cd ../..
SLIP_PROVE_CLI=/absolute/path/to/slip-prove node scripts/phase6-live-referee.mjs
```

Run `link-build.mjs` only from a freshly generated compiler build tree; local
proofData/preimage scratch does not belong in either build directory. The referee
preflight reads only `contract/`, `zkir/`, `keys/` and `params/`. Its default CLI path
is the maintainer's local spike checkout for convenience, while `SLIP_PROVE_CLI` is the
portable explicit override.

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

# Phase 7 sources: authenticated undeployed steward relay

Status: authenticated host relay accepted by the undeployed node and confirmed through
the indexer. This document records the mandatory source trail for
`scripts/steward-relay.mjs` and `scripts/phase7-live-relay-demo.mjs`. It describes a
trusted local developer-wallet boundary, not production custody or trustless DUST
sponsorship.

## Native kapa queries

All six searches used the native
`mcp__midnight__search_midnight_knowledge_sources` tool. Source conclusions were then
checked against this repository's direct midnight-js 4.1.1 and wallet-sdk 1.2.0
dependencies and resolved ledger-v8 8.1.0 / wallet-sdk-facade 4.1.0 source before
code was written.

1. **Relay lifecycle and trust boundary**

   > For Midnight ledger 8 with midnight-js 4.1.1 and wallet-sdk 1.2.0, how should a trusted local steward relay accept a proved pre-binding contract-call transaction, deserialize it, add only DUST during balancing, sign, finalize, submit it to an undeployed node, and confirm the resulting public contract state through an indexer block-hash query? Clarify that this relay is a trusted wallet boundary rather than trustless DUST sponsorship, and identify security limits for a LAN-only developer relay.

   Relevant results:

   - [wallet facade `balanceUnboundTransaction`](https://github.com/midnightntwrk/midnight-wallet/blob/main/packages/facade/src/index.ts) — a proved/pre-binding transaction is balanced, with an optional token-kind subset; signing and finalization follow.
   - [ledger-8 transaction lifecycle](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/spec/intents-transactions.md) — proving precedes wallet handoff; the transaction remains mutable/pre-binding until wallet balancing and binding.
   - [official provider setup](https://docs.midnight.network/guides/deploy-and-operate#procedure) — wallet balance/finalize/submit sequence and DUST fee role.
   - [official DUST sponsorship](https://docs.midnight.network/guides/dust-sponsorship#the-user-side-prove-balance-bind) — the trust-minimized sponsorship flow hands a finalized/bound user transaction to a sponsor. Slip instead hands its steward a proved/pre-binding transaction; calling this a trusted wallet boundary rather than trustless sponsorship is an inference from that documented contrast and the pinned transaction stage.
   - [guaranteed/fallible semantics](https://docs.midnight.network/concepts/how-midnight-works/transaction-semantics) — fee collection is guaranteed-phase work; Slip's accepted native seal has no fallible transcript.

2. **Coherent state context and confirmation**

   > For Midnight indexer v4 and midnight-js 4.1.1 on ledger 8, what exact API sequence produces a coherent public contract context for an offline caller and confirms a 32-byte commitment afterward? Include querying the latest block hash and timestamp, queryContractState with a blockHash fence, ContractState serialization, timestamp units versus Compact secondsSinceEpoch, and the limitation of confirming by current contract state rather than permanent transaction history.

   Relevant results:

   - [Indexer public-data provider](https://github.com/midnightntwrk/midnight-js/blob/main/packages/indexer-public-data-provider/src/provider.ts#L106-L205) — `queryContractState(address, {type: 'blockHash', blockHash})` returns the state as of the fence or `null`.
   - [Indexer point-in-time tests](https://github.com/midnightntwrk/midnight-indexer/blob/main/qa/tests/tests/integration/basic/queries/contract-type-queries.test.ts#L225-L288) — block-hash and height offsets resolve point-in-time contract state.
   - [ledger-8 contract context](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/spec/contracts.md) — call context includes seconds since epoch and parent-block information.
   - [PublicDataProvider API](https://docs.midnight.network/api-reference/midnight-js/@midnight-ntwrk/midnight-js-types/interfaces/PublicDataProvider) — an unfenced query returns latest state; watch-style APIs can wait indefinitely, so the demo owns its timeout.

3. **What the acceptance evidence proves**

   > For a Midnight undeployed-network sealPick test, what exactly is established by a node result of SucceedEntirely plus an indexer state containing the expected commitment, and what additional evidence is required before claiming that a physical iPhone app submitted that transaction through a steward relay?

   Relevant results:

   - [the `SucceedEntirely` API](https://docs.midnight.network/api-reference/midnight-js/@midnight-ntwrk/midnight-js-types/variables/SucceedEntirely) — both guaranteed and fallible portions succeeded.
   - [ledger-8 transaction application](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/spec/intents-transactions.md) — whole-transaction failure versus full/partial success and state application.
   - [end-to-end architecture](https://docs.midnight.network/concepts/how-midnight-works/end-to-end-architecture) — device-local private computation/proving and the distinct public node/indexer boundary. Component results do not by themselves prove that one physical-device run crossed every boundary.

4. **Stable intent identifiers for idempotency**

   > In Midnight ledger 8, what does Transaction.identifiers() return for a proved pre-binding transaction containing one contract-call intent, and does that intent identifier remain stable when a wallet adds a separate DUST balancing transaction and binds/merges it? Can a trusted relay use the original intent identifier, in addition to a serialized-byte hash, to deduplicate alternate proofs or serializations of the same call before DUST balancing?

   Relevant results:

   - [ledger-8 `Transaction::identifiers`](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/ledger/src/structure.rs#L1454-L1526) — standard-transaction identifiers include each intent binding commitment (plus any Zswap commitment identifiers).
   - [ledger-8 WASM transaction API](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/ledger-wasm/src/tx.rs#L1325-L1363) — exposes those identifiers as serialized hex strings.
   - The accepted one-intent fixture returns one 66-hex identifier. The relay requires that exact one-identifier shape and keys both the byte digest and identifier before wallet work. It reads that incoming identity once and does not depend on the finalized transaction retaining the same identifier after the separate DUST intent is added. An identifier is not proof-validity evidence: semantic de-duplication shares only pending/success results, never an explicitly rejected proof.

5. **Explicit rejection versus ambiguous submission**

   > For Midnight wallet SDK 1.2.0 and ledger 8, how can a client distinguish an explicitly invalid transaction submission from an ambiguous transport or finality failure after submitting a finalized transaction? Identify the relevant TransactionInvalidError or SubmissionError types, whether retrying exact finalized bytes is safe, and what evidence can reconcile a submission that may already have reached the node.

   Relevant results:

   - [Wallet SDK error reference](https://docs.midnight.network/sdks/error-reference#wallet-sdk-error-reference) — `TransactionInvalidError` means the node rejected the transaction and it must not be resubmitted unchanged; `TransactionProgressError` can leave it in the mempool and requires status reconciliation.
   - [pinned node-client behavior](https://github.com/midnightntwrk/midnight-wallet/blob/main/packages/node-client/src/effect/PolkadotNodeClient.ts) — finality timeout, usurped, dropped and invalid statuses are distinct tagged errors; lower-level submission failures wrap their cause in `SubmissionError`.
   - [official 1010 decoding](https://docs.midnight.network/how-to/decode-1010-transaction-rejection-errors) — RPC code 1010 is an explicit transaction-pool rejection envelope whose inner custom code identifies the ledger error.
   - [transaction-submission protocol](https://github.com/midnightntwrk/midnight-architecture/blob/main/apis-and-common-types/transaction-submission/Readme.md) — a timeout is an unclear outcome and may mean either that the transaction remains pending or never reached the node.

6. **Wallet reversion and DUST reservation safety**

   > In Midnight wallet SDK 1.2.0, WalletFacade.submitTransaction reverts the finalized transaction after any submission error. For a trusted relay that sees a connection or finality-unknown error, how should it prevent the released DUST inputs from being selected by another queued transaction before the exact finalized transaction is retried or reconciled? Should successful and ambiguous intent identifiers remain tombstoned through the original intent TTL, and how should TransactionUsurpedError be classified?

   Relevant results:

   - [wallet facade submission test](https://github.com/midnightntwrk/midnight-wallet/blob/main/packages/facade/test/submission.test.ts) — every failed facade submission reverts shielded, unshielded and DUST wallet reservations.
   - [wallet resubmission specification](https://github.com/midnightntwrk/midnight-architecture/blob/main/components/WalletEngine/Specification.md) — resubmission is TTL-bounded because a network failure can leave inclusion uncertain.
   - [ledger-8 replay protection](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/spec/intents-transactions.md#replay-protection) — seen intent hashes remain through their TTL and reject replay.
   - [wallet SDK error reference](https://docs.midnight.network/sdks/error-reference#wallet-sdk-error-reference) — usurped means another transaction replaced one with matching discriminators. Slip conservatively freezes rather than treating that semantic action as safe to rebuild.

Kapa searches include current `main` results. They establish concepts and lead to
source; the executable referee is the pinned installed code below, not newer API text.
In particular, a newer wallet `validateTransaction` helper appears in current source
but does not exist in pinned wallet-sdk 1.2.0, so the relay does not pretend to call it.

## Pinned executable source

Unless explicitly noted, paths below are under
`contracts/e2e/node_modules/@midnight-ntwrk/`; resolved versions come from
`contracts/e2e/package-lock.json`.

- `ledger-v8/ledger-v8.d.ts:1885-1913` — `ContractCall` exposes address, entry point,
  guaranteed/fallible transcripts and proof.
- `ledger-v8/ledger-v8.d.ts:1983-2068` — `Intent` exposes contract actions, both
  unshielded offers, DUST actions and its `Date` TTL.
- `ledger-v8/ledger-v8.d.ts:2202-2253` — maintenance and deployment are distinct
  action classes; the relay permits only an actual `ContractCall`.
- `ledger-v8/ledger-v8.d.ts:2298-2505` — exact four-marker transaction
  deserialization, serialization, stable identifiers, rewards, intents and Zswap offers.
- `ledger-v8/ledger-v8.d.ts:255-380` — the guaranteed transcript's external effects:
  nullifiers, shielded receives/spends, child calls, mints and unshielded flows.
- `wallet-sdk-facade/dist/index.js:318-376,414-490` and
  `dist/index.d.ts:251-279` — submit, DUST-only selection through
  `tokenKindsToBalance: ['dust']`, sign, prove the separate balancing transaction,
  bind and finalize. The omitted option defaults to balancing all token kinds, so it
  is never omitted here.
- `wallet-sdk-node-client/dist/effect/NodeClientError.d.ts` and
  `PolkadotNodeClient.js` — pinned `_tag` shapes and the distinct explicit-invalid,
  finality-timeout, dropped, usurped, connection and raw submission paths. The relay
  walks nested `cause` links without rendering them and recognizes RPC code 1010 as
  explicit rejection.
- `wallet-sdk-facade/dist/index.js:318-326,641-653` — every submission error calls
  `revert(tx)`, releasing the transaction's local wallet reservations. Because that
  includes ambiguous transport/finality outcomes, the relay must not let a later
  wallet job select the same released DUST before exact retry or expiry.
- `midnight-js-indexer-public-data-provider/dist/index.mjs:828-850` — contract-state
  lookup accepts the exact block-hash offset and yields a deserialized
  `ContractState`; its serialized bytes are the phone context.
- `midnight-js-types/dist/public-data-provider.d.ts:127-145` — finality watchers have
  no inherent timeout. `/confirm` instead makes one current-state query per request;
  bounded polling belongs to the caller/demo.
- `contracts/e2e/slip-build/contract/index.js` — the generated `ledger(state.data)`
  view is the referee for the public `seals` map. Startup rejects this mirror if any
  compiler-generated `contract/` file differs from canonical `contracts/build/contract/`.

The accepted 5,238-byte native fixture
`contracts/build/sealPick.proved-tx.bin` was deserialized and inspected without
printing proof bytes. It has exactly one nonzero intent segment, one `ContractCall`
to `sealPick`, one guaranteed transcript, no fallible transcript, rewards, Zswap or
unshielded offers, pre-existing DUST actions, or contract-external effects. The relay
enforces that semantic shape without hard-coding the compiler-dependent program
length. A stale or invalid proof remains for the node to reject; the public ledger API
cannot reconstruct the deployed verifier-operation map from an indexed
`ContractState`, so the relay does not advertise local `wellFormed` proof validation.

## Boundary and protocol decisions

- The proved/pre-binding transaction is sensitive handoff material. It is accepted as
  raw `application/octet-stream`, limited to 64 KiB (well below ledger's 1 MiB hard
  ceiling), and hashed only for bounded idempotency. The single ledger intent identifier
  additionally collapses proof-rerandomized encodings of the same call only while the
  first result is pending or successful. The request
  buffer and collected HTTP chunks are zeroed after synchronous decode; the decoded ledger transaction must
  remain in memory until its serialized wallet job completes. Bodies, proof bytes,
  tokens, keys and errors are never logged or echoed.
- Every work endpoint requires an exact bearer token of 32 random bytes encoded as 64
  hex characters (for example, `openssl rand -hex 32`). The server
  binds loopback by default; a non-loopback host also requires explicit
  `SLIP_RELAY_ALLOW_LAN=1`. Plain HTTP is for a trusted local LAN/Tailscale demo only,
  never public Wi-Fi, port forwarding or production.
- The relay is restricted to one configured 64-hex contract address and guaranteed
  `sealPick` only. It rejects additional intents/actions, fallible execution, value
  offers, rewards, external effects and pre-existing DUST work before touching the
  steward wallet.
- The incoming intent TTL is retained for DUST balancing and checked against a fresh
  indexer block timestamp. Wallet jobs are serialized. Identical bytes share a bounded
  result cache for the maximum accepted TTL plus a five-minute margin. Explicit
  `TransactionInvalidError`/RPC-1010 rejection is terminal and evicted so corrected
  proof bytes can proceed. A failure before finalization/submission is rolled back and
  evicted for a clean retry; after a finalized transaction exists, an ambiguous retry
  resubmits those exact bytes at most three times. Alternate bytes with the same intent
  receive `submission_uncertain`; they never replay the earlier proof, rebalance an
  ambiguous submission or select a second set of DUST.
- Authenticated submit traffic is limited to 12 requests per minute per relay process,
  with at most eight pending wallet jobs. Success and unresolved intent tombstones are
  retained for the full 65-minute safety window and never evicted early. The 1,024-entry
  bound exceeds what the configured per-minute rate can admit across that window;
  on exhaustion the relay fails closed rather than forgetting live intent identity.
  These are developer-relay guardrails, not multi-tenant or production admission control.
- The pinned wallet facade releases DUST reservations on every submit error. Therefore
  any ambiguous, usurped or exhausted result freezes all new and already queued wallet
  work until exact finalized bytes succeed or the tombstone expires. Only
  `TransactionInvalidError` or an RPC-1010 rejection is terminal/evictable. This avoids
  selecting the same released DUST for another transaction while the first outcome is
  unknown; it deliberately trades demo availability for wallet integrity.
- `GET /context/:address` queries the latest block, then fetches that contract state at
  the exact block hash and returns tagged bytes with block seconds. `GET
  /confirm/:commitment` scans only the configured contract's current public `seals`
  values. A later round reset can remove a seal, so this is immediate demo confirmation,
  not permanent history.
- The undeployed genesis wallet and tooling proof service are host-only. The proof
  service may prove the separate DUST balancing transaction; Slip's `sealPick` proof is
  already native and never goes there. No genesis key or relay token belongs in a
  release build.

The current Swift relay client must add the same required bearer token before any LAN
or physical-device run. The server will not weaken authentication to accommodate an
unauthenticated client.

## Evidence matrix

| Evidence | What it establishes | What it does not establish |
|---|---|---|
| Phase 6 host referee | Ledger 8 derived the call binding; Slip's native prover made the `sealPick` proof; the node returned `SucceedEntirely`; indexed state contained the exact commitment. | The iPhone did not originate this live submission. Tooling proved setup calls and the wallet's separate DUST transaction. |
| Physical iPhone `NetworkSealingServiceTests` | Against an embedded post-create state, the phone executed, assembled and proved a 5,238-byte transaction; the planted device-secret pattern was absent. | Its stub relay acknowledged submit/confirm; there was no HTTP steward wallet, node or indexer. |
| Relay unit/policy tests | Authentication, HTTP boundaries, exact transaction allowlist, DUST-only wallet ordering, idempotency and privacy/error handling. | They do not prove live chain acceptance or phone provenance. |
| Phase 7 authenticated host relay demo | A fresh standard-path deployment supplied live public context; the native prover assembled `sealPick`; the exact proved/pre-binding bytes crossed authenticated loopback HTTP; the steward added only DUST; the node returned `SucceedEntirely`; relay confirmation and an independent indexer read contained the exact locally expected commitment. | The producer was the host referee, not an iPhone. Standard setup calls and the separate wallet DUST proof used the tooling proof service. |
| Authenticated phone → relay → devnet | **Pending.** This is the evidence required for the combined “phone proof, network verified” demo claim. | No claim until the protected client carries the token and one real run reaches node success plus exact indexed commitment. |

The final hardened live run on 2026-09-05 assembled the 5,238-byte proved/pre-binding
transaction in 1,107 ms, returned `SucceedEntirely` at block 2128, and independently
observed public
transaction identifier
`00f091dff5caa1c4187dae9a525b686d33ee9b86f237b6692b7d1848af66af045d`
and commitment
`e87cfcfb808dc9033999316359655f84ec7f06514f5ca709d904326148c533fe`.
These are one local-devnet observation, not latency promises or stable deployment IDs.

## Executable verification

`node --test scripts/steward-relay.test.mjs` covers configuration/authentication,
route and media-type policy, declared and chunked body caps, submit rate limiting,
non-echoed errors, the transaction allowlist dimensions, block-time conversion,
DUST-work serialization, byte/intent idempotency, invalid-versus-ambiguous outcomes,
TTL tombstone retention, queued-work freezing, bounded active work, input zeroing and
commitment lookup.
An existing synthetic transaction fixture is
checked only when its explicit path is supplied as `SLIP_RELAY_FIXTURE_PATH`; tests do
not assume ignored proof artifacts exist in a fresh clone. Relay startup enumerates and
compares only `contracts/build/contract/`, never build-root proofData/preimage scratch.

`node scripts/phase7-live-relay-demo.mjs` creates a fresh contract through the pinned
standard setup path, stops that setup wallet, starts the actual steward runtime behind
an ephemeral authenticated loopback HTTP server, fetches exact state/time context,
executes and assembles the native seal, and requires `SucceedEntirely`, relay
confirmation, and an independent member-to-commitment indexer equality check. Its token
is random per run and never printed. Synthetic proofData is mode 0600 inside a mode
0700 temporary directory and is unlinked immediately after native use; request buffers
and planted controls are zeroed. It deliberately does not claim physical-device
provenance. The combined phone-to-network demo remains pending until the protected app
client supports the same authentication.

## Skills consulted

Midnight Expert:

- `compact-core/skills/compact-witness-ts/SKILL.md`
- `compact-core/skills/compact-language-ref/SKILL.md`
- `compact-core/skills/compact-transaction-model/SKILL.md`
- `compact-core/skills/compact-privacy-disclosure/SKILL.md`
- `midnight-verify/skills/verify-by-execution/SKILL.md`
- `midnight-verify/skills/verify-correctness/SKILL.md`
- `midnight-verify/0.14.0/skills/verify-by-source/SKILL.md`
- `midnight-verify/0.14.0/skills/verify-by-wallet-source/SKILL.md`

MIDSKILLS: `.agents/skills/SOURCE.md` LOCAL DELTA first, then `midnightskill`,
`midnight-js`, `midnight-transactions`, `midnight-security`, and `indexer`. Their
language-0.22 examples are advisory; the pinned compiler 0.31.1 / language 0.23.0 /
runtime 0.16.0 / ledger-8 code and executable fixture are authoritative.

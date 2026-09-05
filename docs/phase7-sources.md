# Phase 7 sources: authenticated undeployed steward relay

Status: authenticated host relay accepted by the undeployed node and confirmed through
the indexer. This document records the mandatory source trail for
`scripts/steward-relay.mjs` and `scripts/phase7-live-relay-demo.mjs`. It describes a
trusted local developer-wallet boundary, not production custody or trustless DUST
sponsorship. An authenticated iPhone Simulator seal also landed and indexed on
2026-09-05; it exposed the finality-blocked HTTP response fixed below. That run is
simulator evidence, not a physical-iPhone claim.

## Native kapa queries

All eight searches used the native
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

7. **Node acceptance versus finality**

   > For Midnight wallet SDK 1.2.0 with wallet-sdk-facade 4.1.0 and ledger 8, what exact API separates node transaction-pool acceptance from later block inclusion and finality? Identify whether WalletFacade.submitTransaction waits for finality, which lower-level node-client or wallet operation returns the transaction identifier immediately after a successful broadcast, how submission errors before node acceptance surface, and why an indexer-backed commitment confirmation should report pending until indexed state appears.

   Relevant results:

   - [wallet facade submission](https://github.com/midnightntwrk/midnight-wallet/blob/main/packages/facade/src/index.ts) — the high-level facade waits for `Finalized`, so it is not the response boundary for a latency-bounded relay.
   - [submission service](https://github.com/midnightntwrk/midnight-wallet/blob/main/packages/capabilities/src/submission/submissionService.ts) — its public wait stage is `Submitted`, `InBlock`, or `Finalized`; `Submitted` is the narrow node/pool-acceptance boundary.
   - [node-client status mapping](https://github.com/midnightntwrk/midnight-wallet/blob/main/packages/node-client/src/effect/PolkadotNodeClient.ts) — ready/future/broadcast/retracted statuses emit `Submitted`, while inclusion and finality are later events.
   - [transaction-submission protocol](https://github.com/midnightntwrk/midnight-architecture/blob/main/apis-and-common-types/transaction-submission/Readme.md) — submission to the mempool and final transaction outcome are separate stages. Slip therefore returns after `Submitted` and lets the client poll indexed commitment state.

8. **Pending tracking when returning at `Submitted`**

   > For wallet-sdk-facade 4.1.0 and wallet-sdk-capabilities in the Midnight wallet SDK 1.2.0 stack, if WalletFacade.finalizeRecipe has already added the finalized transaction to pendingTransactionsService, is it valid to call the public wallet.submissionService.submitTransaction(finalizedTransaction, 'Submitted') to return immediately after node transaction-pool acceptance, then return finalizedTransaction.identifiers().at(-1), while calling wallet.revert(finalizedTransaction) if submission fails before Submitted? Explain how pending transaction tracking is later reconciled by wallet synchronization, and distinguish the Submitted event from InBlock and Finalized.

   Relevant results:

   - [pending transaction lifecycle](https://github.com/midnightntwrk/midnight-wallet/blob/main/packages/facade/src/index.ts) — finalization registers the transaction before submission; the facade's pending subscription later reverts indexed failure/partial success.
   - [pending service release notes](https://github.com/midnightntwrk/midnight-wallet/blob/main/packages/capabilities/CHANGELOG.md) — the service polls the indexer, retains pending transactions across the submission wait, and clears or reports them when their outcome appears.
   - [submission event types](https://github.com/midnightntwrk/midnight-wallet/blob/main/packages/node-client/src/effect/SubmissionEvent.ts) — `Submitted` carries the node transaction hash but no block; `InBlock` and `Finalized` add block identity and height.
   - Kapa's current-main result describes facade-wide reversion on submission error. Slip's pinned-source referee narrows that operation: it releases wallet reservations only for explicit `TransactionInvalidError`/RPC-1010 rejection. An error before observing `Submitted` is not proof that no broadcast occurred, so an ambiguous result retains the booked DUST and pending record for exact retry.

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
  is never omitted here. `finalizeRecipe` registers the finalized transaction with
  the pending service before returning it.
- `wallet-sdk-facade/dist/index.js:318-326` — the high-level submit path hard-codes
  `Finalized`. The relay deliberately uses the facade's public `submissionService`
  instead so its HTTP response can stop at `Submitted`, while returning the same
  `finalized.identifiers().at(-1)` transaction identifier.
- `wallet-sdk-capabilities/dist/submission/submissionService.d.ts:20-25` and
  `submissionService.js:20-45` — the pinned 3.3.1 service exposes the exact
  `Submitted | InBlock | Finalized` overload and forwards the requested stage to the
  node client.
- `wallet-sdk-node-client/dist/effect/NodeClient.js:19-28` and
  `PolkadotNodeClient.js:122-163` — the wait resolves on the first requested event;
  ready/future/broadcast/retracted produce `Submitted`, while `InBlock` and
  `Finalized` remain later stages.
- `wallet-sdk-node-client/dist/effect/NodeClientError.d.ts` and
  `PolkadotNodeClient.js` — pinned `_tag` shapes and the distinct explicit-invalid,
  finality-timeout, dropped, usurped, connection and raw submission paths. The relay
  walks nested `cause` links without rendering them and recognizes RPC code 1010 as
  explicit rejection.
- `wallet-sdk-capabilities/dist/pendingTransactions/pendingTransactionsService.js:42-57,73-145`
  — the already-started pending service polls indexed transaction status independently
  of the submission call, clears success, and exposes failure/partial success to the
  facade subscription.
- `wallet-sdk-dust-wallet/dist/v1/CoreWallet.js:65-82,94-100` and
  `wallet-sdk-facade/dist/index.js:641-653` — balancing moves selected DUST into the
  wallet's pending set; `revert(tx)` releases it. Re-adding a pending-service record
  does not recreate that DUST reservation, so ambiguous errors before observing
  `Submitted` retain the original booking. Only explicit invalid/RPC-1010 rejection
  releases it.
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
  remain in memory until its serialized wallet job completes. The relay request path
  never logs or echoes bodies, proof bytes, tokens, keys, or internal errors. The
  separate operator-only serve mode prints its one-time setup token plus bounded error
  diagnostics to the local terminal by design; that terminal is a sensitive trusted
  boundary.
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
  proof bytes can proceed. A failure before finalization is rolled back and evicted for
  a clean retry; after a finalized transaction exists, an ambiguous error before
  observing `Submitted` retains its DUST booking and resubmits that exact finalized
  transaction at most three times. Alternate bytes with the same intent
  receive `submission_uncertain`; they never replay the earlier proof, rebalance an
  ambiguous submission or select a second set of DUST.
- Authenticated submit traffic is limited to 12 requests per minute per relay process,
  with at most eight pre-`Submitted` or retrying wallet jobs. Success and unresolved intent tombstones are
  retained for the full 65-minute safety window and never evicted early. The 1,024-entry
  bound exceeds what the configured per-minute rate can admit across that window;
  on exhaustion the relay fails closed rather than forgetting live intent identity.
  These are developer-relay guardrails, not multi-tenant or production admission control.
- The relay calls the pinned submission service with `Submitted`, not the facade's
  finality-waiting submit method. A successful POST therefore means the node emitted
  `Submitted` and acknowledged submission; it does not mean inclusion, finality or
  contract success. Ambiguous
  errors retain DUST reservations and freeze new and already queued wallet work while
  exact finalized bytes are retried. Only `TransactionInvalidError` or RPC 1010 is
  terminal and releases the finalized transaction. This deliberately trades demo
  availability for wallet integrity.
- Pending-wallet state and coordinator tombstones are in memory. This single-process
  developer relay must not be restarted after `Submitted` and before indexed resolution
  or TTL expiry; the live referee waits for `SucceedEntirely` and exact indexed state
  before shutdown. A production relay would need durable pending-state and tombstone
  restoration.
- `GET /context/:address` queries the latest block, then fetches that contract state at
  the exact block hash and returns tagged bytes with block seconds. `GET
  /confirm/:commitment` scans only the configured contract's current public `seals`
  values. Absence immediately after `Submitted` is `pending`, not an error; presence is
  `confirmed`. The route does not infer `rejected` merely from absence. A later round
  reset can remove a seal, so this is immediate demo confirmation, not permanent history.
- The undeployed genesis wallet and tooling proof service are host-only. The proof
  service may prove the separate DUST balancing transaction; Slip's `sealPick` proof is
  already native and never goes there. No genesis key or relay token belongs in a
  release build.

The DEBUG simulator client can supply the same required bearer token. Its current
developer configuration is not a production credential store, and the server never
weakens authentication to accommodate a misconfigured client.

## Evidence matrix

| Evidence | What it establishes | What it does not establish |
|---|---|---|
| Phase 6 host referee | Ledger 8 derived the call binding; Slip's native prover made the `sealPick` proof; the node returned `SucceedEntirely`; indexed state contained the exact commitment. | The iPhone did not originate this live submission. Tooling proved setup calls and the wallet's separate DUST transaction. |
| Physical iPhone `NetworkSealingServiceTests` | Against an embedded post-create state, the phone executed, assembled and proved a 5,238-byte transaction; the planted device-secret pattern was absent. | Its stub relay acknowledged submit/confirm; there was no HTTP steward wallet, node or indexer. |
| Relay unit/policy tests | Authentication, HTTP boundaries, exact transaction allowlist, DUST-only wallet ordering, idempotency and privacy/error handling. | They do not prove live chain acceptance or phone provenance. |
| Phase 7 authenticated host relay demo | A fresh standard-path deployment supplied live public context; the native prover assembled `sealPick`; the exact proved/pre-binding bytes crossed authenticated loopback HTTP; the steward added only DUST; the node returned `SucceedEntirely`; relay confirmation and an independent indexer read contained the exact locally expected commitment. | The producer was the host referee, not an iPhone. Standard setup calls and the separate wallet DUST proof used the tooling proof service. |
| Authenticated iPhone Simulator → relay → devnet | A real simulator seal reached the authenticated relay, landed, and was visible in indexed contract state on 2026-09-05. | The pre-fix HTTP response exceeded the client timeout because it waited for finality; this change returns at `Submitted`. This is not physical-device evidence. |

The post-fix live relay referee on 2026-09-05 assembled the 5,238-byte proved/pre-binding
transaction in 1,256 ms, returned `SucceedEntirely` at block 3672, and independently
observed public
transaction identifier
`003ccd002962d3510b8a59dc9b63636f7003c15d207f108f86ff0ec2ce8106fd08`
and commitment
`e87cfcfb808dc9033999316359655f84ec7f06514f5ca709d904326148c533fe`.
These are one local-devnet observation, not latency promises or stable deployment IDs.

## Executable verification

`node --test scripts/steward-relay.test.mjs` covers configuration/authentication,
route and media-type policy, declared and chunked body caps, submit rate limiting,
non-echoed errors, the transaction allowlist dimensions, block-time conversion,
DUST-work serialization, byte/intent idempotency, invalid-versus-ambiguous outcomes,
TTL tombstone retention, queued-work freezing, bounded active work, input zeroing and
commitment lookup. It also models a later finality stage while proving POST returns at
`Submitted`, then checks `pending` before the synthetic indexed seal appears and
`confirmed` afterward; failure before observing `Submitted` remains an HTTP error.
Finalized identifiers are validated before broadcast, with invalid identifiers rolled
back before the submission service can run. A composed coordinator/wallet case proves
an ambiguous error retains DUST, blocks queued work, and retries the identical finalized
object without rebalancing.
An existing synthetic transaction fixture is
checked only when its explicit path is supplied as `SLIP_RELAY_FIXTURE_PATH`; tests do
not assume ignored proof artifacts exist in a fresh clone. Relay startup enumerates and
compares only `contracts/build/contract/`, never build-root proofData/preimage scratch.

`node scripts/phase7-live-relay-demo.mjs` creates a fresh contract through the pinned
standard setup path, stops that setup wallet, starts the actual steward runtime behind
an ephemeral authenticated loopback HTTP server, fetches exact state/time context,
executes and assembles the native seal, and requires `SucceedEntirely`, relay
confirmation, and an independent member-to-commitment indexer equality check. Its token
is random per run and, in the default self-contained path, never printed. Synthetic proofData is mode 0600 inside a mode
0700 temporary directory and is unlinked immediately after native use; request buffers
and planted controls are zeroed. It deliberately does not claim physical-device
provenance. The authenticated simulator-to-network run is separate evidence; a
physical-iPhone run remains owner-controlled.

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

# Phase 6 design v2: phone proof to ledger 8

Status: the narrow undeployed-network path is proven end to end. The local devnet
accepted a `sealPick` call assembled by ledger 8 and proved by Slip's native prover;
the indexer returned the exact commitment. The host referee uses the same runtime
`ProofData` encoding and native operation that MidnightKit exposes to the phone. The
app now assembles/proves through that native operation and has a steward-relay
abstraction; authenticated physical-device-to-relay acceptance remains a separate
Phase 7 gate. This document separates the verified native milestone from the
hardening still required before a real-wallet path.

Every Midnight claim and source line is recorded in `phase6-sources.md` (native kapa
queries 1–17, Midnight Expert, MIDSKILLS, pinned midnight-js 4.1.1 and ledger 8).

## Required phone path

```text
public indexer snapshot                    trusted iPhone process
  contract/Zswap state + parameters ─────▶ Compact execution + device-only witness
  block context, address, network          private transcript and ProofData stay here
                                                    │
                                                    ▼
                                      ledger add_calls / transcript partition
                                      derive transaction binding + prove locally
                                                    │
                              proved, unbalanced transaction (trusted-wallet handoff)
                                                    ▼
                                         approved wallet balance/sign/finalize
                                                    │
                          network boundary ── finalized transaction ─────▶ node
                                                                    │ verify/include
                                                                    ▼
                                                                 indexer
```

Assembly and proving are one trusted-process operation. Stock midnight-js cannot
construct the call from public context alone: the call prototype also contains the
private transcript outputs, aligned input/output and communication randomness produced
by local execution. Slip therefore must not export runtime `ProofData`, a proof
preimage, a private transcript or a witness to an external assembler. The phone imports
public chain context, assembles and proves locally, then hands the tagged
proved/pre-binding transaction only to an approved trusted wallet boundary. That
intermediate value is not a public network payload; only the finalized transaction is.

## Public context entering the device

The smallest safe input is a coherent chain snapshot, not a bag of independently
latest values:

| Public value | Source and use |
|---|---|
| Network ID | Exact ledger network (`undeployed` for the local referee); selects address and transaction rules. |
| Contract address and entry point | Identify the deployed contract call. The operation and deployed verifier key must be resolved from that contract's state. |
| `ContractState` | Canonical tagged bytes from the indexer, used for local reads and operation lookup. |
| `ZswapChainState` and `LedgerParameters` | Fetch with the contract state through `queryZSwapAndContractState` so transcript partitioning, costs, TTL rules and any offers use one associated block. |
| Complete block/query context | The associated block identity and Unix time in seconds, plus every public field read during execution. The identical values drive Compact execution and native replay. |
| Wallet public keys | Coin/encryption public keys needed by runtime execution; no secret or signing key belongs in this fetch. |
| TTL and any deliberately public/disclosed call values | Chosen under the associated ledger parameters and represented identically during execution and assembly. Circuit inputs are private by default; `sealPick` has no explicit call arguments. |
| Circuit artifacts | ZKIR and prover key bundled locally; the verifier identity is checked against the deployed operation. |

Pinned midnight-js 4.1.1's `queryZSwapAndContractState` tuple does not expose its
block hash or timestamp, and its provider implementation can substitute initial ledger
parameters when the indexed action lacks them. The phone transport must first pin an
explicit block reference/time, query the tuple at that block, and reject missing or
fallback parameters rather than silently mixing contexts.

Slip's current unitless `sealPick` produces no Zswap inputs, outputs or transients. That
permits an explicit empty-offer assertion in this one circuit; it is not permission for
a general assembler to discard Zswap state. Likewise, the current fresh-devnet fixture's
limited query context must not become the production interface.

## Private in-process material

The following never crosses the app's process boundary: `{choice, salt}`, private
state, witness return values, aligned private inputs/outputs, private transcript outputs,
the proof preimage, runtime `ProofData`, and communication-commitment randomness. They
are neither logged nor serialized for handoff. Wallet secret/signing keys remain inside
the separately approved wallet boundary and never enter Slip. Updated private state is
retained only after indexer-confirmed success.

The DEBUG `PublicProofArtifact` remains diagnostic-only and is absent from Release. It
is not an input to this transaction path.

## Binding and proof ordering

Ledger 8 first creates a `PrePartitionContractCall`. `add_calls` computes the
communication commitment, partitions the transcript with the applicable ledger
parameters, and places the call in an intent. `Transaction.prove` then derives the
binding input from the assembled transaction and asks Slip's native prover to prove that
exact statement.

Proof verification receives, in order:

1. the binding input covering address, entry point, transcript costs/effects and parent
   intent binding, including the guaranteed transcript's instruction count;
2. the communication commitment as a separate public field; and
3. guaranteed then fallible public transcript fields.

The communication commitment is not part of the first field. Formatting a proof made
for another binding cannot repair it.

`Prover.buildProvedCallTransaction(...)` is the preferred phone boundary because it
keeps assembly, binding derivation and proving in one native call. The lower-level
`Prover.prove(...bindingInput:)` remains useful for verification and for a future split
architecture, but a safe split would require an opaque in-process transaction handle:
derive a public big-endian `0x` binding string from that retained skeleton, prove it on
the phone, then attach the proof only after revalidating the unchanged skeleton. It must
never send serialized `ProofData` or a preimage to a coordinator.

## Native assembler requirements

The protected native operation now returns a tagged proved/pre-binding transaction, the
shape ledger-WASM deserializes with `('signature', 'proof', 'pre-binding')`. Before it is
a production boundary, its implementation must additionally:

- resolve the circuit operation and verifier identity from the live deployed
  `ContractState`, rejecting a mismatch with bundled artifacts;
- consume `LedgerParameters` from the same indexed block, including its runtime cost
  model, rather than `initialParameters()` or a separately bundled default;
- preserve the complete Compact `QueryContext` and all public read results used to
  create `ProofData`;
- sample fresh cryptographic communication randomness and retain it only in process;
- accept and correctly partition Zswap inputs/outputs/transients, while explicitly
  asserting that current unitless `sealPick` has none; and
- return named, sanitized errors without transcript, witness, proof-preimage or key
  content.

The verified fresh-devnet assembler currently uses the deployed state and address but a
bundled verifier, initial ledger parameters/cost model, zero communication randomness,
a partial query context and empty Zswap values. Those limits explain why its passing
referee is a narrow milestone, not a general transaction builder.

## Wallet, submission and confirmation

The native result is already proved but unbalanced. It includes pre-binding material and
must be treated as a sensitive trusted-wallet handoff, not sent to the node. The wallet
selects value/DUST inputs, signs its recipe, proves the separate balancing transaction as
needed and performs final binding. The app submits only the finalized bytes to the node
and waits for an indexer result with timeout/cancellation.
Success requires both `SucceedEntirely` and the expected commitment in indexed contract
state; RPC acceptance alone is insufficient.

The host referee uses the undeployed genesis wallet and local proof service only for
standard setup calls and the wallet's separate DUST proof. Slip's `sealPick` call proof
comes from the native prover and never calls the proof server. A real device needs an
approved wallet custody and authorization design; no genesis secret, proof-server
fallback or hidden signing path may ship in the app.

## Verified gate and payload invariant

`scripts/phase6-live-referee.mjs` deployed, enrolled and created through pinned
midnight-js; captured an indexed block and queried the contract state at that exact block
hash; executed `sealPick` locally; invoked native transaction assembly/proving; let the
genesis wallet balance/finalize; and submitted. This anchors the referee's contract state
and time, but it does not exercise the future Zswap/ledger-parameter transport described
above.
The node returned `SucceedEntirely`, and the indexer returned the byte-identical public
commitment. A positive control planted the exact 32-byte synthetic witness pattern into
a copy-shaped buffer and detected it; the pristine finalized transaction excluded it.
The separate diagnostic-artifact serializer tests retain their own planted-pattern
positive control.

That is the measured claim: **Slip's prover made the bound contract-call proof, and a
Midnight node verified it.** A single authenticated phone-to-relay-to-node run, wallet
custody, native hardening and release-network submission remain separate work.

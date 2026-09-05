# Phase 6 design: phone proof to ledger 8

Status: design established; app submission is blocked at the frozen native boundary.
The same local devnet accepted a standard control seal and rejected the current
app-generated proof as `InvalidProof`. See `phase6-sources.md` for queries, URLs,
source lines and executable evidence.

## Required transaction path

```text
trusted iPhone process
  current public state + device-only witness/private state
    → execute Compact circuit
    → build ContractCallPrototype and unproven transaction
    → compute the transaction/call binding input
    → prove that exact bound preimage on device
    → balance value and DUST, sign, then bind
      ───────────── public finalized transaction ─────────────▶ node
                                                               │ verify/include
                                                               ▼
                                                            indexer
```

The call cannot be assembled from a proof and commitment. Ledger 8 also requires the
contract address and operation, partitioned public transcripts, private transcript
outputs, aligned input/output, communication randomness and the key location. The
private pieces stay inside the trusted process; they are inputs to local assembly and
proving, not network payload fields.

Proof generation comes after call assembly because the proof’s first public input binds
the contract address, entry point, transcript costs/effects and length, parent intent
binding and communication commitment. `Transaction.prove` supplies that computed field
through `overwriteBindingInput`. Wrapping older raw proof bytes in a ledger serialization
header cannot change the statement they prove.

After the call proof exists, wallet-sdk balances shielded/unshielded value and adds DUST
for fees, signs the relevant segments, proves the wallet’s balancing transaction, and
binds/merges the result. Only the finalized serialized transaction goes to the node.
Finality and the new public contract state are confirmed through the indexer with an
application-owned timeout/cancellation policy.

## Slip’s present boundary

`ContractRuntime` and `Prover` correctly demonstrate local execution and proof generation,
but their proof is intentionally isolated from a network transaction. The protected Rust
bridge currently fixes `binding_input = 0` and communication randomness to zero, proves
immediately, and returns only raw proof bytes. Its C API cannot:

- consume current on-chain state and a contract address;
- construct a ledger-8 `ContractCallPrototype`/unproven transaction;
- accept the binding overwrite computed for that transaction;
- return a ledger-serialized unbound transaction; or
- balance/sign/finalize a wallet transaction.

The allowed new Swift `MidnightKit/Network` directory cannot add those native symbols.
There is no official Swift wallet/transaction SDK to call instead, and shipping a second
midnight-js runtime in JavaScriptCore would duplicate sensitive state and still require
a native wallet/prover boundary. A Swift-only HTTP submitter would therefore be unsafe:
it could broadcast bytes but cannot create the valid bytes.

## Narrowest safe implementation

The next authorized native change should expose one transaction-aware operation, not a
collection of Swift reimplementations:

1. Inside the native ledger-8 bridge, execute/assemble against supplied **public** chain
   context while keeping the witness, private state and private transcript in process.
2. Compute the final call binding and prove with it before releasing any payload.
3. Return a ledger-serialized unbound proved transaction plus only public metadata needed
   by the UI (commitment and timings).
4. For the undeployed demo, pass that unbound transaction to a device-local genesis-wallet
   adapter to balance DUST, sign and bind, then submit to `ws://localhost:9944` and confirm
   through `http://localhost:8088/api/v4/graphql`.
5. For a real device/network, replace the demo genesis key with an approved wallet custody
   and authorization design. A genesis secret must never ship in a release build.

The app must never call the proof server. No retry may fall back to remote proving. Private
state is installed only after indexer-confirmed success; errors crossing into Swift remain
named and sanitized.

## Payload/privacy gate

The DEBUG diagnostic export and its serializer are absent from Release builds. Its JSON
has exactly two fields, `proof` and `commitment`, and decoding rejects extra fields. A
32-byte planted witness test scans raw JSON, text encodings and decoded binary fields;
the clean payload excludes it and a valid JSON proof field contaminated with that pattern
is detected. The exporter removes any previous artifact before starting, so a failed run
cannot be mistaken for fresh evidence.

This export is useful diagnostic evidence, but it is not a submission payload and cannot
be promoted into one. Implementation resumes only after the owner authorizes the protected
native transaction-aware API and chooses the devnet/real-wallet boundary.

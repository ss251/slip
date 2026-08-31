# Contract simulator tests

Two runnable probes against the compiled contract. No test framework — plain Node,
so they run before the TS workspace exists.

- `slip.test.mjs` — 28 assertions: steward authorization, crew roster, sealing
  (membership / double-seal / deadline), reveal (wrong salt, flipped choice,
  double-reveal), settle, and per-round state reset + commitment replay-binding.
- `leak.mjs` — privacy probe: asserts the salt never appears in the public
  transaction transcript and that the choice is not recoverable from public
  state by brute force.

## Running

These need the generated contract as an ESM module plus the runtime version the
compiler emits (`compact compile -- --runtime-version`).

```sh
compact compile contracts/slip.compact contracts/build

mkdir -p /tmp/slip-sim && cd /tmp/slip-sim
npm init -y
npm install @midnight-ntwrk/compact-runtime@0.19.0 @midnight-ntwrk/midnight-js-network-id
cp -R <repo>/contracts/build/contract ./slipcontract
echo '{"type":"module"}' > slipcontract/package.json   # generated code is ESM
cp <repo>/contracts/test/*.mjs .

node slip.test.mjs   # exits non-zero on failure
node leak.mjs
```

Fold these into the real TS test workspace (vitest, per `.claude/docs/testing.md`)
when it lands; until then they are the contract's evidence.

## Harness notes (cost us time — worth keeping)

- `Contract#initialState` and every circuit are **async** — `await` them.
- `createConstructorContext(initialPrivateState, coinPublicKey)`.
- `createCircuitContext(circuitId, address, coinPublicKey, contractState,
  privateState, stateProvider, gasLimit, costModel, time, parentBlockHash,
  reentrancyGuard)` — `time` is a `Date` and is what drives `blockTimeLt` /
  `blockTimeGte`, so deadlines are testable.
- Thread state forward with
  `res.context.callContext.currentQueryContext.state` and
  `res.context.callContext.currentPrivateState`.
- Seed the first call from `initialState(...).currentContractState.data`.

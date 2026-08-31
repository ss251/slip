# Contract simulator tests

Two runnable probes against the compiled contract. No test framework — plain Node,
so they run before the TS workspace exists.

- `slip.test.mjs` — 53 assertions across ten sections (below).
- `leak.mjs` — privacy probe: asserts neither the device secret nor the derived
  salt appears in the public transaction transcript, and that the choice is not
  recoverable from public state by brute force. Exits non-zero on any leak.

## What `slip.test.mjs` covers

| § | Area |
|---|---|
| 1 | Steward authorization on `createSlip` / `enrollMember` |
| 2 | Crew roster assembly in `draft`; duplicate enrollment |
| 3 | **Deadline bounds** — both ends of the seal window; all four phase boundaries derived |
| 4 | **Roster lock** — enrollment frozen across every phase |
| 5 | Sealing: membership, double-seal, deadline, commitment opacity |
| 6 | **Salt derivation** — per (member, round), no host witness |
| 7 | **The product moment** — reveals open the instant sealing closes |
| 8 | **Settle** — bounded at both ends, after reveals close |
| 9 | **Dispute** — eligibility, attribution, void semantics, no re-settle |
| 10 | **Seal-wipe protection** — no clearing at any point before the round closes |
| 11 | Round 2: a dispute landing after the settle window |
| 12 | Round 3: settled and unchallenged (the happy ending) |
| 13 | Round 4: steward never settles — no brick, no fake result |
| 14 | Next round: state reset, roster survival, replay binding |

### The round is four phases

```
..< sealDeadline                   SEAL
[sealDeadline, revealDeadline)     REVEAL   (24h) opens the INSTANT sealing closes
[revealDeadline, settleDeadline)   SETTLE   (12h) steward records the outcome
[.., disputeDeadline)              DISPUTE  (12h) any member who sealed may void it
>= disputeDeadline                 CLOSED
```

`phases(openedAt)` in the harness derives all four boundaries from one timestamp;
use it rather than hand-computing offsets, so a change to a window constant only
needs editing in one place. The suite runs five rounds because several properties
are only observable on a round that ended a particular way — disputed early,
disputed late, settled-and-unchallenged, never-settled.

### Cast list

`ALICE`, `BOB`, `CARL`, `DANA` are enrolled; `MALLORY` never is. Their roles in
round 1 are load-bearing and not interchangeable:

- **CARL** seals and never reveals — he is the "sealed but did not disclose"
  disputer, and his unopened seal is what proves the reveal window closes.
- **DANA** is enrolled and never seals — she is the "crew member who did not
  participate" whose dispute must be refused.
- **MALLORY** is outside the crew entirely.

### Time is Unix SECONDS. This is load-bearing.

The runtime writes `createCircuitContext`'s `time` argument into
`block.secondsSinceEpoch` verbatim — literally `BigInt(time)`
(`compact-runtime/dist/circuit-context.js`, `createInitialQueryContext`).

An earlier version of this harness passed `new Date(5000)`. `BigInt(new Date(5000))`
is `5000`, so the ledger held *five milliseconds past the epoch* in a field
mainnet reads as seconds. Every assertion still passed, because every constant in
the suite was mislabeled by the same factor — the suite was unit-agnostic and
therefore structurally incapable of catching a seconds-vs-milliseconds
regression. That is the exact bug class that could brick this contract
permanently, so the harness now uses realistic Unix-second magnitudes
(`NOW = 1788000000`) and passes plain numbers, never `Date` objects.

**If you add a test, pass seconds. Never pass a `Date`.**

### The new regression tests

- **Milliseconds-scale deadline is rejected** — `createSlip` with
  `BigInt(deadline) * 1000n` (what `Date.now()` would hand it) fails the
  365-day upper bound instead of silently arming an unreachable round.
- **Too-soon deadline is rejected** — 60 s out fails the 5-minute floor. Two
  more cases (`100n` and `0n`) exercise the underflow-guard branch, where the
  bound falls back to 0 rather than subtracting past zero.
- **A deadline just inside 365 days is accepted** — the upper bound is a bound,
  not a blanket refusal.
- **Reveals open the instant sealing closes** — §7, at one-second resolution:
  the identical reveal is rejected at `sealDeadline - 1` and accepted at exactly
  `sealDeadline`. This is the product's signature moment and the regression that
  matters most; a previous revision inserted a settle window here and pushed it
  back two hours.
- **Settle is bounded at both ends** — §8. Rejected during the reveal window, at
  `revealDeadline - 1`, at exactly `settleDeadline` (boundary), and after. Both
  reserved sentinels (`2`, `3`) are rejected as outcome arguments, so neither
  "no result" state can be forged by a settle.
- **Dispute** — §9. Rejected for a non-crew caller, for an enrolled member who
  did not seal (Dana), and after `disputeDeadline`. Accepted for Carl, who sealed
  and never revealed — eligibility is participation, not disclosure. The void is
  checked to be distinguishable (`status == disputed`, `outcome == 3`, not the
  never-settled `2`), attributable (`disputedBy == carlId`), and terminal (no
  re-settle, no second dispute). **Both terminal-state tests deliberately run at
  a block time still inside the settle and dispute windows**, so they reject on
  *status* rather than incidentally on time — otherwise they would pass without
  testing anything.
- **Seal-wipe protection** — §10 attempts `createSlip` at four points across the
  round (reveal window, settle window, dispute window, one second before close)
  and confirms every seal survives. Gating on status rather than time would have
  allowed the settle-window and dispute-window cases.
- **A round can end three ways, all distinguishable** — §11 disputed after the
  settle window closed, §12 settled and unchallenged, §13 never settled. §13 also
  checks the un-brick: `createSlip` still works after a round nobody settled.
  That matters because gating `createSlip` on status rather than time would let a
  missed settle window brick the contract permanently.
- **Salt is derived per (member, round)** — `pickSaltOf` differs across rounds
  for one member and across members in one round, and is deterministic so a
  device can re-derive it to open its seal. A further assertion checks the
  *on-chain* seal equals `pickCommitment(round, memberId, choice, pickSaltOf(...))`,
  which is what proves the circuit actually uses the derived value. Note that
  comparing commitments alone would prove nothing here: `pickCommitment` binds
  round and memberId directly, so commitments differ even with a constant salt.
  The `pickSaltOf` inequalities are what carry the claim.
- **`enrollMember` is rejected while a slip is open** — checked both mid-seal
  and mid-reveal. The roster is locked for the whole life of a slip, not merely
  until the seal deadline; members are added between rounds (`draft`/`settled`).
- **Reveal after the reveal window closes is rejected** — a third member seals
  and never opens, so the upper bound of the window is exercised on a seal that
  is otherwise valid.
- **Out-of-range picks are rejected at both `sealPick` and `reveal`** — the only
  way to reach either range check is a host that lies about `localPick()`, so no
  honest flow exercises them and they need explicit tests. The `reveal` case
  matters most: it is documented as defence-in-depth and is transitively
  unreachable today, so the test asserts it fails on the *range* check
  (`"pick must be 0 (No) or 1 (Yes)"`) rather than on the commitment mismatch
  that would otherwise catch it. If a future change breaks that transitive
  argument, this test fails instead of the tally's `else` branch quietly becoming
  a catch-all.

## Running

`npm test` from `contracts/` does the whole thing (`pretest` compiles with
`--skip-zk` and links `build/contract` as `test/slipcontract`).

Manually, these need the generated contract as an ESM module plus the runtime
version the compiler emits (`compact compile -- --runtime-version`):

```sh
compact compile contracts/slip.compact contracts/build

mkdir -p /tmp/slip-sim && cd /tmp/slip-sim
npm init -y
npm install @midnight-ntwrk/compact-runtime@0.19.0 @midnight-ntwrk/midnight-js-network-id
cp -R <repo>/contracts/build/contract ./slipcontract
echo '{"type":"module"}' > slipcontract/package.json   # generated code is ESM
cp <repo>/contracts/test/*.mjs .

node slip.test.mjs   # exits non-zero on failure
node leak.mjs        # exits non-zero on a leak
```

Fold these into the real TS test workspace (vitest, per `.claude/docs/testing.md`)
when it lands; until then they are the contract's evidence.

## Harness notes (cost us time — worth keeping)

- `Contract#initialState` and every circuit are **async** — `await` them.
- `createConstructorContext(initialPrivateState, coinPublicKey)`.
- `createCircuitContext(circuitId, address, coinPublicKey, contractState,
  privateState, stateProvider, gasLimit, costModel, time, parentBlockHash,
  reentrancyGuard)` — `time` is a **`number` of Unix seconds** (the type is
  `time?: number`; it is passed straight to `BigInt()`). A `Date` is accepted by
  JS and silently means milliseconds. See the warning above.
- Thread state forward with
  `res.context.callContext.currentQueryContext.state` and
  `res.context.callContext.currentPrivateState`.
- Seed the first call from `initialState(...).currentContractState.data`.
- `rejects()` snapshots and restores state, so a rejected call cannot leave the
  suite on a mutated ledger. §3 additionally resets to `initialState` by hand
  after the "just inside 365 days" case, because that one *succeeds* and would
  otherwise leave a round open.
- Witnesses are now only `localSecretKey` and `localPick`. `localPickSalt` was
  removed from the contract; passing it does nothing.

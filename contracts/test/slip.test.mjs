import * as rt from '@midnight-ntwrk/compact-runtime';
import { setNetworkId } from '@midnight-ntwrk/midnight-js-network-id';
import { Contract, ledger, pureCircuits } from './slipcontract/index.js';

setNetworkId('undeployed');

const ADDR = rt.sampleContractAddress();
const CPK = { bytes: new Uint8Array(32) };

const k = (b) => { const x = new Uint8Array(32); x[0] = b; return x; };
const STEWARD = k(0x01), ALICE = k(0x02), BOB = k(0x03), CARL = k(0x04),
      DANA = k(0x05), MALLORY = k(0x09);

const YES = 1n, NO = 0n;
const NO_OUTCOME = 2n;   // sentinel: nobody recorded a result
const DISPUTED = 3n;     // sentinel: a result was recorded and then voided

// Status enum ordinals
const DRAFT = 0, OPEN = 1, SETTLED = 2, DISPUTED_STATUS = 3;

// ---------------------------------------------------------------------------
// Clock — UNIX SECONDS, and nothing but.
//
// The runtime stores whatever is handed to `createCircuitContext`'s `time`
// argument verbatim as `block.secondsSinceEpoch` (BigInt(time)). An earlier
// version of this harness passed `new Date(5000)`, which BigInt()s to 5000 —
// five *milliseconds* past the epoch, sitting in a field mainnet reads as
// seconds. Every assertion still passed, because every value in the suite was
// mislabeled by the same factor: the suite was unit-agnostic and structurally
// incapable of catching a seconds-vs-milliseconds regression. That is exactly
// the bug class that can brick this contract, so the harness uses realistic
// Unix-second magnitudes and passes plain numbers.
// ---------------------------------------------------------------------------
const NOW = 1788000000;              // 2026-09-01T13:20:00Z, a real Unix second
const SEAL_WINDOW = 3600;            // our choice per round, not a contract constant
const REVEAL_WINDOW = 86400;         // contract constant: 24h
const SETTLE_WINDOW = 43200;         // contract constant: 12h
const DISPUTE_WINDOW = 43200;        // contract constant: 12h

// The round timeline. Reveals open the INSTANT sealing closes; the steward
// settles after reveals close; any participating member may then challenge.
//
//   ..< D   seal  |  [D, R)  reveal  |  [R, S)  settle  |  [.., P)  dispute
const phases = (openedAt) => {
  const D = openedAt + SEAL_WINDOW;
  const R = D + REVEAL_WINDOW;
  const S = R + SETTLE_WINDOW;
  const P = S + DISPUTE_WINDOW;
  return { D, R, S, P };
};

// Five rounds, each opened just after the previous one fully closed.
const r1 = phases(NOW);
const r2 = phases(r1.P + 60);
const r3 = phases(r2.P + 60);
const r4 = phases(r3.P + 60);
const r5open = r4.P + 60;

const w = (sk, pick) => ({
  localSecretKey: ({ privateState }) => [privateState, sk],
  localPick: ({ privateState }) => [privateState, pick],
});

let state, priv;

async function call(sk, pick, id, timeSeconds, ...args) {
  const c = new Contract(w(sk, pick));
  // runtime 0.16.0 signature: (contractAddress, coinPublicKey, contractState,
  // privateState, gasLimit?, costModel?, time?). It differs from 0.19.0's, which
  // takes a leading circuit id — if you move the toolchain, re-read
  // compact-runtime/dist/circuit-context.d.ts rather than assuming.
  const ctx = rt.createCircuitContext(
    ADDR, CPK, state, priv,
    undefined, undefined, timeSeconds
  );
  const res = await c.impureCircuits[id](ctx, ...args);
  state = res.context.currentQueryContext.state;
  priv = res.context.currentPrivateState;
  return res;
}

let pass = 0, fail = 0;
function ok(label, cond, detail = '') {
  if (cond) { pass++; console.log(`  PASS  ${label}${detail ? ' — ' + detail : ''}`); }
  else { fail++; console.log(`  FAIL  ${label}${detail ? ' — ' + detail : ''}`); }
}
async function rejects(label, fn) {
  const snapshot = state, snapshotPriv = priv;
  try {
    await fn();
    state = snapshot; priv = snapshotPriv;
    fail++; console.log(`  FAIL  ${label} — expected rejection, transaction SUCCEEDED`);
  } catch (e) {
    state = snapshot; priv = snapshotPriv;
    pass++; console.log(`  PASS  ${label} — rejected: "${String(e.message).split('\n')[0].slice(0, 70)}"`);
  }
}
const L = () => ledger(state);
const eq = (a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)) === 0;

async function main() {
  const c = new Contract(w(STEWARD, NO));
  const init = await c.initialState(rt.createConstructorContext(undefined, CPK));
  state = init.currentContractState.data;
  priv = init.currentPrivateState;

  const aliceId = pureCircuits.memberIdOf(ALICE);
  const bobId = pureCircuits.memberIdOf(BOB);
  const carlId = pureCircuits.memberIdOf(CARL);
  const danaId = pureCircuits.memberIdOf(DANA);

  const enrollAll = async () => {
    for (const id of [aliceId, bobId, carlId, danaId]) {
      await call(STEWARD, NO, 'enrollMember', NOW, id);
    }
  };

  ok('a fresh contract has no recorded outcome, not a fabricated "No"',
    L().outcome === NO_OUTCOME, `outcome=${L().outcome} (2 = none)`);

  console.log('\n[1] Authorization — steward-only operations');
  await rejects('non-steward cannot createSlip',
    () => call(MALLORY, NO, 'createSlip', NOW, new Uint8Array(32), BigInt(r1.D)));
  await rejects('non-steward cannot enrollMember',
    () => call(MALLORY, NO, 'enrollMember', NOW, aliceId));

  console.log('\n[2] Crew roster — assembled while the contract is in draft');
  await enrollAll();
  ok('crew has 4 members', L().crew.size() === 4n, `size=${L().crew.size()}`);
  await rejects('duplicate enrollment rejected',
    () => call(STEWARD, NO, 'enrollMember', NOW, aliceId));

  console.log('\n[3] Deadline bounds — the seal window is bounded at both ends');
  await rejects('deadline in the past rejected',
    () => call(STEWARD, NO, 'createSlip', NOW, k(0x77), BigInt(NOW - 3600)));
  await rejects('too-soon deadline rejected (60s, under the 5-minute floor)',
    () => call(STEWARD, NO, 'createSlip', NOW, k(0x77), BigInt(NOW + 60)));
  // Exercises the underflow guard: a deadline below the 300s floor takes the
  // `0` fallback branch instead of the subtraction, and must still be rejected.
  await rejects('sub-300s absolute deadline rejected without underflowing',
    () => call(STEWARD, NO, 'createSlip', NOW, k(0x77), 100n));
  await rejects('zero deadline rejected',
    () => call(STEWARD, NO, 'createSlip', NOW, k(0x77), 0n));
  await rejects('MILLISECOND-scale deadline rejected (the Date.now() bug)',
    () => call(STEWARD, NO, 'createSlip', NOW, k(0x77), BigInt(r1.D) * 1000n));
  await rejects('deadline beyond 365 days rejected',
    () => call(STEWARD, NO, 'createSlip', NOW, k(0x77), BigInt(NOW + 31536000 + 60)));
  await call(STEWARD, NO, 'createSlip', NOW, k(0x77), BigInt(NOW + 31536000 - 60));
  ok('a deadline just inside 365 days is accepted', L().status === OPEN);
  // Roll back and open the round the rest of the suite uses.
  state = init.currentContractState.data; priv = init.currentPrivateState;
  await enrollAll();
  await call(STEWARD, NO, 'createSlip', NOW, k(0x77), BigInt(r1.D));
  ok('steward can createSlip with a sane deadline',
    L().status === OPEN && L().roundId === 1n, `status=${L().status} round=${L().roundId}`);
  ok('all four phase boundaries are derived, not caller-supplied',
    L().sealDeadline === BigInt(r1.D) && L().revealDeadline === BigInt(r1.R)
      && L().settleDeadline === BigInt(r1.S) && L().disputeDeadline === BigInt(r1.P),
    `seal -> reveal +${REVEAL_WINDOW} -> settle +${SETTLE_WINDOW} -> dispute +${DISPUTE_WINDOW}`);
  ok('a freshly opened round has no recorded outcome and no disputer',
    L().outcome === NO_OUTCOME && eq(L().disputedBy, new Uint8Array(32)));

  console.log('\n[4] Roster lock — enrollment is frozen for the life of a slip');
  await rejects('enrollMember rejected during the seal phase',
    () => call(STEWARD, NO, 'enrollMember', NOW + 600, pureCircuits.memberIdOf(MALLORY)));
  await rejects('enrollMember rejected during the reveal window',
    () => call(STEWARD, NO, 'enrollMember', r1.D + 60, pureCircuits.memberIdOf(MALLORY)));
  await rejects('enrollMember rejected during the settle window',
    () => call(STEWARD, NO, 'enrollMember', r1.R + 60, pureCircuits.memberIdOf(MALLORY)));

  console.log('\n[5] Sealing — privacy, membership, double-seal, deadline');
  await rejects('outsider (not in crew) cannot seal',
    () => call(MALLORY, YES, 'sealPick', NOW + 600));
  // The range check is only reachable by a host that lies about localPick(), so
  // it needs an explicit test — no honest flow ever produces a value >= 2.
  await rejects('out-of-range pick rejected at seal',
    () => call(ALICE, 2n, 'sealPick', NOW + 600));
  await call(ALICE, YES, 'sealPick', NOW + 600);
  await call(BOB, NO, 'sealPick', NOW + 600);
  await call(CARL, YES, 'sealPick', NOW + 600);
  // Dana is enrolled but deliberately never seals — she is the "crew member who
  // did not participate" used by the dispute eligibility test in [7].
  ok('three of four members sealed', L().seals.size() === 3n, `size=${L().seals.size()}`);

  // PRIVACY PROBE: is the choice inferable from public state?
  const aliceCommit = L().seals.lookup(aliceId);
  const aliceSalt1 = pureCircuits.pickSaltOf(1n, ALICE);
  ok('commitment reproduces only with the exact {choice, derived salt}',
    eq(aliceCommit, pureCircuits.pickCommitment(1n, aliceId, YES, aliceSalt1)));
  ok('commitment is opaque without the salt',
    !eq(aliceCommit, pureCircuits.pickCommitment(1n, aliceId, YES, new Uint8Array(32))),
    'guessing the choice with a wrong salt does not match');
  ok('two members, same round, different picks -> unrelated commitments',
    !eq(aliceCommit, L().seals.lookup(bobId)));

  await rejects('double-seal rejected (same member, same round)',
    () => call(ALICE, NO, 'sealPick', NOW + 600));
  await rejects('sealing after the deadline rejected',
    () => call(DANA, YES, 'sealPick', r1.D));

  console.log('\n[6] Salt derivation — per (member, round), no host witness');
  ok('salt differs across rounds for the same member',
    !eq(pureCircuits.pickSaltOf(1n, ALICE), pureCircuits.pickSaltOf(2n, ALICE)));
  ok('salt differs across members in the same round',
    !eq(pureCircuits.pickSaltOf(1n, ALICE), pureCircuits.pickSaltOf(1n, BOB)));
  ok('salt is deterministic — the same device re-derives it to open its seal',
    eq(pureCircuits.pickSaltOf(1n, ALICE), pureCircuits.pickSaltOf(1n, ALICE)));
  // The commitment binds round and memberId directly, so differing commitments
  // alone would NOT prove the salt varies. The pickSaltOf inequalities above are
  // what carry the per-(member, round) claim.
  ok('same member, different rounds -> different commitments',
    !eq(pureCircuits.pickCommitment(1n, aliceId, YES, pureCircuits.pickSaltOf(1n, ALICE)),
        pureCircuits.pickCommitment(2n, aliceId, YES, pureCircuits.pickSaltOf(2n, ALICE))));
  ok('different members, same round -> different commitments',
    !eq(pureCircuits.pickCommitment(1n, aliceId, YES, pureCircuits.pickSaltOf(1n, ALICE)),
        pureCircuits.pickCommitment(1n, bobId, YES, pureCircuits.pickSaltOf(1n, BOB))));
  ok('the contract actually seals with the derived salt (on-chain value matches)',
    eq(L().seals.lookup(carlId),
       pureCircuits.pickCommitment(1n, carlId, YES, pureCircuits.pickSaltOf(1n, CARL))));

  console.log('\n[7] THE PRODUCT MOMENT — reveals open the instant sealing closes');
  await rejects('reveal one second before the seal deadline rejected',
    () => call(ALICE, YES, 'reveal', r1.D - 1));
  await call(ALICE, YES, 'reveal', r1.D);
  ok('the SAME reveal accepted at EXACTLY the seal deadline',
    L().reveals.lookup(aliceId) === YES,
    'no settle window in between, nobody waiting on the steward');
  await rejects('reveal with FLIPPED CHOICE rejected',
    () => call(BOB, YES, 'reveal', r1.D + 60));
  await rejects('reveal by someone who never sealed rejected',
    () => call(MALLORY, YES, 'reveal', r1.D + 60));
  await rejects('double-reveal rejected',
    () => call(ALICE, YES, 'reveal', r1.D + 60));
  // Defence-in-depth range check. Uses CARL, who has sealed and NOT yet
  // revealed, so it fails on the RANGE assert rather than on an earlier guard.
  await rejects('out-of-range pick rejected at reveal (defence in depth)',
    () => call(CARL, 2n, 'reveal', r1.D + 60));
  await call(BOB, NO, 'reveal', r1.D + 60);
  ok('tallies correct', L().tallyYes === 1n && L().tallyNo === 1n,
    `yes=${L().tallyYes} no=${L().tallyNo}`);
  // Carl deliberately never opens — he is the "sealed but did not reveal"
  // disputer in [8], and his seal proves the reveal window closes.
  await rejects('reveal after the reveal window has closed rejected',
    () => call(CARL, YES, 'reveal', r1.R));

  console.log('\n[8] Settle — bounded at both ends, after reveals close');
  await rejects('settle during the reveal window rejected',
    () => call(STEWARD, NO, 'settle', r1.D + 60, YES));
  await rejects('settle one second before reveals close rejected',
    () => call(STEWARD, NO, 'settle', r1.R - 1, YES));
  await rejects('settle at exactly settleDeadline rejected (boundary)',
    () => call(STEWARD, NO, 'settle', r1.S, YES));
  await rejects('settle after the settle window rejected',
    () => call(STEWARD, NO, 'settle', r1.S + 3600, YES));
  await rejects('non-steward cannot settle',
    () => call(MALLORY, NO, 'settle', r1.R + 60, YES));
  await rejects('outcome out of range rejected',
    () => call(STEWARD, NO, 'settle', r1.R + 60, 7n));
  await rejects('the "no result" sentinel cannot be written as a real outcome',
    () => call(STEWARD, NO, 'settle', r1.R + 60, NO_OUTCOME));
  await rejects('the "disputed" sentinel cannot be written as a real outcome',
    () => call(STEWARD, NO, 'settle', r1.R + 60, DISPUTED));
  await call(STEWARD, NO, 'settle', r1.R + 60, YES);
  ok('settled at the start of the settle window',
    L().status === SETTLED && L().outcome === YES,
    `status=${L().status} outcome=${L().outcome}`);
  await rejects('double-settle rejected',
    () => call(STEWARD, NO, 'settle', r1.R + 120, NO));

  console.log('\n[9] Dispute — any member who SEALED may void a wrong outcome');
  await rejects('dispute by a non-crew member rejected',
    () => call(MALLORY, NO, 'dispute', r1.R + 120));
  await rejects('dispute by a crew member who did NOT seal rejected (Dana)',
    () => call(DANA, NO, 'dispute', r1.R + 120));
  await rejects('dispute after the dispute window has closed rejected',
    () => call(ALICE, NO, 'dispute', r1.P));
  // Carl sealed but never revealed. He can still see the outcome is wrong, and
  // has standing to say so — eligibility is participation, not disclosure.
  await call(CARL, NO, 'dispute', r1.R + 120);
  ok('a sealed-but-unrevealed member CAN dispute',
    L().status === DISPUTED_STATUS, `status=${L().status} (3 = disputed)`);
  ok('the outcome is voided with a DISTINCT sentinel, not the never-settled one',
    L().outcome === DISPUTED, `outcome=${L().outcome} (2 = never settled, 3 = disputed)`);
  ok('the dispute is attributable on-chain', eq(L().disputedBy, carlId),
    'a client can render who challenged it without trawling transactions');
  await rejects('a disputed round cannot be re-settled',
    () => call(STEWARD, NO, 'settle', r1.R + 180, NO));
  await rejects('a disputed round cannot be disputed again',
    () => call(ALICE, NO, 'dispute', r1.R + 180));
  ok('reveals and seals survive the dispute — only the outcome was voided',
    L().seals.size() === 3n && L().reveals.size() === 2n,
    `seals=${L().seals.size()} reveals=${L().reveals.size()}`);

  console.log('\n[10] Seal-wipe protection — no clearing before the round closes');
  await rejects('createSlip during the reveal window rejected',
    () => call(STEWARD, NO, 'createSlip', r1.D + 60, k(0x88), BigInt(r1.D + 200000)));
  await rejects('createSlip during the settle window rejected',
    () => call(STEWARD, NO, 'createSlip', r1.R + 60, k(0x88), BigInt(r1.R + 200000)));
  await rejects('createSlip during the dispute window rejected',
    () => call(STEWARD, NO, 'createSlip', r1.S + 60, k(0x88), BigInt(r1.S + 200000)));
  await rejects('createSlip one second before the round closes rejected',
    () => call(STEWARD, NO, 'createSlip', r1.P - 1, k(0x88), BigInt(r1.P + 200000)));
  ok('every seal survived every clearing attempt', L().seals.size() === 3n);

  console.log('\n[11] Round 2 — a dispute may land AFTER the settle window closes');
  await call(STEWARD, NO, 'createSlip', r2.D - SEAL_WINDOW, k(0x88), BigInt(r2.D));
  ok('a new slip opens once the previous round has fully closed',
    L().roundId === 2n && L().status === OPEN, `round=${L().roundId}`);
  await call(ALICE, YES, 'sealPick', r2.D - 60);
  await call(BOB, YES, 'sealPick', r2.D - 60);
  await call(ALICE, YES, 'reveal', r2.D + 60);
  await call(STEWARD, NO, 'settle', r2.R + 60, NO);
  ok('round 2 settled', L().status === SETTLED && L().outcome === NO);
  // The dispute window runs past settleDeadline: the steward can settle at the
  // last minute, and the crew still gets a full window to challenge it.
  await call(BOB, YES, 'dispute', r2.S + 60);
  ok('dispute accepted after settleDeadline, inside the dispute window',
    L().status === DISPUTED_STATUS && L().outcome === DISPUTED
      && eq(L().disputedBy, bobId));

  console.log('\n[12] Round 3 — settled and NOT disputed (the normal happy ending)');
  await call(STEWARD, NO, 'createSlip', r3.D - SEAL_WINDOW, k(0x99), BigInt(r3.D));
  await call(ALICE, YES, 'sealPick', r3.D - 60);
  await call(BOB, NO, 'sealPick', r3.D - 60);
  await call(ALICE, YES, 'reveal', r3.D + 60);
  await call(BOB, NO, 'reveal', r3.D + 60);
  await call(STEWARD, NO, 'settle', r3.R + 60, YES);
  await rejects('dispute after disputeDeadline rejected on an undisputed round',
    () => call(ALICE, NO, 'dispute', r3.P));
  ok('an unchallenged outcome stands',
    L().status === SETTLED && L().outcome === YES && eq(L().disputedBy, new Uint8Array(32)),
    `status=${L().status} outcome=${L().outcome} disputedBy=none`);

  console.log('\n[13] Round 4 — the steward never settles (no brick, no fake result)');
  await call(STEWARD, NO, 'createSlip', r4.D - SEAL_WINDOW, k(0xAB), BigInt(r4.D));
  await call(ALICE, YES, 'sealPick', r4.D - 60);
  await call(BOB, NO, 'sealPick', r4.D - 60);
  await call(ALICE, YES, 'reveal', r4.D + 60);
  await call(BOB, NO, 'reveal', r4.D + 60);
  // The steward simply never shows up. The settle window closes.
  await rejects('steward who missed the window cannot settle late',
    () => call(STEWARD, NO, 'settle', r4.S, YES));
  await rejects('...nor during the dispute window',
    () => call(STEWARD, NO, 'settle', r4.S + 60, YES));
  await rejects('nothing to dispute on a round that was never settled',
    () => call(ALICE, NO, 'dispute', r4.S + 60));
  ok('UNAMBIGUOUS: never-settled reads as sentinel 2, distinct from disputed (3)',
    L().outcome === NO_OUTCOME && L().status === OPEN,
    `outcome=${L().outcome} status=${L().status} (open + 2 = nobody recorded a result)`);
  ok('the picks still opened — reveals are never hostage to the steward',
    L().reveals.size() === 2n && L().tallyYes === 1n && L().tallyNo === 1n);
  await rejects('an unsettled round still cannot be cleared early',
    () => call(STEWARD, NO, 'createSlip', r4.P - 1, k(0xCD), BigInt(r4.P + 200000)));

  console.log('\n[14] Next round — state resets, no brick, no cross-round replay');
  await call(STEWARD, NO, 'createSlip', r5open, k(0xCD), BigInt(r5open + SEAL_WINDOW));
  ok('NO BRICK: a new slip opens over a never-settled round once it closed',
    L().status === OPEN && L().roundId === 5n, `status=${L().status} round=${L().roundId}`);
  ok('seals cleared for new round', L().seals.size() === 0n);
  ok('reveals cleared for new round', L().reveals.size() === 0n);
  ok('tallies cleared', L().tallyYes === 0n && L().tallyNo === 0n);
  ok('outcome reset to the no-result sentinel', L().outcome === NO_OUTCOME);
  ok('disputedBy cleared', eq(L().disputedBy, new Uint8Array(32)));
  ok('crew roster survives the round change', L().crew.size() === 4n);
  ok('round is bound into the commitment (replay-proof)',
    !eq(pureCircuits.pickCommitment(1n, aliceId, YES, aliceSalt1),
        pureCircuits.pickCommitment(5n, aliceId, YES, aliceSalt1)),
    'same {member, choice, salt} yields a different commitment in round 5');
  ok('member is bound into the commitment (no copycat seals)',
    !eq(pureCircuits.pickCommitment(1n, aliceId, YES, aliceSalt1),
        pureCircuits.pickCommitment(1n, bobId, YES, aliceSalt1)));

  console.log(`\n===== ${pass} passed, ${fail} failed =====`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });

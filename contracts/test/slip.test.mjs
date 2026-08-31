import * as rt from '@midnight-ntwrk/compact-runtime';
import { setNetworkId } from '@midnight-ntwrk/midnight-js-network-id';
import { Contract, ledger, pureCircuits } from './slipcontract/index.js';

setNetworkId('undeployed');

const ADDR = rt.sampleContractAddress();
const CPK = { bytes: new Uint8Array(32) };

const k = (b) => { const x = new Uint8Array(32); x[0] = b; return x; };
const STEWARD = k(0x01), ALICE = k(0x02), BOB = k(0x03), MALLORY = k(0x09);
const SALT_A = k(0xAA), SALT_B = k(0xBB), SALT_WRONG = k(0xCC);

const YES = 1n, NO = 0n;
const DEADLINE = 5000n;
const BEFORE = 1000, AFTER = 9000;

const w = (sk, pick, salt) => ({
  localSecretKey: ({ privateState }) => [privateState, sk],
  localPick: ({ privateState }) => [privateState, pick],
  localPickSalt: ({ privateState }) => [privateState, salt],
});

let state, priv;

async function call(sk, pick, salt, id, timeMs, ...args) {
  const c = new Contract(w(sk, pick, salt));
  const ctx = rt.createCircuitContext(
    id, ADDR, CPK, state, priv,
    undefined, undefined, undefined, new Date(timeMs), undefined, undefined
  );
  const res = await c.impureCircuits[id](ctx, ...args);
  state = res.context.callContext.currentQueryContext.state;
  priv = res.context.callContext.currentPrivateState;
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

async function main() {
  const c = new Contract(w(STEWARD, NO, SALT_A));
  const init = await c.initialState(rt.createConstructorContext(undefined, CPK));
  state = init.currentContractState.data;
  priv = init.currentPrivateState;

  console.log('\n[1] Authorization — steward-only operations');
  await rejects('non-steward cannot createSlip',
    () => call(MALLORY, NO, SALT_A, 'createSlip', BEFORE, new Uint8Array(32), DEADLINE));
  await call(STEWARD, NO, SALT_A, 'createSlip', BEFORE, k(0x77), DEADLINE);
  ok('steward can createSlip', L().status === 1, `status=${L().status} round=${L().roundId}`);
  await rejects('non-steward cannot enrollMember',
    () => call(MALLORY, NO, SALT_A, 'enrollMember', BEFORE, pureCircuits.memberIdOf(ALICE)));

  console.log('\n[2] Crew roster');
  const aliceId = pureCircuits.memberIdOf(ALICE);
  const bobId = pureCircuits.memberIdOf(BOB);
  await call(STEWARD, NO, SALT_A, 'enrollMember', BEFORE, aliceId);
  await call(STEWARD, NO, SALT_A, 'enrollMember', BEFORE, bobId);
  ok('crew has 2 members', L().crew.size() === 2n, `size=${L().crew.size()}`);
  await rejects('duplicate enrollment rejected',
    () => call(STEWARD, NO, SALT_A, 'enrollMember', BEFORE, aliceId));

  console.log('\n[3] Sealing — privacy, membership, double-seal, deadline');
  await rejects('outsider (not in crew) cannot seal',
    () => call(MALLORY, YES, SALT_A, 'sealPick', BEFORE));
  await call(ALICE, YES, SALT_A, 'sealPick', BEFORE);
  await call(BOB, NO, SALT_B, 'sealPick', BEFORE);
  ok('two seals recorded', L().seals.size() === 2n, `size=${L().seals.size()}`);

  // PRIVACY PROBE: is the choice inferable from public state?
  const aliceCommit = L().seals.lookup(aliceId);
  const bobCommit = L().seals.lookup(bobId);
  const guessYes = pureCircuits.pickCommitment(1n, aliceId, YES, SALT_A);
  const guessNoSalt = pureCircuits.pickCommitment(1n, aliceId, YES, new Uint8Array(32));
  ok('commitment is opaque without the salt',
    Buffer.compare(Buffer.from(aliceCommit), Buffer.from(guessNoSalt)) !== 0,
    'brute-forcing choice with wrong salt does not match');
  ok('commitment reproduces only with the exact {choice, salt}',
    Buffer.compare(Buffer.from(aliceCommit), Buffer.from(guessYes)) === 0);
  ok('two members, same round, different picks -> unrelated commitments',
    Buffer.compare(Buffer.from(aliceCommit), Buffer.from(bobCommit)) !== 0);

  await rejects('double-seal rejected (same member, same round)',
    () => call(ALICE, NO, SALT_A, 'sealPick', BEFORE));
  await rejects('sealing after the deadline rejected',
    () => call(BOB, YES, SALT_B, 'sealPick', AFTER));
  await rejects('revealing before the deadline rejected',
    () => call(ALICE, YES, SALT_A, 'reveal', BEFORE));

  console.log('\n[4] Reveal — commitment must re-derive');
  await rejects('reveal with WRONG SALT rejected',
    () => call(ALICE, YES, SALT_WRONG, 'reveal', AFTER));
  await rejects('reveal with FLIPPED CHOICE rejected',
    () => call(ALICE, NO, SALT_A, 'reveal', AFTER));
  await call(ALICE, YES, SALT_A, 'reveal', AFTER);
  ok('honest reveal accepted', L().reveals.lookup(aliceId) === YES,
    `alice revealed ${L().reveals.lookup(aliceId)}`);
  await rejects('double-reveal rejected',
    () => call(ALICE, YES, SALT_A, 'reveal', AFTER));
  await call(BOB, NO, SALT_B, 'reveal', AFTER);
  ok('tallies correct', L().tallyYes === 1n && L().tallyNo === 1n,
    `yes=${L().tallyYes} no=${L().tallyNo}`);

  console.log('\n[5] Settle');
  await rejects('non-steward cannot settle',
    () => call(MALLORY, NO, SALT_A, 'settle', AFTER, YES));
  await rejects('outcome out of range rejected',
    () => call(STEWARD, NO, SALT_A, 'settle', AFTER, 7n));
  await call(STEWARD, NO, SALT_A, 'settle', AFTER, YES);
  ok('settled with outcome YES', L().status === 2 && L().outcome === YES,
    `status=${L().status} outcome=${L().outcome}`);

  console.log('\n[6] Next round — state resets, no cross-round replay');
  await call(STEWARD, NO, SALT_A, 'createSlip', AFTER, k(0x88), 20000n);
  ok('seals cleared for new round', L().seals.size() === 0n);
  ok('reveals cleared for new round', L().reveals.size() === 0n);
  ok('tallies cleared', L().tallyYes === 0n && L().tallyNo === 0n);
  ok('crew roster survives the round change', L().crew.size() === 2n);
  ok('roundId advanced', L().roundId === 2n, `round=${L().roundId}`);
  ok('round is bound into the commitment (replay-proof)',
    Buffer.compare(
      Buffer.from(pureCircuits.pickCommitment(1n, aliceId, YES, SALT_A)),
      Buffer.from(pureCircuits.pickCommitment(2n, aliceId, YES, SALT_A))
    ) !== 0,
    'same {member, choice, salt} yields a different commitment in round 2');
  ok('member is bound into the commitment (no copycat seals)',
    Buffer.compare(
      Buffer.from(pureCircuits.pickCommitment(1n, aliceId, YES, SALT_A)),
      Buffer.from(pureCircuits.pickCommitment(1n, bobId, YES, SALT_A))
    ) !== 0);

  console.log(`\n===== ${pass} passed, ${fail} failed =====`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });

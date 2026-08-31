import * as rt from '@midnight-ntwrk/compact-runtime';
import { setNetworkId } from '@midnight-ntwrk/midnight-js-network-id';
import { Contract, ledger, pureCircuits } from './slipcontract/index.js';
setNetworkId('undeployed');

const ADDR = rt.sampleContractAddress(), CPK = { bytes: new Uint8Array(32) };
const k = (b) => { const x = new Uint8Array(32); x[0] = b; return x; };
const STEWARD = k(1), ALICE = k(2);

// Unix SECONDS — the unit the ledger's `secondsSinceEpoch` field actually means.
const NOW = 1788000000;
const DEADLINE = NOW + 3600;

const w = (sk, p) => ({
  localSecretKey: ({ privateState }) => [privateState, sk],
  localPick: ({ privateState }) => [privateState, p],
});
let state, priv;
async function call(sk, p, id, t, ...a) {
  const c = new Contract(w(sk, p));
  const ctx = rt.createCircuitContext(id, ADDR, CPK, state, priv, undefined, undefined, undefined, t, undefined, undefined);
  const r = await c.impureCircuits[id](ctx, ...a);
  state = r.context.callContext.currentQueryContext.state;
  priv = r.context.callContext.currentPrivateState;
  return r;
}

const c = new Contract(w(STEWARD, 0n));
const init = await c.initialState(rt.createConstructorContext(undefined, CPK));
state = init.currentContractState.data; priv = init.currentPrivateState;

const aliceId = pureCircuits.memberIdOf(ALICE);
await call(STEWARD, 0n, 'enrollMember', NOW, aliceId);
await call(STEWARD, 0n, 'createSlip', NOW, k(0x77), BigInt(DEADLINE));

// Alice seals YES. The salt is no longer supplied by the host — the circuit
// derives it from her device secret, so this is the value the commitment hides
// behind, and it never appears as a circuit input.
const DERIVED_SALT = pureCircuits.pickSaltOf(1n, ALICE);
const res = await call(ALICE, 1n, 'sealPick', NOW + 600);

// Everything a chain observer can see for this transaction:
const trace = res.context.callProofDataTrace;
const publicTranscript = JSON.stringify(trace, (_, v) =>
  typeof v === 'bigint' ? v.toString() : (v instanceof Uint8Array ? Buffer.from(v).toString('hex') : v));

const hex = (b) => Buffer.from(b).toString('hex');
console.log('public transcript size:', publicTranscript.length, 'chars');
console.log('LEAK CHECK — device secret present in public transcript? ',
  publicTranscript.includes(hex(ALICE)) ? 'YES *** LEAK ***' : 'no');
console.log('LEAK CHECK — derived salt present in public transcript?  ',
  publicTranscript.includes(hex(DERIVED_SALT)) ? 'YES *** LEAK ***' : 'no');
console.log('LEAK CHECK — Alice memberId present (expected, intended)?',
  publicTranscript.includes(hex(aliceId)) ? 'yes (intended)' : 'no');

// Can an observer distinguish YES from NO given only public state?
const L = ledger(state);
const onChain = hex(L.seals.lookup(aliceId));
const asYes = hex(pureCircuits.pickCommitment(1n, aliceId, 1n, DERIVED_SALT));
const asNo = hex(pureCircuits.pickCommitment(1n, aliceId, 0n, DERIVED_SALT));
console.log('\non-chain seal      :', onChain.slice(0, 32), '...');
console.log('opens as YES+salt  :', asYes.slice(0, 32), '... match:', onChain === asYes);
console.log('opens as NO +salt  :', asNo.slice(0, 32), '... match:', onChain === asNo);

// Brute force. The observer knows round + memberId + both possible choices —
// everything except the salt. Two families of guess:
//   (a) low-entropy salts, the failure mode the old localPickSalt() witness
//       invited (a constant, a counter, a reused value);
//   (b) salts derived the way the circuit derives them, but from a guessed
//       device secret — the only remaining attack surface now that the salt is
//       bound to localSecretKey().
let crackedWeak = false, crackedDerived = false;
for (let guess = 0; guess < 512; guess++) {
  for (const ch of [0n, 1n]) {
    if (hex(pureCircuits.pickCommitment(1n, aliceId, ch, k(guess & 0xff))) === onChain) crackedWeak = true;
    const candidate = k(guess & 0xff);
    if (Buffer.compare(Buffer.from(candidate), Buffer.from(ALICE)) === 0) continue;
    const s = pureCircuits.pickSaltOf(1n, candidate);
    if (hex(pureCircuits.pickCommitment(1n, aliceId, ch, s)) === onChain) crackedDerived = true;
  }
}
console.log('\nbrute force (a) 512 low-entropy salt guesses x 2 choices:',
  crackedWeak ? 'CRACKED *** LEAK ***' : 'no match — a weak salt is no longer reachable, the circuit picks it');
console.log('brute force (b) 256 guessed device secrets x 2 choices, excluding Alice\'s:',
  crackedDerived ? 'CRACKED *** LEAK ***' : 'no match — choice not recoverable without the device secret');

if (publicTranscript.includes(hex(ALICE)) || publicTranscript.includes(hex(DERIVED_SALT))
    || crackedWeak || crackedDerived || onChain !== asYes) {
  console.error('\n*** PRIVACY PROBE FAILED ***');
  process.exit(1);
}
console.log('\n===== privacy probe clean =====');

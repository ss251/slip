import * as rt from '@midnight-ntwrk/compact-runtime';
import { setNetworkId } from '@midnight-ntwrk/midnight-js-network-id';
import { Contract, ledger, pureCircuits } from './slipcontract/index.js';
setNetworkId('undeployed');

const ADDR = rt.sampleContractAddress(), CPK = { bytes: new Uint8Array(32) };
const k = (b) => { const x = new Uint8Array(32); x[0] = b; return x; };
const STEWARD = k(1), ALICE = k(2);
const SECRET_SALT = k(0xAA);
const w = (sk, p, s) => ({
  localSecretKey: ({ privateState }) => [privateState, sk],
  localPick: ({ privateState }) => [privateState, p],
  localPickSalt: ({ privateState }) => [privateState, s],
});
let state, priv;
async function call(sk, p, s, id, t, ...a) {
  const c = new Contract(w(sk, p, s));
  const ctx = rt.createCircuitContext(id, ADDR, CPK, state, priv, undefined, undefined, undefined, new Date(t), undefined, undefined);
  const r = await c.impureCircuits[id](ctx, ...a);
  state = r.context.callContext.currentQueryContext.state;
  priv = r.context.callContext.currentPrivateState;
  return r;
}

const c = new Contract(w(STEWARD, 0n, k(9)));
const init = await c.initialState(rt.createConstructorContext(undefined, CPK));
state = init.currentContractState.data; priv = init.currentPrivateState;

await call(STEWARD, 0n, k(9), 'createSlip', 1000, k(0x77), 5000n);
await call(STEWARD, 0n, k(9), 'enrollMember', 1000, pureCircuits.memberIdOf(ALICE));

// Alice seals YES with a secret salt.
const res = await call(ALICE, 1n, SECRET_SALT, 'sealPick', 1000);

// Everything a chain observer can see for this transaction:
const trace = res.context.callProofDataTrace;
const publicTranscript = JSON.stringify(trace, (_, v) =>
  typeof v === 'bigint' ? v.toString() : (v instanceof Uint8Array ? Buffer.from(v).toString('hex') : v));

const saltHex = Buffer.from(SECRET_SALT).toString('hex');
console.log('public transcript size:', publicTranscript.length, 'chars');
console.log('LEAK CHECK — raw salt present in public transcript? ', publicTranscript.includes(saltHex) ? 'YES *** LEAK ***' : 'no');
console.log('LEAK CHECK — Alice memberId present (expected, intended)?',
  publicTranscript.includes(Buffer.from(pureCircuits.memberIdOf(ALICE)).toString('hex')) ? 'yes (intended)' : 'no');

// Can an observer distinguish YES from NO given only public state?
const L = ledger(state);
const onChain = Buffer.from(L.seals.lookup(pureCircuits.memberIdOf(ALICE))).toString('hex');
const asYes = Buffer.from(pureCircuits.pickCommitment(1n, pureCircuits.memberIdOf(ALICE), 1n, SECRET_SALT)).toString('hex');
const asNo  = Buffer.from(pureCircuits.pickCommitment(1n, pureCircuits.memberIdOf(ALICE), 0n, SECRET_SALT)).toString('hex');
console.log('\non-chain seal      :', onChain.slice(0, 32), '...');
console.log('opens as YES+salt  :', asYes.slice(0, 32), '... match:', onChain === asYes);
console.log('opens as NO +salt  :', asNo.slice(0, 32),  '... match:', onChain === asNo);

// Brute force: observer knows round + memberId + both possible choices, but NOT the salt.
let cracked = false;
for (let guess = 0; guess < 512; guess++) {
  for (const ch of [0n, 1n]) {
    const g = Buffer.from(pureCircuits.pickCommitment(1n, pureCircuits.memberIdOf(ALICE), ch, k(guess & 0xff))).toString('hex');
    if (g === onChain && !(ch === 1n && (guess & 0xff) === 0xAA)) cracked = true;
  }
}
console.log('\nbrute force over 512 salt guesses x 2 choices, excluding the true opening:', cracked ? 'CRACKED *** LEAK ***' : 'no match — choice not recoverable from public state');

// Dumps the real ProofPreimage inputs for one sealPick call, so the Rust prover can
// prove OUR circuit rather than a toy one. Fields map onto transient_crypto's
// ProofPreimage: inputs, private_transcript, public_transcript_{inputs,outputs}.
import * as rt from '@midnight-ntwrk/compact-runtime';
import { setNetworkId } from '@midnight-ntwrk/midnight-js-network-id';
import { Contract, pureCircuits } from './slipcontract/index.js';
import { writeFileSync } from 'node:fs';
setNetworkId('undeployed');

// Deterministic on purpose: the on-device execution gate diffs JSC's proofData against
// this file's, so nothing random may enter either run.
const FIXED_ADDR = '11'.repeat(32);
const ADDR = FIXED_ADDR, CPK = { bytes: new Uint8Array(32) };
const k = (b) => new Uint8Array(32).fill(b);
const STEWARD = k(1), ALICE = k(2);
const NOW = 1788000000, DEADLINE = NOW + 3600;

const w = (sk, p) => ({
  localSecretKey: ({ privateState }) => [privateState, sk],
  localPick: ({ privateState }) => [privateState, p],
});
let state, priv;
async function call(sk, p, id, t, ...a) {
  const c = new Contract(w(sk, p));
  const ctx = rt.createCircuitContext(ADDR, CPK, state, priv, undefined, undefined, t);
  const r = await c.impureCircuits[id](ctx, ...a);
  state = r.context.currentQueryContext.state;
  priv = r.context.currentPrivateState;
  return r;
}

const boot = new Contract(w(STEWARD, 0n));
const init = await boot.initialState(rt.createConstructorContext(undefined, CPK));
state = init.currentContractState.data;
priv = init.currentPrivateState;

// enrollment first: the contract locks the roster once a slip is open
await call(STEWARD, 0n, 'enrollMember', NOW, pureCircuits.memberIdOf(ALICE));
await call(STEWARD, 0n, 'createSlip', NOW + 10, new Uint8Array(32).fill(9), BigInt(DEADLINE));
// The ContractState the sealPick call runs against (after enrollMember + createSlip):
// public chain context the native tx assembly builds from. Operations come from the
// deploy-time state; data is the latest ledger state.
{
  const cs = init.currentContractState; cs.data = state;
  writeFileSync('build/sealPick.state.bin', Buffer.from(cs.serialize()));
  console.log('wrote build/sealPick.state.bin');
}
const res = await call(ALICE, 1n, 'sealPick', NOW + 600);

const pd = res.proofData;
// The runtime's own serialiser — the sanctioned bridge from a simulator run to a
// prover input. Hand-converting AlignedValues would be guesswork.
const bytes = rt.proofDataIntoSerializedPreimage(
  pd.input, pd.output, pd.publicTranscript, pd.privateTranscriptOutputs, 'sealPick',
);
writeFileSync('build/sealPick.preimage.bin', Buffer.from(bytes));
// Golden proofData for the on-device execution gate: JSC must reproduce this
// byte-for-byte (after the same canonical serialisation) or execution is unfaithful.
const enc = (v) => JSON.parse(JSON.stringify(v, (_, x) =>
  typeof x === 'bigint' ? x.toString() : (x instanceof Uint8Array ? Array.from(x) : x)));
writeFileSync('build/sealPick-proofdata.json', JSON.stringify({
  input: enc(pd.input), output: enc(pd.output),
  publicTranscript: enc(pd.publicTranscript), privateTranscriptOutputs: enc(pd.privateTranscriptOutputs),
}));
console.log('wrote build/sealPick-proofdata.json');
console.log('wrote build/sealPick.preimage.bin', bytes.length, 'bytes');
console.log('  public transcript ops :', pd.publicTranscript.length);
console.log('  private outputs       :', pd.privateTranscriptOutputs.length);

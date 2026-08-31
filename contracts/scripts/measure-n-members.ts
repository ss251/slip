// Proves Option B at crew scale: can ONE steward fund N members?
//
// Registration is address-scoped (ledger: address_delegation: Map<NightAddress,
// DustPublicKey>), so a steward needs one Night address per member. Here each
// steward sub-address is its own wallet (in the app these are HD-derived indices
// off one master seed). Genesis funds each sub-address with NIGHT; each sub then
// designates DUST generation to a distinct member who holds nothing.
//
// Also answers: can a FRESH sub-address (NIGHT, zero DUST) pay for its own
// registration out of retroactive DUST, or does it hit code 173 and need to wait?
import { MidnightWalletProvider, syncWallet } from '../src/wallet.js';
import { getConfig } from '../src/config.js';
import { setNetworkId } from '@midnight-ntwrk/midnight-js-network-id';
import type { EnvironmentConfiguration } from '@midnight-ntwrk/testkit-js';
import pino from 'pino';
import * as rx from 'rxjs';

const logger = pino({ level: 'info', transport: { target: 'pino-pretty', options: { colorize: true } } });

const N = 3;
const GENESIS = '0000000000000000000000000000000000000000000000000000000000000001';
const stewardSeed = (i: number) => `${'0'.repeat(61)}${(i + 1)}a1`.slice(-64);
const memberSeed  = (i: number) => `${'0'.repeat(61)}${(i + 1)}b2`.slice(-64);
const NIGHT_PER_SUB = 1_000_000n;
const ms = (t: number) => `${(t / 1000).toFixed(1)}s`;

async function main() {
  const config = getConfig();
  setNetworkId(config.networkId as any);
  const env = {
    walletNetworkId: config.networkId, networkId: config.networkId,
    indexer: config.indexer, indexerWS: config.indexerWS,
    node: config.node, nodeWS: config.nodeWS,
    faucet: config.faucet, proofServer: config.proofServer,
  } as EnvironmentConfiguration;

  const mk = async (seed: string) => {
    const w = await MidnightWalletProvider.build(logger, env, { kind: 'seed', value: seed });
    await w.start(); await syncWallet(logger, w.wallet); return w;
  };
  const st = (w: any) => rx.firstValueFrom(w.wallet.state().pipe(rx.filter((s: any) => s.isSynced)));

  logger.info(`building genesis + ${N} steward sub-addresses + ${N} members...`);
  const genesis  = await mk(GENESIS);
  const stewards = []; for (let i = 0; i < N; i++) stewards.push(await mk(stewardSeed(i)));
  const members  = []; for (let i = 0; i < N; i++) members.push(await mk(memberSeed(i)));

  for (let i = 0; i < N; i++) {
    const d = await members[i].getDustBalance();
    const s: any = await st(members[i]);
    logger.info(`member[${i}] start: DUST=${d} NIGHT utxos=${s.unshielded.availableCoins.length}`);
  }

  // 1. genesis funds each steward sub-address with NIGHT (only)
  logger.info('--- funding steward sub-addresses with NIGHT ---');
  for (let i = 0; i < N; i++) {
    const addr = await stewards[i].wallet.unshielded.getAddress();
    await genesis.transferNight(addr, NIGHT_PER_SUB);
    logger.info(`  sent ${NIGHT_PER_SUB} NIGHT -> steward[${i}]`);
  }
  for (let i = 0; i < N; i++) {
    let ok = false;
    for (let k = 0; k < 60; k++) {
      await new Promise((r) => setTimeout(r, 3_000));
      const s: any = await st(stewards[i]);
      if (s.unshielded.availableCoins.length > 0) {
        const unreg = s.unshielded.availableCoins.filter((c: any) => c.meta?.registeredForDustGeneration === false);
        logger.info(`  steward[${i}] funded: ${s.unshielded.availableCoins.length} utxos, ${unreg.length} unregistered, DUST=${await stewards[i].getDustBalance()}`);
        ok = true; break;
      }
    }
    if (!ok) { logger.error(`steward[${i}] never received NIGHT`); process.exit(2); }
  }

  // 2. each steward sub designates DUST generation to its member
  logger.info('--- registering: steward[i] NIGHT -> member[i] DUST address ---');
  const t0 = Date.now();
  const selfFunded: boolean[] = [];
  for (let i = 0; i < N; i++) {
    const mState: any = await st(members[i]);
    const sState: any = await st(stewards[i]);
    const unreg = sState.unshielded.availableCoins.filter((c: any) => c.meta?.registeredForDustGeneration === false);
    try {
      const recipe = await stewards[i].wallet.registerNightUtxosForDustGeneration(
        unreg,
        stewards[i].unshieldedKeystore.getPublicKey(),
        (p: Uint8Array) => stewards[i].unshieldedKeystore.signData(p),
        mState.dust.address,
      );
      const finalized = await stewards[i].wallet.finalizeRecipe(recipe);
      const tx = await stewards[i].wallet.submitTransaction(finalized);
      selfFunded.push(true);
      logger.info(`  steward[${i}] registered (SELF-FUNDED from retroactive DUST) tx=${String(tx).slice(0, 16)}...`);
    } catch (e: any) {
      selfFunded.push(false);
      logger.error(`  steward[${i}] registration FAILED: ${e?.message ?? e}`);
    }
  }

  // 3. did every member independently receive DUST?
  logger.info('--- polling members for DUST ---');
  const got: (number | null)[] = new Array(N).fill(null);
  while (Date.now() - t0 < 10 * 60 * 1000 && got.some((g) => g === null)) {
    await new Promise((r) => setTimeout(r, 3_000));
    for (let i = 0; i < N; i++) {
      if (got[i] !== null) continue;
      const bal = await members[i].getDustBalance();
      if (bal > 0n) { got[i] = Date.now() - t0; logger.info(`  *** member[${i}] has DUST (${bal}) at ${ms(got[i]!)} ***`); }
    }
  }

  logger.info('--- RESULT ---');
  logger.info(`self-funded registrations: ${selfFunded.filter(Boolean).length}/${N}`);
  for (let i = 0; i < N; i++) {
    logger.info(`member[${i}]: ${got[i] === null ? 'NO DUST (FAIL)' : `DUST at ${ms(got[i]!)}`}`);
  }
  const genesisDust = await genesis.getDustBalance();
  logger.info(`genesis DUST still intact: ${genesisDust > 0n} (${genesisDust})`);
  logger.info(got.every((g) => g !== null) ? 'VERDICT: N-member fan-out WORKS' : 'VERDICT: N-member fan-out FAILED');
  process.exit(got.every((g) => g !== null) ? 0 : 1);
}
main().catch((e) => { logger.error(e); process.exit(1); });

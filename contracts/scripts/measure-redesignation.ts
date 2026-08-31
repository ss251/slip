// Measures Option B: how long after a steward redesignates DUST generation to a
// member's DUST address does that member actually have spendable DUST?
//
// Alice = steward (genesis, holds NIGHT). Mallory = member (fresh seed, holds nothing).
// Alice registers her NIGHT UTXOs with dustReceiverAddress = Mallory's DUST address.
// We poll Mallory's DUST balance and report time-to-first-DUST.
import { MidnightWalletProvider, syncWallet } from '../src/wallet.js';
import { getConfig } from '../src/config.js';
import { setNetworkId } from '@midnight-ntwrk/midnight-js-network-id';
import type { EnvironmentConfiguration } from '@midnight-ntwrk/testkit-js';
import pino from 'pino';
import * as rx from 'rxjs';

const logger = pino({ level: 'info', transport: { target: 'pino-pretty', options: { colorize: true } } });

const ALICE_SEED   = '0000000000000000000000000000000000000000000000000000000000000001';
const MALLORY_SEED = '00000000000000000000000000000000000000000000000000000000000000ab';
const POLL_MS = 3_000;
const TIMEOUT_MS = 20 * 60 * 1000;

const ms = (t: number) => `${(t / 1000).toFixed(1)}s`;

async function main() {
  const config = getConfig();
  logger.info(`network=${config.networkId} node=${config.node}`);
  setNetworkId(config.networkId as any);

  const envConfig: EnvironmentConfiguration = {
    walletNetworkId: config.networkId, networkId: config.networkId,
    indexer: config.indexer, indexerWS: config.indexerWS,
    node: config.node, nodeWS: config.nodeWS,
    faucet: config.faucet, proofServer: config.proofServer,
  } as EnvironmentConfiguration;

  const alice   = await MidnightWalletProvider.build(logger, envConfig, { kind: 'seed', value: ALICE_SEED });
  await alice.start(); await syncWallet(logger, alice.wallet);
  const mallory = await MidnightWalletProvider.build(logger, envConfig, { kind: 'seed', value: MALLORY_SEED });
  await mallory.start(); await syncWallet(logger, mallory.wallet);

  const aliceState   = await rx.firstValueFrom(alice.wallet.state().pipe(rx.filter((s: any) => s.isSynced)));
  const malloryState = await rx.firstValueFrom(mallory.wallet.state().pipe(rx.filter((s: any) => s.isSynced)));

  const malloryDustAddr = malloryState.dust.address;
  logger.info(`Mallory DUST address: ${String(malloryDustAddr)}`);
  logger.info(`Mallory DUST before:  ${await mallory.getDustBalance()}`);
  logger.info(`Mallory NIGHT coins:  ${malloryState.unshielded.availableCoins.length} (expect 0)`);

  // Registration is scoped to a Night ADDRESS (ledger: address_delegation:
  // Map<NightAddress, DustPublicKey>), not to individual UTXOs. Re-registering an
  // already-registered address simply repoints its mapping, so we pass the coins as-is.
  const coins = aliceState.unshielded.availableCoins;
  const already = coins.filter((c: any) => c.meta?.registeredForDustGeneration === true).length;
  logger.info(`Alice NIGHT utxos: ${coins.length} total, ${already} already registered`);
  logger.info(`Alice DUST balance (pays the registration fee): ${await alice.getDustBalance()}`);
  const unregistered = coins;

  logger.info('--- submitting redesignation (Alice NIGHT -> Mallory DUST address) ---');
  const t0 = Date.now();
  const recipe = await alice.wallet.registerNightUtxosForDustGeneration(
    unregistered,
    alice.unshieldedKeystore.getPublicKey(),
    (payload: Uint8Array) => alice.unshieldedKeystore.signData(payload),
    malloryDustAddr,
  );
  // Redesignation must be explicitly DUST-balanced before finalizing. Plain
  // self-registration self-funds from retroactive DUST; pointing generation at a
  // third party does not, and skipping this yields Malformed(BalanceCheckOverspend).
  const a = alice as any;
  const balanced = await alice.wallet.balanceUnprovenTransaction(
    (recipe as any).transaction,
    { shieldedSecretKeys: a.zswapSecretKeys, dustSecretKey: a.dustSecretKey },
    { ttl: new Date(Date.now() + 30 * 60 * 1000), tokenKindsToBalance: ['dust'] },
  );
  // No signRecipe here: registerNightUtxosForDustGeneration already signed via its
  // signDustRegistration callback. Signing again yields InputsSignaturesLengthMismatch.
  const finalized = await alice.wallet.finalizeRecipe(balanced as any);
  const txId = await alice.wallet.submitTransaction(finalized);
  const tSubmit = Date.now() - t0;
  logger.info(`registration submitted in ${ms(tSubmit)} txId=${txId}`);

  let firstDustAt: number | null = null;
  let lastBal = 0n;
  while (Date.now() - t0 < TIMEOUT_MS) {
    await new Promise((r) => setTimeout(r, POLL_MS));
    const bal = await mallory.getDustBalance();
    if (bal !== lastBal) { logger.info(`t=${ms(Date.now() - t0)} Mallory DUST = ${bal}`); lastBal = bal; }
    if (bal > 0n && firstDustAt === null) {
      firstDustAt = Date.now() - t0;
      logger.info(`*** FIRST DUST at ${ms(firstDustAt)} ***`);
      break;
    }
  }

  if (firstDustAt === null) {
    logger.error(`NO DUST after ${ms(TIMEOUT_MS)} — redesignation did not deliver to a third party.`);
    process.exit(1);
  }

  logger.info('--- RESULT ---');
  logger.info(`submit=${ms(tSubmit)} time_to_first_dust=${ms(firstDustAt)} balance=${lastBal}`);
  await alice.stop(); await mallory.stop();
  process.exit(0);
}

main().catch((e) => { logger.error(e); process.exit(1); });

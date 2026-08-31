// Network e2e: deploys slip.compact to the local ledger-9 devnet and calls a
// circuit, proving the contract works on a chain rather than only in the simulator.
//
// Run from contracts/: `npm run test:network` (builds with ZK keys, links the build
// in, installs this workspace, then runs). Requires infra/devnet-compose.yml up
// (`npm run devnet:up`). Uses the
// midnight-js 5.0.0-beta line, the only published stack that consumes compiler-0.34.0
// artifacts; midnight-js 4.1.1 hard-pins compact-runtime 0.16.0 and cannot load them.
//
// Verified 2026-08-31: deploy 21.8s, createSlip SucceedEntirely 17.3s.
import { CompiledContract } from '@midnight-ntwrk/midnight-js-protocol/compact-js';
import { deployContract, submitCallTx } from '@midnight-ntwrk/midnight-js-contracts';
import { NodeZkConfigProvider } from '@midnight-ntwrk/midnight-js-node-zk-config-provider';
import { indexerPublicDataProvider } from '@midnight-ntwrk/midnight-js-indexer-public-data-provider';
import { httpClientProofProvider } from '@midnight-ntwrk/midnight-js-http-client-proof-provider';
import { levelPrivateStateProvider } from '@midnight-ntwrk/midnight-js-level-private-state-provider';
import { setNetworkId } from '@midnight-ntwrk/midnight-js-network-id';
import { ttlOneHour } from '@midnight-ntwrk/midnight-js-utils';
import { ZswapSecretKeys, DustSecretKey, LedgerParameters } from '@midnight-ntwrk/midnight-js-protocol/ledger';
import { FluentWalletBuilder } from '@midnight-ntwrk/testkit-js';
import { Contract, ledger } from './slip-build/contract/index.js'; // linked by link-build.mjs
import path from 'node:path';
import pino from 'pino';

const logger = pino({ level: 'info', transport: { target: 'pino-pretty', options: { colorize: true } } });
setNetworkId('undeployed');

const CFG = {
  walletNetworkId: 'undeployed', networkId: 'undeployed',
  indexer: 'http://localhost:8088/api/v4/graphql',
  indexerWS: 'ws://localhost:8088/api/v4/graphql/ws',
  node: 'http://localhost:9944', nodeWS: 'ws://localhost:9944',
  proofServer: 'http://localhost:6300', faucet: '',
};
const GENESIS = '0000000000000000000000000000000000000000000000000000000000000001';
const ZK = path.resolve('./slip-build');
const STEWARD_SK = new Uint8Array(32).fill(7);

const witnesses = {
  localSecretKey: ({ privateState }) => [privateState, STEWARD_SK],
  localPick:      ({ privateState }) => [privateState, 0],
};

async function buildWallet(seed) {
  const built = await FluentWalletBuilder.forEnvironment(CFG)
    .withDustOptions({ ledgerParams: LedgerParameters.initialParameters(), additionalFeeOverhead: 1_000n, feeBlocksMargin: 5 })
    .withSeed(seed).buildWithoutStarting();
  const { wallet, seeds, keystore } = built;
  const zswap = ZswapSecretKeys.fromSeed(seeds.shielded);
  const dust  = DustSecretKey.fromSeed(seeds.dust);
  await wallet.start(zswap, dust);
  const provider = {
    wallet, keystore,
    getCoinPublicKey: () => zswap.coinPublicKey,
    getEncryptionPublicKey: () => zswap.encryptionPublicKey,
    async balanceTx(tx, ttl = ttlOneHour()) {
      const recipe = await wallet.balanceUnboundTransaction(tx, { shieldedSecretKeys: zswap, dustSecretKey: dust }, { ttl });
      // The SDK wraps this in Effect.tryPromise, so the callback MUST return a
      // Promise — a synchronous return fails as "Signer callback failed".
      const signed = await wallet.signRecipe(recipe, (p) => keystore.signDataAsync(p));
      return wallet.finalizeRecipe(signed);
    },
    submitTx: (tx) => wallet.submitTransaction(tx),
  };
  return provider;
}

async function main() {
  logger.info('building genesis wallet...');
  const w = await buildWallet(GENESIS);
  logger.info('waiting for wallet sync (60s cap)...');
  await new Promise((resolve, reject) => {
    const to = setTimeout(() => { sub.unsubscribe(); reject(new Error('wallet never synced in 60s')); }, 60_000);
    const sub = w.wallet.state().subscribe((x) => {
      if (x.isSynced) { clearTimeout(to); sub.unsubscribe(); resolve(x); }
    });
  });
  logger.info('wallet synced');

  const zkConfigProvider = new NodeZkConfigProvider(ZK);
  const providers = {
    privateStateProvider: levelPrivateStateProvider({
      privateStateStoreName: `slip-e2e-${Date.now()}`,
      privateStoragePasswordProvider: () => 'Slip-E2E-Password!1',
      accountId: w.getCoinPublicKey(),
    }),
    publicDataProvider: indexerPublicDataProvider(CFG.indexer, CFG.indexerWS),
    zkConfigProvider,
    proofProvider: httpClientProofProvider(CFG.proofServer, zkConfigProvider),
    walletProvider: w,
    midnightProvider: w,
  };

  const compiled = CompiledContract.make('SlipContract', Contract).pipe(
    (c) => CompiledContract.withWitnesses(c, witnesses),
    (c) => CompiledContract.withCompiledFileAssets(c, ZK),
  );

  logger.info('--- DEPLOYING slip.compact ---');
  const t0 = Date.now();
  const deployed = await deployContract(providers, {
    compiledContract: compiled,
    privateStateId: 'slip-steward',
    initialPrivateState: {},
    args: [],
  });
  const addr = deployed.deployTxData.public.contractAddress;
  logger.info(`*** DEPLOYED at ${addr} in ${((Date.now()-t0)/1000).toFixed(1)}s ***`);

  const st0 = await providers.publicDataProvider.queryContractState(addr);
  const l0 = ledger(st0.data);
  logger.info(`ledger after constructor: status=${l0.status} round=${l0.round}`);

  logger.info('--- CALLING createSlip ---');
  const t1 = Date.now();
  const question = new Uint8Array(32).fill(9);
  const deadline = BigInt(Math.floor(Date.now()/1000) + 3600);
  const res = await submitCallTx(providers, {
    compiledContract: compiled,
    contractAddress: addr,
    privateStateId: 'slip-steward',
    circuitId: 'createSlip',
    args: [question, deadline],
  });
  logger.info(`*** createSlip status=${res.public.status} in ${((Date.now()-t1)/1000).toFixed(1)}s ***`);

  const st1 = await providers.publicDataProvider.queryContractState(addr);
  const l1 = ledger(st1.data);
  logger.info(`ledger after createSlip: status=${l1.status} round=${l1.round} sealDeadline=${l1.sealDeadline}`);
  logger.info('=== E2E DEPLOY + CALL: SUCCESS ===');
  await w.wallet.stop();
  process.exit(0);
}
main().catch((e) => {
  logger.error(e?.message ?? String(e));
  let c = e?.cause, depth = 0;
  while (c && depth++ < 6) { logger.error(`cause[${depth}]: ${c?.message ?? String(c)}`); c = c?.cause; }
  if (e?.stack) console.error(e.stack.split('\n').slice(0, 12).join('\n'));
  process.exit(1);
});

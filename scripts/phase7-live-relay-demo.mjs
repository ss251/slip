#!/usr/bin/env node

// Phase 7 component demo: prepare a live Slip round through the pinned standard
// host path, assemble sealPick with the native ledger/prover, and hand the exact
// proved/pre-binding bytes to the authenticated steward relay over HTTP.
//
// This proves the host producer -> authenticated relay -> local node -> indexer
// boundary. It is not evidence that a physical iPhone originated the request.

import assert from 'node:assert/strict';
import { execFile as execFileCallback } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import {
  access,
  chmod,
  mkdtemp,
  readFile,
  readdir,
  rm,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';

import {
  createRelayServer,
  createStewardRuntime,
  loadRelayConfiguration,
} from './steward-relay.mjs';

const execFile = promisify(execFileCallback);
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, '..');
const e2eRoot = path.join(repositoryRoot, 'contracts', 'e2e');
const moduleRoot = path.join(e2eRoot, 'node_modules');
const generatedRoot = path.join(e2eRoot, 'slip-build');
const canonicalGeneratedRoot = path.join(repositoryRoot, 'contracts', 'build');
const nativeProver = process.env.SLIP_PROVE_CLI ?? path.join(
  homedir(),
  'Developer',
  'midnight-ios-spike',
  'slip-prove-ffi',
  'target',
  'release',
  'slip-prove',
);

const moduleURL = (...components) => pathToFileURL(path.join(moduleRoot, ...components)).href;
const [
  { CompiledContract },
  { deployContract, submitCallTx },
  { NodeZkConfigProvider },
  { indexerPublicDataProvider },
  { httpClientProofProvider },
  { levelPrivateStateProvider },
  { setNetworkId },
  { SucceedEntirely },
  { ttlOneHour },
  { DustSecretKey, LedgerParameters, Transaction, ZswapSecretKeys },
  { FluentWalletBuilder },
  compactRuntime,
  { Contract, ledger, pureCircuits },
] = await Promise.all([
  import(moduleURL('@midnight-ntwrk', 'midnight-js-protocol', 'dist', 'compact-js.mjs')),
  import(moduleURL('@midnight-ntwrk', 'midnight-js-contracts', 'dist', 'index.mjs')),
  import(moduleURL('@midnight-ntwrk', 'midnight-js-node-zk-config-provider', 'dist', 'index.mjs')),
  import(moduleURL('@midnight-ntwrk', 'midnight-js-indexer-public-data-provider', 'dist', 'index.mjs')),
  import(moduleURL('@midnight-ntwrk', 'midnight-js-http-client-proof-provider', 'dist', 'index.mjs')),
  import(moduleURL('@midnight-ntwrk', 'midnight-js-level-private-state-provider', 'dist', 'index.mjs')),
  import(moduleURL('@midnight-ntwrk', 'midnight-js-network-id', 'dist', 'index.mjs')),
  import(moduleURL('@midnight-ntwrk', 'midnight-js-types', 'dist', 'index.mjs')),
  import(moduleURL('@midnight-ntwrk', 'midnight-js-utils', 'dist', 'index.mjs')),
  import(moduleURL('@midnight-ntwrk', 'midnight-js-protocol', 'dist', 'ledger.mjs')),
  import(moduleURL('@midnight-ntwrk', 'testkit-js', 'dist', 'index.mjs')),
  import(moduleURL('@midnight-ntwrk', 'compact-runtime', 'dist', 'index.js')),
  import(pathToFileURL(path.join(generatedRoot, 'contract', 'index.js')).href),
]);

const localNetwork = Object.freeze({
  walletNetworkId: 'undeployed',
  networkId: 'undeployed',
  indexer: 'http://localhost:8088/api/v4/graphql',
  indexerWS: 'ws://localhost:8088/api/v4/graphql/ws',
  node: 'http://localhost:9944',
  nodeWS: 'ws://localhost:9944',
  proofServer: 'http://localhost:6300',
  faucet: '',
});
const genesisSeed = '0000000000000000000000000000000000000000000000000000000000000001';
const syntheticSecret = new Uint8Array(32).fill(7);
const syntheticPick = 1n;
const privateStateID = 'slip-phase7-live-relay-demo';
const finalityTimeoutMilliseconds = 60_000;
const confirmationPollMilliseconds = 250;

setNetworkId('undeployed');

const safeLine = (error) => String(error?.message ?? error).split('\n', 1)[0].slice(0, 320);
const bytesEqual = (left, right) => Buffer.from(left).equals(Buffer.from(right));
const encodeProofData = (value) => JSON.parse(JSON.stringify(value, (_, item) => {
  if (typeof item === 'bigint') return item.toString();
  if (item instanceof Uint8Array) return Array.from(item);
  return item;
}));

async function relativeFiles(root, relative = '') {
  const entries = await readdir(path.join(root, relative), { withFileTypes: true });
  const nested = await Promise.all(entries.map((entry) => {
    const child = path.join(relative, entry.name);
    return entry.isDirectory() ? relativeFiles(root, child) : [child];
  }));
  return nested.flat().sort();
}

async function preflight() {
  await Promise.all([
    access(nativeProver),
    access(path.join(generatedRoot, 'contract', 'index.js')),
    access(path.join(generatedRoot, 'zkir', 'sealPick.zkir')),
    access(path.join(generatedRoot, 'keys', 'sealPick.prover')),
    access(path.join(generatedRoot, 'keys', 'sealPick.verifier')),
    access(path.join(generatedRoot, 'params', 'bls_midnight_2p14')),
  ]);

  // Compare only consumed compiler artifacts. Build-root scratch can contain
  // private proof inputs and is deliberately outside this process boundary.
  for (const artifactDirectory of ['contract', 'zkir', 'keys', 'params']) {
    const [canonicalFiles, linkedFiles] = await Promise.all([
      relativeFiles(path.join(canonicalGeneratedRoot, artifactDirectory)),
      relativeFiles(path.join(generatedRoot, artifactDirectory)),
    ]);
    assert.deepEqual(
      linkedFiles,
      canonicalFiles,
      `contracts/e2e/slip-build/${artifactDirectory} is stale`,
    );
    for (const relative of canonicalFiles) {
      const [canonical, linked] = await Promise.all([
        readFile(path.join(canonicalGeneratedRoot, artifactDirectory, relative)),
        readFile(path.join(generatedRoot, artifactDirectory, relative)),
      ]);
      assert.equal(
        linked.equals(canonical),
        true,
        `contracts/e2e/slip-build/${artifactDirectory}/${relative} is stale`,
      );
    }
  }
}

async function buildSetupWallet() {
  const built = await FluentWalletBuilder.forEnvironment(localNetwork)
    .withDustOptions({
      ledgerParams: LedgerParameters.initialParameters(),
      additionalFeeOverhead: 1_000n,
      feeBlocksMargin: 5,
    })
    .withSeed(genesisSeed)
    .buildWithoutStarting();
  const { wallet, seeds, keystore } = built;
  const zswap = ZswapSecretKeys.fromSeed(seeds.shielded);
  const dust = DustSecretKey.fromSeed(seeds.dust);
  try {
    await wallet.start(zswap, dust);
  } catch (error) {
    try { await wallet.stop(); } catch { /* preserve the startup error */ }
    throw error;
  }
  return {
    wallet,
    coinPublicKey: zswap.coinPublicKey,
    getCoinPublicKey: () => zswap.coinPublicKey,
    getEncryptionPublicKey: () => zswap.encryptionPublicKey,
    async balanceTx(transaction, ttl = ttlOneHour()) {
      const recipe = await wallet.balanceUnboundTransaction(
        transaction,
        { shieldedSecretKeys: zswap, dustSecretKey: dust },
        { ttl },
      );
      const signed = await wallet.signRecipe(recipe, (payload) => keystore.signData(payload));
      return wallet.finalizeRecipe(signed);
    },
    submitTx: (transaction) => wallet.submitTransaction(transaction),
  };
}

async function waitForWalletSync(wallet) {
  await new Promise((resolve, reject) => {
    let subscription;
    let settled = false;
    const timeout = setTimeout(() => {
      settled = true;
      subscription?.unsubscribe();
      reject(new Error('wallet sync timed out'));
    }, 60_000);
    subscription = wallet.state().subscribe({
      next: (state) => {
        if (!settled && state.isSynced) {
          settled = true;
          clearTimeout(timeout);
          queueMicrotask(() => subscription?.unsubscribe());
          resolve();
        }
      },
      error: () => {
        if (!settled) {
          settled = true;
          clearTimeout(timeout);
          reject(new Error('wallet sync failed'));
        }
      },
    });
  });
}

async function latestBlock() {
  const response = await fetch(localNetwork.indexer, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ query: '{ block { height hash timestamp } }' }),
  });
  assert.equal(response.ok, true, `indexer block query returned HTTP ${response.status}`);
  const payload = await response.json();
  assert.equal(payload.errors, undefined, 'indexer block query returned GraphQL errors');
  const block = payload?.data?.block;
  assert.ok(block, 'indexer returned no latest block');
  assert.match(block.hash, /^[0-9a-f]{64}$/i, 'indexer block hash is not 32-byte hex');
  assert.ok(Number.isSafeInteger(block.timestamp), 'indexer block timestamp is not a safe integer');
  assert.ok(block.timestamp > 1_000_000_000_000, 'indexer block timestamp is not milliseconds');
  return Object.freeze({
    height: block.height,
    hash: block.hash.toLowerCase(),
    seconds: Math.floor(block.timestamp / 1_000),
  });
}

async function listen(server) {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', reject);
      resolve();
    });
  });
  const address = server.address();
  assert.ok(address && typeof address === 'object', 'relay did not expose a local address');
  return `http://127.0.0.1:${address.port}`;
}

async function closeServer(server) {
  if (!server?.listening) return;
  server.closeIdleConnections?.();
  await new Promise((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
}

async function fetchRelayJSON(baseURL, pathname, token, options = {}) {
  const response = await fetch(`${baseURL}${pathname}`, {
    ...options,
    headers: {
      authorization: `Bearer ${token}`,
      ...(options.headers ?? {}),
    },
  });
  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new Error(`relay returned non-JSON HTTP ${response.status}`);
  }
  assert.equal(
    response.ok,
    true,
    `relay request failed with HTTP ${response.status}: ${payload?.error ?? 'unknown_error'}`,
  );
  return payload;
}

async function waitForFinality(publicDataProvider, transactionID) {
  let timeout;
  try {
    return await Promise.race([
      publicDataProvider.watchForTxData(transactionID),
      new Promise((_, reject) => {
        timeout = setTimeout(
          () => reject(new Error('transaction finality timed out')),
          finalityTimeoutMilliseconds,
        );
      }),
    ]);
  } finally {
    clearTimeout(timeout);
  }
}

async function waitForRelayConfirmation(baseURL, token, commitmentHex) {
  const deadline = Date.now() + finalityTimeoutMilliseconds;
  while (Date.now() < deadline) {
    const payload = await fetchRelayJSON(baseURL, `/confirm/${commitmentHex}`, token);
    if (payload.status === 'confirmed') return;
    assert.equal(payload.status, 'pending', 'relay rejected the indexed commitment');
    await new Promise((resolve) => setTimeout(resolve, confirmationPollMilliseconds));
  }
  throw new Error('relay commitment confirmation timed out');
}

async function main() {
  await preflight();
  const scratch = await mkdtemp(path.join(tmpdir(), 'slip-phase7-relay-'));
  await chmod(scratch, 0o700);
  let setupWallet;
  let setupWalletStopped = false;
  let publicDataProvider;
  let relayRuntime;
  let relayServer;

  try {
    setupWallet = await buildSetupWallet();
    await waitForWalletSync(setupWallet.wallet);
    console.log('phase7: setup wallet synced');

    const zkConfigProvider = new NodeZkConfigProvider(generatedRoot);
    publicDataProvider = indexerPublicDataProvider(localNetwork.indexer, localNetwork.indexerWS);
    const privateStateProvider = levelPrivateStateProvider({
      midnightDbName: path.join(scratch, 'midnight-level-db'),
      privateStateStoreName: 'private-states',
      signingKeyStoreName: 'signing-keys',
      privateStoragePasswordProvider: () => 'Slip-Phase7-Relay-Demo!1',
      accountId: setupWallet.getCoinPublicKey(),
    });
    const standardProviders = {
      privateStateProvider,
      publicDataProvider,
      zkConfigProvider,
      proofProvider: httpClientProofProvider(localNetwork.proofServer, zkConfigProvider),
      walletProvider: setupWallet,
      midnightProvider: setupWallet,
    };
    const witnesses = {
      localSecretKey: ({ privateState }) => [privateState, syntheticSecret],
      localPick: ({ privateState }) => [privateState, syntheticPick],
    };
    const compiled = CompiledContract.make('SlipContract', Contract).pipe(
      (contract) => CompiledContract.withWitnesses(contract, witnesses),
      (contract) => CompiledContract.withCompiledFileAssets(contract, generatedRoot),
    );

    console.log('phase7: deploying and preparing Slip through the pinned standard path');
    const deployed = await deployContract(standardProviders, {
      compiledContract: compiled,
      privateStateId: privateStateID,
      initialPrivateState: {},
      args: [],
    });
    assert.equal(deployed.deployTxData.public.status, SucceedEntirely, 'deployment did not succeed entirely');
    const contractAddress = deployed.deployTxData.public.contractAddress;
    console.log(`phase7: deployed ${contractAddress}`);

    // SLIP_MEMBER_ID (64 hex): enrol a real device's PUBLIC member id instead of the synthetic
    // member, so a phone can seal against this round. Public data only.
    const memberID = process.env.SLIP_MEMBER_ID
      ? Uint8Array.from(Buffer.from(process.env.SLIP_MEMBER_ID, 'hex'))
      : pureCircuits.memberIdOf(syntheticSecret);
    assert.equal(memberID.length, 32, 'SLIP_MEMBER_ID must be 32 bytes of hex');
    const enrollment = await submitCallTx(standardProviders, {
      compiledContract: compiled,
      contractAddress,
      privateStateId: privateStateID,
      circuitId: 'enrollMember',
      args: [memberID],
    });
    assert.equal(enrollment.public.status, SucceedEntirely, 'enrollment did not succeed entirely');

    const beforeCreate = await latestBlock();
    const creation = await submitCallTx(standardProviders, {
      compiledContract: compiled,
      contractAddress,
      privateStateId: privateStateID,
      circuitId: 'createSlip',
      args: [new Uint8Array(32).fill(9), BigInt(beforeCreate.seconds + 7_200)],
    });
    assert.equal(creation.public.status, SucceedEntirely, 'createSlip did not succeed entirely');
    console.log('phase7: enrollMember/createSlip SucceedEntirely');

    const coinPublicKey = setupWallet.coinPublicKey;
    await setupWallet.wallet.stop();
    setupWalletStopped = true;

    const relayToken = randomBytes(32).toString('hex');
    const relayConfiguration = loadRelayConfiguration({
      SLIP_RELAY_TOKEN: relayToken,
      SLIP_CONTRACT_ADDRESS: contractAddress,
      // Serve mode may bind beyond loopback for a phone on the LAN (explicit opt-in).
      SLIP_RELAY_HOST: process.env.SLIP_RELAY_HOST,
      SLIP_RELAY_ALLOW_LAN: process.env.SLIP_RELAY_ALLOW_LAN,
      SLIP_RELAY_PORT: process.env.SLIP_RELAY_PORT,
    });
    relayRuntime = await createStewardRuntime(relayConfiguration);
    const serving = process.env.SLIP_RELAY_SERVE === '1';
    // serve-mode diagnostics: error MESSAGES only (never transaction bytes, tokens or keys).
    const diag = (label, fn) => async (...args) => {
      try { return await fn(...args); } catch (error) {
        if (serving) console.error(`relay ${label} failed: ${error?.constructor?.name ?? 'Error'} — ${String(error?.message ?? error).slice(0, 300)}`);
        throw error;
      }
    };
    relayServer = createRelayServer({
      configuration: relayConfiguration,
      getContext: diag('context', relayRuntime.getContext),
      submit: diag('submit', relayRuntime.submit),
      confirm: diag('confirm', relayRuntime.confirm),
      logger: serving ? { error: (event) => console.error(`relay: ${event}`) } : {},
    });
    const relayBaseURL = await listen(relayServer);
    console.log('phase7: authenticated relay listening on loopback');
    if (process.env.SLIP_RELAY_SERVE === '1') {
      // Serve mode: hand the round to a real device and keep the relay up until SIGINT.
      // The token is printed ONCE here for the operator; it is never logged elsewhere.
      console.log(`SLIP_RELAY_URL=${relayBaseURL}`);
      console.log(`SLIP_RELAY_TOKEN=${relayToken}`);
      console.log(`SLIP_CONTRACT_ADDRESS=${contractAddress}`);
      console.log('phase7: SERVING — press Ctrl-C to stop');
      await new Promise((resolve) => process.once('SIGINT', resolve));
      console.log('phase7: serve mode stopped by operator');
      return;
    }

    const healthResponse = await fetch(`${relayBaseURL}/health`);
    assert.equal(healthResponse.status, 200, 'relay health check failed');
    assert.deepEqual(await healthResponse.json(), { status: 'ok' }, 'relay health payload changed');
    const unauthorizedResponse = await fetch(`${relayBaseURL}/context/${contractAddress}`);
    assert.equal(unauthorizedResponse.status, 401, 'relay accepted unauthenticated context access');
    assert.deepEqual(
      await unauthorizedResponse.json(),
      { error: 'unauthorized' },
      'relay authentication failure payload changed',
    );

    const publicContext = await fetchRelayJSON(
      relayBaseURL,
      `/context/${contractAddress}`,
      relayToken,
    );
    assert.equal(publicContext.address, contractAddress, 'relay returned another contract');
    assert.match(publicContext.stateHex, /^(?:[0-9a-f]{2})+$/, 'relay returned invalid state hex');
    assert.ok(Number.isSafeInteger(publicContext.blockTimeSecs), 'relay returned invalid block time');

    const liveStateBytes = Buffer.from(publicContext.stateHex, 'hex');
    const liveState = compactRuntime.ContractState.deserialize(liveStateBytes);
    const localPrivateState = await privateStateProvider.get(privateStateID);
    assert.ok(localPrivateState !== null && localPrivateState !== undefined, 'local private state is missing');
    const context = compactRuntime.createCircuitContext(
      contractAddress,
      { bytes: compactRuntime.encodeCoinPublicKey(coinPublicKey) },
      liveState,
      localPrivateState,
      undefined,
      undefined,
      publicContext.blockTimeSecs,
    );
    context.currentQueryContext.block.secondsSinceEpoch = BigInt(publicContext.blockTimeSecs);
    const localResult = await new Contract(witnesses).impureCircuits.sealPick(context);
    const localLedger = ledger(localResult.context.currentQueryContext.state);
    assert.equal(localLedger.seals.member(memberID), true, 'local seal produced no commitment');
    const expectedCommitment = localLedger.seals.lookup(memberID);
    const commitmentHex = Buffer.from(expectedCommitment).toString('hex');

    const proofDataPath = path.join(scratch, 'sealPick-proofData.json');
    const statePath = path.join(scratch, 'sealPick-state.bin');
    const transactionPath = path.join(scratch, 'sealPick-proved-prebinding.bin');
    const proofData = localResult.proofData;
    await Promise.all([
      writeFile(proofDataPath, JSON.stringify({
        input: encodeProofData(proofData.input),
        output: encodeProofData(proofData.output),
        publicTranscript: encodeProofData(proofData.publicTranscript),
        privateTranscriptOutputs: encodeProofData(proofData.privateTranscriptOutputs),
      }), { mode: 0o600 }),
      writeFile(statePath, liveStateBytes, { mode: 0o600 }),
    ]);

    const transactionTTLSeconds = publicContext.blockTimeSecs + 3_600;
    const { stdout } = await execFile(nativeProver, [
      'assemble',
      '--proofdata', proofDataPath,
      '--state', statePath,
      '--address', contractAddress,
      '--entry', 'sealPick',
      '--verifier', path.join(generatedRoot, 'keys', 'sealPick.verifier'),
      '--block', String(publicContext.blockTimeSecs),
      '--ttl', String(transactionTTLSeconds),
      '--zkir-dir', path.join(generatedRoot, 'zkir'),
      '--keys-dir', path.join(generatedRoot, 'keys'),
      '--params', path.join(generatedRoot, 'params'),
      '--network', 'undeployed',
      '--out', transactionPath,
    ], { timeout: 120_000, maxBuffer: 1_048_576 });
    await unlink(proofDataPath);
    await chmod(transactionPath, 0o600);
    const nativeResult = JSON.parse(stdout.trim().split('\n').at(-1));
    assert.equal(nativeResult.ok, true, 'native transaction assembly failed');

    const transactionBytes = await readFile(transactionPath);
    await unlink(transactionPath);
    assert.equal(transactionBytes.length, nativeResult.bytes, 'native byte count differs from output file');
    const decodedTransaction = Transaction.deserialize(
      'signature',
      'proof',
      'pre-binding',
      transactionBytes,
    );
    const canonicalTransactionBytes = Buffer.from(decodedTransaction.serialize());
    try {
      assert.equal(
        canonicalTransactionBytes.equals(transactionBytes),
        true,
        'native transaction did not round-trip canonically',
      );
    } finally {
      canonicalTransactionBytes.fill(0);
    }
    const witnessPattern = Buffer.from(syntheticSecret);
    const positiveControl = Buffer.from(transactionBytes);
    try {
      witnessPattern.copy(positiveControl, 0);
      assert.equal(positiveControl.includes(witnessPattern), true, 'planted witness control failed');
      assert.equal(transactionBytes.includes(witnessPattern), false, 'relay payload contains witness pattern');
    } finally {
      positiveControl.fill(0);
      witnessPattern.fill(0);
    }

    let submission;
    try {
      submission = await fetchRelayJSON(relayBaseURL, '/submit', relayToken, {
        method: 'POST',
        headers: { 'content-type': 'application/octet-stream' },
        body: transactionBytes,
      });
    } finally {
      transactionBytes.fill(0);
    }
    assert.equal(typeof submission.txId, 'string', 'relay returned no transaction id');

    const finalized = await waitForFinality(publicDataProvider, submission.txId);
    assert.equal(finalized.status, SucceedEntirely, 'relayed sealPick did not succeed entirely');
    await waitForRelayConfirmation(relayBaseURL, relayToken, commitmentHex);

    const indexedState = await publicDataProvider.queryContractState(contractAddress);
    assert.ok(indexedState, 'indexer returned no post-seal contract state');
    const indexedLedger = ledger(indexedState.data);
    assert.equal(indexedLedger.seals.member(memberID), true, 'indexer has no seal for the member');
    assert.equal(
      bytesEqual(indexedLedger.seals.lookup(memberID), expectedCommitment),
      true,
      'indexed commitment differs from local execution',
    );

    console.log(`phase7: native assembly ok (${nativeResult.bytes} bytes, ${nativeResult.ms} ms)`);
    console.log(`phase7: relayed sealPick ${finalized.status} at block ${finalized.blockHeight}`);
    console.log(`phase7: transaction ${submission.txId}`);
    console.log(`phase7: indexed commitment ${commitmentHex}`);
  } finally {
    const cleanupFailures = [];
    try {
      if (relayServer) await closeServer(relayServer);
    } catch {
      cleanupFailures.push('relay server');
    }
    try {
      if (relayRuntime) await relayRuntime.stop();
    } catch {
      cleanupFailures.push('relay runtime');
    }
    if (publicDataProvider?.dispose) {
      try { await publicDataProvider.dispose(); } catch { cleanupFailures.push('public data provider'); }
    }
    if (setupWallet?.wallet && !setupWalletStopped) {
      try { await setupWallet.wallet.stop(); } catch { cleanupFailures.push('setup wallet'); }
    }
    assert.ok(
      scratch.startsWith(`${path.resolve(tmpdir())}${path.sep}slip-phase7-relay-`),
      'refusing to remove an unexpected scratch path',
    );
    try { await rm(scratch, { recursive: true, force: true }); } catch { cleanupFailures.push('scratch'); }
    assert.deepEqual(cleanupFailures, [], `cleanup failed: ${cleanupFailures.join(', ')}`);
  }

  console.log('PHASE7 LIVE RELAY DEMO: PASS');
}

main().catch((error) => {
  console.error(`PHASE7 LIVE RELAY DEMO: FAIL — ${safeLine(error)}`);
  process.exitCode = 1;
});

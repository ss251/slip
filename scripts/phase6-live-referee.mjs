#!/usr/bin/env node

// Phase 6 referee: prove Slip's sealPick call with the native ledger-8 assembler,
// then let the pinned wallet balance/finalize it and the local node verify it.
//
// This is deliberately a host-only, undeployed-network check. The secret below is
// synthetic test material, proofData lives only in a mode-0700 temporary directory,
// and neither it nor the proof bytes are printed. The native seal proof does not use
// the HTTP proof provider; standard setup calls and the wallet's DUST proof still do.

import assert from 'node:assert/strict';
import { execFile as execFileCallback } from 'node:child_process';
import { access, chmod, mkdtemp, readFile, readdir, rm, unlink, writeFile } from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';

const execFile = promisify(execFileCallback);
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, '..');
const e2eRoot = path.join(repositoryRoot, 'contracts', 'e2e');
const moduleRoot = path.join(e2eRoot, 'node_modules');
const zkRoot = path.join(e2eRoot, 'slip-build');
const canonicalZkRoot = path.join(repositoryRoot, 'contracts', 'build');
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
  import(pathToFileURL(path.join(zkRoot, 'contract', 'index.js')).href),
]);

const configuration = {
  walletNetworkId: 'undeployed',
  networkId: 'undeployed',
  indexer: 'http://localhost:8088/api/v4/graphql',
  indexerWS: 'ws://localhost:8088/api/v4/graphql/ws',
  node: 'http://localhost:9944',
  nodeWS: 'ws://localhost:9944',
  proofServer: 'http://localhost:6300',
  faucet: '',
};
const genesisSeed = '0000000000000000000000000000000000000000000000000000000000000001';
const syntheticSecret = new Uint8Array(32).fill(7);
const syntheticPick = 1n;
const privateStateID = 'slip-phase6-native-referee';
const finalityTimeoutMilliseconds = 60_000;

setNetworkId('undeployed');

const safeLine = (error) => String(error?.message ?? error).split('\n', 1)[0].slice(0, 320);
const bytesEqual = (left, right) => Buffer.from(left).equals(Buffer.from(right));
const encodeProofData = (value) => JSON.parse(JSON.stringify(value, (_, item) => {
  if (typeof item === 'bigint') return item.toString();
  if (item instanceof Uint8Array) return Array.from(item);
  return item;
}));

async function preflight() {
  await Promise.all([
    access(nativeProver),
    access(path.join(zkRoot, 'contract', 'index.js')),
    access(path.join(zkRoot, 'zkir', 'sealPick.zkir')),
    access(path.join(zkRoot, 'keys', 'sealPick.prover')),
    access(path.join(zkRoot, 'keys', 'sealPick.verifier')),
    access(path.join(zkRoot, 'params', 'bls_midnight_2p14')),
  ]);

  const relativeFiles = async (root, relative = '') => {
    const entries = await readdir(path.join(root, relative), { withFileTypes: true });
    const nested = await Promise.all(entries.map((entry) => {
      const child = path.join(relative, entry.name);
      return entry.isDirectory() ? relativeFiles(root, child) : [child];
    }));
    return nested.flat().sort();
  };
  // Compare only the compiler artifacts this referee consumes. Build-root scratch can
  // contain private preimages/proofData and must never be enumerated or read here.
  for (const artifactDirectory of ['contract', 'zkir', 'keys', 'params']) {
    const [canonicalFiles, linkedFiles] = await Promise.all([
      relativeFiles(path.join(canonicalZkRoot, artifactDirectory)),
      relativeFiles(path.join(zkRoot, artifactDirectory)),
    ]);
    assert.deepEqual(
      linkedFiles,
      canonicalFiles,
      `contracts/e2e/slip-build/${artifactDirectory} is stale; run node contracts/e2e/link-build.mjs`,
    );
    for (const relative of canonicalFiles) {
      const [canonical, linked] = await Promise.all([
        readFile(path.join(canonicalZkRoot, artifactDirectory, relative)),
        readFile(path.join(zkRoot, artifactDirectory, relative)),
      ]);
      assert.equal(
        bytesEqual(linked, canonical),
        true,
        `contracts/e2e/slip-build/${artifactDirectory}/${relative} is stale; run node contracts/e2e/link-build.mjs`,
      );
    }
  }
}

async function latestBlock() {
  const response = await fetch(configuration.indexer, {
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
  // Indexer v4 timestamps feed new Date(timestamp) in wallet-sdk, hence milliseconds;
  // Compact BlockContext.secondsSinceEpoch is seconds.
  assert.ok(block.timestamp > 1_000_000_000_000, 'indexer block timestamp is not milliseconds');
  return {
    height: block.height,
    hash: block.hash,
    seconds: Math.floor(block.timestamp / 1_000),
  };
}

async function buildWallet() {
  const built = await FluentWalletBuilder.forEnvironment(configuration)
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
    try {
      await wallet.stop();
    } catch (cleanupError) {
      throw new AggregateError([error, cleanupError], 'wallet start and cleanup failed');
    }
    throw error;
  }
  return {
    wallet,
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
    subscription = wallet.state().subscribe((state) => {
      if (!settled && state.isSynced) {
        settled = true;
        clearTimeout(timeout);
        queueMicrotask(() => subscription?.unsubscribe());
        resolve();
      }
    });
  });
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

async function main() {
  await preflight();
  const scratch = await mkdtemp(path.join(tmpdir(), 'slip-phase6-live-'));
  await chmod(scratch, 0o700);
  let walletProvider;
  let publicDataProvider;

  try {
    walletProvider = await buildWallet();
    await waitForWalletSync(walletProvider.wallet);
    console.log('phase6: genesis wallet synced');

    const zkConfigProvider = new NodeZkConfigProvider(zkRoot);
    publicDataProvider = indexerPublicDataProvider(configuration.indexer, configuration.indexerWS);
    const privateStateProvider = levelPrivateStateProvider({
      midnightDbName: path.join(scratch, 'midnight-level-db'),
      privateStateStoreName: 'private-states',
      signingKeyStoreName: 'signing-keys',
      privateStoragePasswordProvider: () => 'Slip-Phase6-Referee!1',
      accountId: walletProvider.getCoinPublicKey(),
    });
    const standardProviders = {
      privateStateProvider,
      publicDataProvider,
      zkConfigProvider,
      proofProvider: httpClientProofProvider(configuration.proofServer, zkConfigProvider),
      walletProvider,
      midnightProvider: walletProvider,
    };
    const witnesses = {
      localSecretKey: ({ privateState }) => [privateState, syntheticSecret],
      localPick: ({ privateState }) => [privateState, syntheticPick],
    };
    const compiled = CompiledContract.make('SlipContract', Contract).pipe(
      (contract) => CompiledContract.withWitnesses(contract, witnesses),
      (contract) => CompiledContract.withCompiledFileAssets(contract, zkRoot),
    );

    console.log('phase6: deploying Slip with the standard pinned path');
    const deployed = await deployContract(standardProviders, {
      compiledContract: compiled,
      privateStateId: privateStateID,
      initialPrivateState: {},
      args: [],
    });
    assert.equal(deployed.deployTxData.public.status, SucceedEntirely, 'deployment did not succeed entirely');
    const address = deployed.deployTxData.public.contractAddress;
    console.log(`phase6: deployed ${address}`);

    const memberID = pureCircuits.memberIdOf(syntheticSecret);
    const enrollment = await submitCallTx(standardProviders, {
      compiledContract: compiled,
      contractAddress: address,
      privateStateId: privateStateID,
      circuitId: 'enrollMember',
      args: [memberID],
    });
    assert.equal(enrollment.public.status, SucceedEntirely, 'enrollment did not succeed entirely');
    console.log('phase6: enrollMember SucceedEntirely');

    const beforeCreate = await latestBlock();
    const deadline = BigInt(beforeCreate.seconds + 7_200);
    const creation = await submitCallTx(standardProviders, {
      compiledContract: compiled,
      contractAddress: address,
      privateStateId: privateStateID,
      circuitId: 'createSlip',
      args: [new Uint8Array(32).fill(9), deadline],
    });
    assert.equal(creation.public.status, SucceedEntirely, 'createSlip did not succeed entirely');
    console.log('phase6: createSlip SucceedEntirely');

    const block = await latestBlock();
    const liveState = await publicDataProvider.queryContractState(address, {
      type: 'blockHash',
      blockHash: block.hash,
    });
    assert.ok(liveState, 'indexer returned no live contract state');
    // Snapshot before local execution because runtime objects can be evolved in place.
    const liveStateBytes = Buffer.from(liveState.serialize());
    const localPrivateState = await privateStateProvider.get(privateStateID);
    assert.ok(
      localPrivateState !== null && localPrivateState !== undefined,
      'local private state is missing',
    );
    const encodedCoinPublicKey = {
      bytes: compactRuntime.encodeCoinPublicKey(walletProvider.getCoinPublicKey()),
    };
    const context = compactRuntime.createCircuitContext(
      address,
      encodedCoinPublicKey,
      liveState,
      localPrivateState,
      undefined,
      undefined,
      block.seconds,
    );
    context.currentQueryContext.block.secondsSinceEpoch = BigInt(block.seconds);
    const localResult = await new Contract(witnesses).impureCircuits.sealPick(context);
    const localLedger = ledger(localResult.context.currentQueryContext.state);
    assert.equal(localLedger.seals.member(memberID), true, 'local seal produced no commitment');
    const expectedCommitment = localLedger.seals.lookup(memberID);

    const proofDataPath = path.join(scratch, 'sealPick-proofData.json');
    const statePath = path.join(scratch, 'sealPick-state.bin');
    const transactionPath = path.join(scratch, 'sealPick-proved-unbalanced.bin');
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

    const transactionTTLSeconds = block.seconds + 3_600;
    const { stdout } = await execFile(nativeProver, [
      'assemble',
      '--proofdata', proofDataPath,
      '--state', statePath,
      '--address', address,
      '--entry', 'sealPick',
      '--verifier', path.join(zkRoot, 'keys', 'sealPick.verifier'),
      '--block', String(block.seconds),
      '--ttl', String(transactionTTLSeconds),
      '--zkir-dir', path.join(zkRoot, 'zkir'),
      '--keys-dir', path.join(zkRoot, 'keys'),
      '--params', path.join(zkRoot, 'params'),
      '--network', 'undeployed',
      '--out', transactionPath,
    ], { timeout: 120_000, maxBuffer: 1_048_576 });
    await unlink(proofDataPath);
    const nativeResult = JSON.parse(stdout.trim().split('\n').at(-1));
    assert.equal(nativeResult.ok, true, 'native transaction assembly failed');
    console.log(`phase6: native assembly ok (${nativeResult.bytes} bytes, ${nativeResult.ms} ms)`);

    const unboundBytes = new Uint8Array(await readFile(transactionPath));
    assert.equal(nativeResult.bytes, unboundBytes.length, 'native byte count differs from output file');
    const unbound = Transaction.deserialize('signature', 'proof', 'pre-binding', unboundBytes);
    assert.equal(
      bytesEqual(unbound.serialize(), unboundBytes),
      true,
      'transaction deserialize round-trip changed bytes',
    );
    const walletTTL = new Date(transactionTTLSeconds * 1_000);
    const finalized = await walletProvider.balanceTx(unbound, walletTTL);
    const finalizedBytes = Buffer.from(finalized.serialize());
    const witnessPattern = Buffer.from(syntheticSecret);
    const positiveControl = Buffer.from(finalizedBytes);
    try {
      witnessPattern.copy(positiveControl, 0);
      assert.equal(
        positiveControl.includes(witnessPattern),
        true,
        'planted witness-pattern control was not detected',
      );
      assert.equal(
        finalizedBytes.includes(witnessPattern),
        false,
        'finalized transaction contains the synthetic witness pattern',
      );
    } finally {
      positiveControl.fill(0);
      witnessPattern.fill(0);
      finalizedBytes.fill(0);
    }

    const transactionID = await walletProvider.submitTx(finalized);
    const finalizedData = await waitForFinality(publicDataProvider, transactionID);
    assert.equal(finalizedData.status, SucceedEntirely, 'sealPick did not succeed entirely');
    const indexedState = await publicDataProvider.queryContractState(address);
    assert.ok(indexedState, 'indexer returned no post-seal contract state');
    const indexedLedger = ledger(indexedState.data);
    assert.equal(indexedLedger.seals.member(memberID), true, 'indexer has no seal for the member');
    assert.equal(
      bytesEqual(indexedLedger.seals.lookup(memberID), expectedCommitment),
      true,
      'indexed commitment differs from local execution',
    );

    console.log(`phase6: sealPick ${finalizedData.status} at block ${finalizedData.blockHeight}`);
    console.log(`phase6: indexed commitment ${Buffer.from(expectedCommitment).toString('hex')}`);
  } finally {
    const cleanupFailures = [];
    if (publicDataProvider?.dispose) {
      try {
        await publicDataProvider.dispose();
      } catch {
        cleanupFailures.push('public data provider');
      }
    }
    if (walletProvider?.wallet) {
      try {
        await walletProvider.wallet.stop();
      } catch {
        cleanupFailures.push('wallet');
      }
    }
    assert.ok(
      scratch.startsWith(`${path.resolve(tmpdir())}${path.sep}slip-phase6-live-`),
      'refusing to remove an unexpected scratch path',
    );
    try {
      await rm(scratch, { recursive: true, force: true });
    } catch {
      cleanupFailures.push('scratch directory');
    }
    assert.deepEqual(cleanupFailures, [], `cleanup failed: ${cleanupFailures.join(', ')}`);
  }

  console.log('PHASE6 LIVE REFEREE: PASS');
}

main().catch((error) => {
  console.error(`PHASE6 LIVE REFEREE: FAIL — ${safeLine(error)}`);
  process.exitCode = 1;
});

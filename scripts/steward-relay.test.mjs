import assert from 'node:assert/strict';
import { request as httpRequest } from 'node:http';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import test from 'node:test';

import {
  MAX_BODY_BYTES,
  RelayPolicyError,
  RelayRequestError,
  assertRelayTTL,
  balanceSignFinalizeSubmit,
  createRelayServer,
  createSubmissionCoordinator,
  deserializeCanonicalTransaction,
  fetchContractContext,
  inspectSealPickTransaction,
  loadRelayConfiguration,
  queryLatestBlock,
  requestIsAuthorized,
  stateContainsCommitment,
  submissionWasExplicitlyRejected,
} from './steward-relay.mjs';

const address = '11'.repeat(32);
const token = 'ab'.repeat(32);
const authorization = { authorization: `Bearer ${token}` };
const configuration = Object.freeze({
  host: '127.0.0.1',
  port: 0,
  token,
  contractAddress: address,
  maxBodyBytes: 64,
  maxTTLSeconds: 3_600,
});

async function startServer(overrides = {}) {
  const errors = [];
  const server = createRelayServer({
    configuration,
    getContext: async () => ({
      address,
      state: Buffer.from('midnight:contract-state[v6]:'),
      blockTimeSecs: 1_788_547_200,
    }),
    submit: async () => 'tx-test-id',
    confirm: async () => 'pending',
    logger: { error: (value) => errors.push(value) },
    ...overrides,
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const { port } = server.address();
  return {
    baseURL: `http://127.0.0.1:${port}`,
    errors,
    async close() {
      await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    },
  };
}

async function fetchJSON(baseURL, pathname, options = {}) {
  const response = await fetch(`${baseURL}${pathname}`, options);
  return { response, body: await response.json() };
}

async function chunkedRequest(baseURL, pathname, chunks, headers = {}) {
  const url = new URL(pathname, baseURL);
  return new Promise((resolve, reject) => {
    const request = httpRequest(url, { method: 'POST', headers }, (response) => {
      const responseChunks = [];
      response.on('data', (chunk) => responseChunks.push(chunk));
      response.on('end', () => resolve({
        status: response.statusCode,
        body: JSON.parse(Buffer.concat(responseChunks).toString('utf8')),
      }));
    });
    request.on('error', reject);
    for (const chunk of chunks) request.write(chunk);
    request.end();
  });
}

test('configuration requires a strong token, fixed contract, and explicit LAN opt-in', () => {
  const base = { SLIP_RELAY_TOKEN: token, SLIP_CONTRACT_ADDRESS: address };
  const result = loadRelayConfiguration(base);
  assert.equal(result.host, '127.0.0.1');
  assert.equal(result.port, 8_787);
  assert.equal(result.contractAddress, address);
  assert.equal(result.network.networkId, 'undeployed');
  assert.equal(result.network.node, 'http://localhost:9944');
  assert.throws(() => loadRelayConfiguration({ ...base, SLIP_RELAY_TOKEN: 'short' }), /64 hex/);
  assert.throws(() => loadRelayConfiguration({ ...base, SLIP_RELAY_HOST: '0.0.0.0' }), /ALLOW_LAN/);
  assert.equal(loadRelayConfiguration({
    ...base,
    SLIP_RELAY_HOST: '0.0.0.0',
    SLIP_RELAY_ALLOW_LAN: '1',
    SLIP_RELAY_PORT: '9876',
  }).port, 9_876);
  assert.throws(() => loadRelayConfiguration({ ...base, SLIP_CONTRACT_ADDRESS: 'ab' }), /32 bytes/);
});

test('bearer comparison requires the exact token', () => {
  assert.equal(requestIsAuthorized(undefined, token), false);
  assert.equal(requestIsAuthorized('Bearer wrong', token), false);
  assert.equal(requestIsAuthorized(`Basic ${token}`, token), false);
  assert.equal(requestIsAuthorized(`Bearer ${token}`, token), true);
});

test('health is public while every work endpoint is authenticated', async (t) => {
  const fixture = await startServer();
  t.after(() => fixture.close());
  const health = await fetchJSON(fixture.baseURL, '/health');
  assert.equal(health.response.status, 200);
  assert.deepEqual(health.body, { status: 'ok' });

  const missing = await fetchJSON(fixture.baseURL, `/context/${address}`);
  assert.equal(missing.response.status, 401);
  assert.deepEqual(missing.body, { error: 'unauthorized' });
  const wrong = await fetchJSON(fixture.baseURL, `/confirm/${'22'.repeat(32)}`, {
    headers: { authorization: 'Bearer wrong' },
  });
  assert.equal(wrong.response.status, 401);
  assert.equal(JSON.stringify(wrong.body).includes(token), false);
});

test('context is block-shaped, contract-scoped, cache-disabled, and GET-only', async (t) => {
  let requestedAddress;
  const fixture = await startServer({
    getContext: async (value) => {
      requestedAddress = value;
      return { address, state: Uint8Array.of(1, 2, 3), blockTimeSecs: 1_788_547_201 };
    },
  });
  t.after(() => fixture.close());
  const result = await fetchJSON(fixture.baseURL, `/context/${address}`, { headers: authorization });
  assert.equal(result.response.status, 200);
  assert.equal(result.response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(result.body, { address, stateHex: '010203', blockTimeSecs: 1_788_547_201 });
  assert.equal(requestedAddress, address);

  const another = await fetchJSON(fixture.baseURL, `/context/${'22'.repeat(32)}`, { headers: authorization });
  assert.equal(another.response.status, 404);
  const wrongMethod = await fetchJSON(fixture.baseURL, `/context/${address}`, {
    method: 'POST',
    headers: authorization,
  });
  assert.equal(wrongMethod.response.status, 405);
  assert.equal(wrongMethod.response.headers.get('allow'), 'GET');
});

test('submit accepts only bounded raw octets and returns only a transaction id', async (t) => {
  const received = [];
  const fixture = await startServer({ submit: async (body) => {
    received.push(Buffer.from(body));
    return 'safe-id';
  } });
  t.after(() => fixture.close());

  const wrongType = await fetchJSON(fixture.baseURL, '/submit', {
    method: 'POST',
    headers: { ...authorization, 'content-type': 'application/json' },
    body: '{}',
  });
  assert.equal(wrongType.response.status, 415);
  const empty = await fetchJSON(fixture.baseURL, '/submit', {
    method: 'POST',
    headers: { ...authorization, 'content-type': 'application/octet-stream' },
    body: Buffer.alloc(0),
  });
  assert.equal(empty.response.status, 400);
  const tooLarge = await fetchJSON(fixture.baseURL, '/submit', {
    method: 'POST',
    headers: { ...authorization, 'content-type': 'application/octet-stream' },
    body: Buffer.alloc(65),
  });
  assert.equal(tooLarge.response.status, 413);

  const accepted = await fetchJSON(fixture.baseURL, '/submit', {
    method: 'POST',
    headers: { ...authorization, 'content-type': 'application/octet-stream' },
    body: Buffer.from([1, 2, 3]),
  });
  assert.equal(accepted.response.status, 200);
  assert.deepEqual(accepted.body, { txId: 'safe-id' });
  assert.deepEqual(received, [Buffer.from([1, 2, 3])]);
});

test('authenticated submit requests are rate-limited per relay process', async (t) => {
  let clock = 1_000;
  const fixture = await startServer({
    maximumSubmissionsPerMinute: 1,
    now: () => clock,
  });
  t.after(() => fixture.close());
  const options = {
    method: 'POST',
    headers: { ...authorization, 'content-type': 'application/octet-stream' },
    body: Buffer.of(1),
  };
  assert.equal((await fetchJSON(fixture.baseURL, '/submit', options)).response.status, 200);
  const limited = await fetchJSON(fixture.baseURL, '/submit', options);
  assert.equal(limited.response.status, 429);
  assert.deepEqual(limited.body, { error: 'rate_limited' });
  clock += 60_000;
  assert.equal((await fetchJSON(fixture.baseURL, '/submit', options)).response.status, 200);
});

test('chunked request bodies cannot bypass the cap', async (t) => {
  let calls = 0;
  const fixture = await startServer({ submit: async () => { calls += 1; return 'never'; } });
  t.after(() => fixture.close());
  const result = await chunkedRequest(fixture.baseURL, '/submit', [Buffer.alloc(40), Buffer.alloc(40)], {
    ...authorization,
    'content-type': 'application/octet-stream',
  });
  assert.equal(result.status, 413);
  assert.deepEqual(result.body, { error: 'payload_too_large' });
  assert.equal(calls, 0);
});

test('confirmation has an exact status vocabulary and commitment shape', async (t) => {
  const fixture = await startServer({ confirm: async () => 'confirmed' });
  t.after(() => fixture.close());
  const result = await fetchJSON(fixture.baseURL, `/confirm/${'ab'.repeat(32)}`, { headers: authorization });
  assert.deepEqual(result.body, { status: 'confirmed' });
  const malformed = await fetchJSON(fixture.baseURL, '/confirm/abcd', { headers: authorization });
  assert.equal(malformed.response.status, 404);
});

test('server never echoes request, token, or internal error detail', async (t) => {
  const planted = 'private-witness-pattern-that-must-not-escape';
  const fixture = await startServer({
    submit: async () => { throw new Error(planted); },
  });
  t.after(() => fixture.close());
  const result = await fetchJSON(fixture.baseURL, '/submit', {
    method: 'POST',
    headers: { ...authorization, 'content-type': 'application/octet-stream' },
    body: planted,
  });
  const rendered = JSON.stringify(result.body);
  assert.equal(result.response.status, 500);
  assert.deepEqual(result.body, { error: 'internal_error' });
  assert.equal(rendered.includes(planted), false);
  assert.equal(rendered.includes(token), false);
  assert.deepEqual(fixture.errors, ['relay_request_failed']);
});

function emptyEffects() {
  return {
    claimedNullifiers: [],
    claimedShieldedReceives: [],
    claimedShieldedSpends: [],
    claimedContractCalls: [],
    shieldedMints: new Map(),
    unshieldedMints: new Map(),
    unshieldedInputs: new Map(),
    unshieldedOutputs: new Map(),
    claimedUnshieldedSpends: new Map(),
  };
}

class FakeContractCall {}

function fakeTransaction() {
  const call = Object.assign(new FakeContractCall(), {
    address,
    entryPoint: 'sealPick',
    guaranteedTranscript: { effects: emptyEffects(), program: [], gas: {} },
    fallibleTranscript: undefined,
  });
  const intent = {
    guaranteedUnshieldedOffer: undefined,
    fallibleUnshieldedOffer: undefined,
    dustActions: undefined,
    actions: [call],
    ttl: new Date('2026-09-05T14:30:00.000Z'),
  };
  return {
    rewards: undefined,
    guaranteedOffer: undefined,
    fallibleOffer: undefined,
    intents: new Map([[7, intent]]),
    identifiers: () => [`00${'12'.repeat(32)}`],
  };
}

function expectPolicy(code, mutate) {
  const transaction = fakeTransaction();
  mutate(transaction, [...transaction.intents.values()][0], [...transaction.intents.values()][0].actions[0]);
  assert.throws(
    () => inspectSealPickTransaction(transaction, { ContractCall: FakeContractCall, contractAddress: address }),
    (error) => error instanceof RelayPolicyError && error.code === code,
  );
}

test('seal policy admits only one guaranteed effect-free call to configured sealPick', () => {
  const accepted = inspectSealPickTransaction(fakeTransaction(), {
    ContractCall: FakeContractCall,
    contractAddress: address,
  });
  assert.equal(accepted.ttl.toISOString(), '2026-09-05T14:30:00.000Z');

  const cases = [
    ['rewards_not_allowed', (tx) => { tx.rewards = {}; }],
    ['guaranteed_offer_not_allowed', (tx) => { tx.guaranteedOffer = {}; }],
    ['fallible_offer_not_allowed', (tx) => { tx.fallibleOffer = new Map(); }],
    ['exactly_one_intent_required', (tx) => { tx.intents.set(8, {}); }],
    ['invalid_segment', (tx, intent) => { tx.intents = new Map([[0, intent]]); }],
    ['unshielded_offer_not_allowed', (_tx, intent) => { intent.guaranteedUnshieldedOffer = {}; }],
    ['unshielded_offer_not_allowed', (_tx, intent) => { intent.fallibleUnshieldedOffer = {}; }],
    ['preexisting_dust_not_allowed', (_tx, intent) => { intent.dustActions = {}; }],
    ['exactly_one_action_required', (_tx, intent) => { intent.actions = []; }],
    ['contract_call_required', (_tx, intent) => { intent.actions = [{}]; }],
    ['wrong_contract', (_tx, _intent, call) => { call.address = '22'.repeat(32); }],
    ['wrong_entry_point', (_tx, _intent, call) => { call.entryPoint = 'settle'; }],
    ['guaranteed_transcript_required', (_tx, _intent, call) => { call.guaranteedTranscript = undefined; }],
    ['fallible_transcript_not_allowed', (_tx, _intent, call) => { call.fallibleTranscript = {}; }],
    ['effects_required', (_tx, _intent, call) => { call.guaranteedTranscript.effects = undefined; }],
    ['invalid_ttl', (_tx, intent) => { intent.ttl = new Date(Number.NaN); }],
    ['invalid_transaction_identifier', (tx) => { tx.identifiers = () => []; }],
  ];
  for (const field of Object.keys(emptyEffects())) {
    cases.push([`external_effect_${field}`, (_tx, _intent, call) => {
      call.guaranteedTranscript.effects[field] = [1];
    }]);
  }
  for (const [code, mutate] of cases) expectPolicy(code, mutate);

  const bytesEntryPoint = fakeTransaction();
  [...bytesEntryPoint.intents.values()][0].actions[0].entryPoint = new TextEncoder().encode('sealPick');
  assert.doesNotThrow(() => inspectSealPickTransaction(bytesEntryPoint, {
    ContractCall: FakeContractCall,
    contractAddress: address,
  }));
  expectPolicy('invalid_entry_point', (_tx, _intent, call) => {
    call.entryPoint = Uint8Array.of(0xff);
  });
});

test('relay TTL is measured against chain time and bounded', () => {
  const block = 1_000;
  assert.doesNotThrow(() => assertRelayTTL(new Date((block + 1_800) * 1_000), block));
  assert.throws(() => assertRelayTTL(new Date(block * 1_000), block), /expired_ttl/);
  assert.throws(() => assertRelayTTL(new Date((block + 3_601) * 1_000), block), /ttl_too_far/);
});

test('explicit native transaction fixture is canonical and satisfies the strict relay policy', {
  skip: process.env.SLIP_RELAY_FIXTURE_PATH ? false : 'set SLIP_RELAY_FIXTURE_PATH to a synthetic fixture',
}, async () => {
  const ledgerURL = pathToFileURL(path.resolve(
    'contracts/e2e/node_modules/@midnight-ntwrk/midnight-js-protocol/dist/ledger.mjs',
  )).href;
  const { ContractCall, Transaction } = await import(ledgerURL);
  const bytes = await readFile(process.env.SLIP_RELAY_FIXTURE_PATH);
  const transaction = deserializeCanonicalTransaction(bytes, Transaction, MAX_BODY_BYTES);
  const result = inspectSealPickTransaction(transaction, { ContractCall, contractAddress: address });
  assert.ok(result.ttl instanceof Date);

  const withTrailingByte = Buffer.concat([bytes, Buffer.of(0)]);
  assert.throws(
    () => deserializeCanonicalTransaction(withTrailingByte, Transaction, MAX_BODY_BYTES),
    RelayPolicyError,
  );
  assert.throws(
    () => deserializeCanonicalTransaction(Buffer.from('not-a-transaction'), Transaction, MAX_BODY_BYTES),
    RelayPolicyError,
  );
});

test('latest block parsing preserves the hash fence and converts milliseconds once', async () => {
  let request;
  const result = await queryLatestBlock('http://indexer.invalid/graphql', async (url, options) => {
    request = { url, options };
    return {
      ok: true,
      json: async () => ({ data: { block: {
        height: 42,
        hash: 'AB'.repeat(32),
        timestamp: 1_788_547_201_999,
      } } }),
    };
  });
  assert.equal(request.url, 'http://indexer.invalid/graphql');
  assert.equal(request.options.method, 'POST');
  assert.deepEqual(result, { height: 42, hash: 'ab'.repeat(32), seconds: 1_788_547_201 });
});

test('contract context serializes state from the exact latest block hash', async () => {
  const calls = [];
  const result = await fetchContractContext({
    address,
    indexerURL: 'http://indexer.invalid/graphql',
    latestBlock: async (url) => {
      calls.push(['block', url]);
      return { hash: 'ab'.repeat(32), seconds: 1_788_547_222 };
    },
    publicDataProvider: {
      queryContractState: async (requestedAddress, fence) => {
        calls.push(['state', requestedAddress, fence]);
        return { serialize: () => Uint8Array.of(4, 5, 6) };
      },
    },
  });
  assert.deepEqual(calls, [
    ['block', 'http://indexer.invalid/graphql'],
    ['state', address, { type: 'blockHash', blockHash: 'ab'.repeat(32) }],
  ]);
  assert.equal(result.address, address);
  assert.deepEqual(result.state, Buffer.of(4, 5, 6));
  assert.equal(result.blockTimeSecs, 1_788_547_222);
});

test('wallet handoff balances DUST only, then signs, finalizes, and submits in order', async () => {
  const calls = [];
  let retryOperation;
  const ttl = new Date('2026-09-05T14:30:00.000Z');
  const transaction = { stage: 'proved-pre-binding' };
  const zswap = { key: 'shielded' };
  const dust = { key: 'dust' };
  const wallet = {
    balanceUnboundTransaction: async (...args) => { calls.push(['balance', ...args]); return 'recipe'; },
    signRecipe: async (recipe, signer) => {
      calls.push(['sign', recipe, signer(Uint8Array.of(7))]);
      return 'signed';
    },
    finalizeRecipe: async (recipe) => { calls.push(['finalize', recipe]); return 'finalized'; },
    submitTransaction: async (tx) => { calls.push(['submit', tx]); return 'tx-id'; },
    revert: async (value) => { calls.push(['revert', value]); },
  };
  const keystore = { signData: (payload) => `signature-${payload[0]}` };
  assert.equal(await balanceSignFinalizeSubmit({
    wallet,
    zswap,
    dust,
    keystore,
    transaction,
    ttl,
    setSubmissionRetry: (retry) => {
      calls.push(['submission-ready']);
      retryOperation = retry;
    },
  }), 'tx-id');
  assert.deepEqual(calls, [
    ['balance', transaction, { shieldedSecretKeys: zswap, dustSecretKey: dust }, {
      ttl,
      tokenKindsToBalance: ['dust'],
    }],
    ['sign', 'recipe', 'signature-7'],
    ['finalize', 'signed'],
    ['submission-ready'],
    ['submit', 'finalized'],
  ]);
  assert.equal(await retryOperation(), 'tx-id');
  assert.deepEqual(calls.at(-1), ['submit', 'finalized']);
});

test('wallet preparation failure rolls back the selected recipe before retry', async () => {
  const calls = [];
  const wallet = {
    balanceUnboundTransaction: async () => 'recipe',
    signRecipe: async () => { throw new Error('signing failed'); },
    revert: async (value) => { calls.push(['revert', value]); },
  };
  await assert.rejects(balanceSignFinalizeSubmit({
    wallet,
    zswap: {},
    dust: {},
    keystore: {},
    transaction: {},
    ttl: new Date(),
  }), /signing failed/);
  assert.deepEqual(calls, [['revert', 'recipe']]);
});

test('submission coordinator zeroes inputs, deduplicates bytes, and serializes wallet work', async () => {
  let active = 0;
  let maximumActive = 0;
  let submissions = 0;
  const coordinator = createSubmissionCoordinator({
    prepare: (bytes) => ({ value: bytes[0] }),
    submitPrepared: async ({ value }) => {
      submissions += 1;
      active += 1;
      maximumActive = Math.max(maximumActive, active);
      await new Promise((resolve) => setImmediate(resolve));
      active -= 1;
      return `tx-${value}`;
    },
  });
  const first = Buffer.of(1);
  const duplicate = Buffer.of(1);
  const second = Buffer.of(2);
  const results = await Promise.all([
    coordinator.submit(first),
    coordinator.submit(duplicate),
    coordinator.submit(second),
  ]);
  assert.deepEqual(results, ['tx-1', 'tx-1', 'tx-2']);
  assert.equal(submissions, 2);
  assert.equal(maximumActive, 1);
  assert.deepEqual([...first], [0]);
  assert.deepEqual([...duplicate], [0]);
  assert.deepEqual([...second], [0]);
  await coordinator.drain();
});

test('ledger intent identity deduplicates different proof encodings of one call', async () => {
  let submissions = 0;
  const coordinator = createSubmissionCoordinator({
    prepare: (bytes) => ({ value: bytes[0], idempotencyKey: 'intent-1' }),
    submitPrepared: async ({ value }) => {
      submissions += 1;
      await new Promise((resolve) => setImmediate(resolve));
      return `tx-${value}`;
    },
  });
  const [first, alternate] = await Promise.all([
    coordinator.submit(Buffer.of(1, 1)),
    coordinator.submit(Buffer.of(1, 2)),
  ]);
  assert.equal(first, 'tx-1');
  assert.equal(alternate, 'tx-1');
  assert.equal(submissions, 1);
});

test('an explicitly invalid proof cannot poison a later valid encoding of the same intent', async () => {
  const submitted = [];
  const coordinator = createSubmissionCoordinator({
    prepare: (bytes) => ({ value: bytes[0], idempotencyKey: 'same-intent' }),
    submitPrepared: async ({ value }, lifecycle) => {
      submitted.push(value);
      lifecycle.setSubmissionRetry(async () => 'must-not-retry-invalid-proof');
      if (value === 1) {
        throw {
          _tag: 'Wallet.SubmissionWalletError',
          cause: { _tag: 'SubmissionError', cause: { _tag: 'TransactionInvalidError' } },
        };
      }
      return 'valid-proof-accepted';
    },
  });
  await assert.rejects(coordinator.submit(Buffer.of(1, 1)));
  assert.equal(await coordinator.submit(Buffer.of(2, 2)), 'valid-proof-accepted');
  assert.deepEqual(submitted, [1, 2]);
});

test('alternate bytes cannot replace an ambiguous submission of the same intent', async () => {
  let retries = 0;
  const coordinator = createSubmissionCoordinator({
    prepare: (bytes) => ({ value: bytes[0], idempotencyKey: 'same-intent' }),
    submitPrepared: async (_prepared, lifecycle) => {
      lifecycle.setSubmissionRetry(async () => { retries += 1; return 'accepted-exact-retry'; });
      throw new Error('transport outcome unknown');
    },
  });
  await assert.rejects(coordinator.submit(Buffer.of(3, 1)), /unknown/);
  await assert.rejects(
    coordinator.submit(Buffer.of(3, 2)),
    (error) => error instanceof RelayRequestError && error.code === 'submission_uncertain',
  );
  assert.equal(retries, 0);
  assert.equal(await coordinator.submit(Buffer.of(3, 1)), 'accepted-exact-retry');
  assert.equal(retries, 1);
});

test('submission rejection classifier follows nested Midnight tags and RPC 1010', () => {
  assert.equal(submissionWasExplicitlyRejected({
    _tag: 'Wallet.SubmissionWalletError',
    cause: { _tag: 'SubmissionError', cause: { _tag: 'TransactionInvalidError' } },
  }), true);
  assert.equal(submissionWasExplicitlyRejected({ _tag: 'SubmissionError', cause: { code: 1010 } }), true);
  assert.equal(submissionWasExplicitlyRejected({ _tag: 'TransactionProgressError' }), false);
  assert.equal(submissionWasExplicitlyRejected({ _tag: 'ConnectionError' }), false);
  assert.equal(submissionWasExplicitlyRejected({ _tag: 'TransactionUsurpedError' }), false);
});

test('failed submissions are evicted and the serialized queue recovers', async () => {
  let attempts = 0;
  const coordinator = createSubmissionCoordinator({
    prepare: (bytes) => bytes[0],
    submitPrepared: async () => {
      attempts += 1;
      if (attempts === 1) throw new Error('rejected');
      return 'accepted';
    },
  });
  await assert.rejects(coordinator.submit(Buffer.of(9)), /rejected/);
  assert.equal(await coordinator.submit(Buffer.of(9)), 'accepted');
  assert.equal(attempts, 2);
});

test('an ambiguous submission retries the same finalized operation without preparing again', async () => {
  let attempts = 0;
  let preparations = 0;
  const coordinator = createSubmissionCoordinator({
    prepare: (bytes) => { preparations += 1; return bytes[0]; },
    submitPrepared: async (_value, lifecycle) => {
      attempts += 1;
      lifecycle.setSubmissionRetry(async () => {
        attempts += 1;
        return 'accepted-on-retry';
      });
      throw new Error('ambiguous transport failure');
    },
  });
  await assert.rejects(coordinator.submit(Buffer.of(3)), /ambiguous/);
  assert.equal(await coordinator.submit(Buffer.of(3)), 'accepted-on-retry');
  assert.equal(attempts, 2);
  assert.equal(preparations, 1);
  assert.equal(coordinator.cacheSize(), 1);
});

test('an ambiguous wallet result freezes already queued work until exact retry resolves', async () => {
  const submitted = [];
  const coordinator = createSubmissionCoordinator({
    prepare: (bytes) => bytes[0],
    submitPrepared: async (value, lifecycle) => {
      submitted.push(value);
      if (value === 1) {
        lifecycle.setSubmissionRetry(async () => 'first-accepted-on-retry');
        throw new Error('first outcome unknown');
      }
      return 'second-must-not-run';
    },
  });
  const first = coordinator.submit(Buffer.of(1));
  const alreadyQueued = coordinator.submit(Buffer.of(2));
  await assert.rejects(first, /unknown/);
  await assert.rejects(
    alreadyQueued,
    (error) => error instanceof RelayRequestError && error.code === 'submission_uncertain',
  );
  assert.deepEqual(submitted, [1]);
  assert.equal(await coordinator.submit(Buffer.of(1)), 'first-accepted-on-retry');
  assert.equal(await coordinator.submit(Buffer.of(2)), 'second-must-not-run');
  assert.deepEqual(submitted, [1, 2]);
});

test('an exhausted ambiguous tombstone fails closed until expiry', async () => {
  let clock = 100;
  let secondCalls = 0;
  const coordinator = createSubmissionCoordinator({
    now: () => clock,
    cacheMilliseconds: 10,
    maximumSubmitAttempts: 1,
    prepare: (bytes) => bytes[0],
    submitPrepared: async (value, lifecycle) => {
      if (value === 1) {
        lifecycle.setSubmissionRetry(async () => 'retry-disabled');
        throw new Error('unknown and exhausted');
      }
      secondCalls += 1;
      return 'second-accepted';
    },
  });
  await assert.rejects(coordinator.submit(Buffer.of(1)), /exhausted/);
  await assert.rejects(
    coordinator.submit(Buffer.of(2)),
    (error) => error instanceof RelayRequestError && error.code === 'submission_uncertain',
  );
  assert.equal(secondCalls, 0);
  clock += 11;
  assert.equal(await coordinator.submit(Buffer.of(2)), 'second-accepted');
  assert.equal(secondCalls, 1);
});

test('prepare failures zero the caller buffer and never enter the wallet queue', async () => {
  let submitted = false;
  const coordinator = createSubmissionCoordinator({
    prepare: () => { throw new RelayPolicyError('bad'); },
    submitPrepared: async () => { submitted = true; },
  });
  const bytes = Buffer.from([5, 6, 7]);
  await assert.rejects(coordinator.submit(bytes), RelayPolicyError);
  assert.deepEqual(bytes, Buffer.alloc(3));
  assert.equal(submitted, false);
});

test('asynchronous preparation is rejected and its input is zeroed', async () => {
  const coordinator = createSubmissionCoordinator({
    prepare: async () => ({}),
    submitPrepared: async () => 'never',
  });
  const bytes = Buffer.from([8, 9]);
  await assert.rejects(coordinator.submit(bytes), /asynchronous_prepare_not_allowed/);
  assert.deepEqual(bytes, Buffer.alloc(2));
});

test('completed idempotency entries expire on the configured clock', async () => {
  let clock = 100;
  let calls = 0;
  const coordinator = createSubmissionCoordinator({
    now: () => clock,
    cacheMilliseconds: 10,
    prepare: (bytes) => bytes[0],
    submitPrepared: async (value) => { calls += 1; return `tx-${value}-${calls}`; },
  });
  assert.equal(await coordinator.submit(Buffer.of(4)), 'tx-4-1');
  assert.equal(await coordinator.submit(Buffer.of(4)), 'tx-4-1');
  clock = 111;
  assert.equal(await coordinator.submit(Buffer.of(4)), 'tx-4-2');
  assert.equal(calls, 2);
});

test('active submission work is bounded independently of the completed cache', async () => {
  let release;
  const blocked = new Promise((resolve) => { release = resolve; });
  const coordinator = createSubmissionCoordinator({
    maximumEntries: 4,
    maximumActiveEntries: 1,
    prepare: (bytes) => bytes[0],
    submitPrepared: async (value) => { await blocked; return `tx-${value}`; },
  });
  const first = coordinator.submit(Buffer.of(1));
  await assert.rejects(
    coordinator.submit(Buffer.of(2)),
    (error) => error instanceof RelayRequestError && error.code === 'relay_busy',
  );
  release();
  assert.equal(await first, 'tx-1');
});

test('completed intent tombstones hold capacity until their safety window expires', async () => {
  let clock = 100;
  let calls = 0;
  const coordinator = createSubmissionCoordinator({
    maximumEntries: 1,
    maximumActiveEntries: 1,
    now: () => clock,
    cacheMilliseconds: 10,
    prepare: (bytes) => bytes[0],
    submitPrepared: async (value) => { calls += 1; return `tx-${value}`; },
  });
  assert.equal(await coordinator.submit(Buffer.of(1)), 'tx-1');
  await assert.rejects(
    coordinator.submit(Buffer.of(2)),
    (error) => error instanceof RelayRequestError && error.code === 'relay_busy',
  );
  clock += 11;
  assert.equal(await coordinator.submit(Buffer.of(2)), 'tx-2');
  assert.equal(calls, 2);
  assert.equal(coordinator.cacheSize(), 1);
});

test('confirmation scans values without needing the private member key', () => {
  const commitment = Buffer.alloc(32, 7);
  const seals = [
    [Buffer.alloc(32, 1), Buffer.alloc(32, 2)],
    [Buffer.alloc(32, 3), commitment],
  ];
  assert.equal(stateContainsCommitment(seals, commitment.toString('hex')), true);
  assert.equal(stateContainsCommitment(seals, Buffer.alloc(32, 8).toString('hex')), false);
});

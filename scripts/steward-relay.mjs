#!/usr/bin/env node

// Trusted undeployed-network steward for Slip's device-generated sealPick call.
//
// The incoming proved/pre-binding transaction is sensitive wallet-handoff data,
// not a public network payload. Never log or cache its bytes. This developer relay
// is deliberately limited to one configured contract, one guaranteed sealPick call,
// DUST-only balancing, and an authenticated loopback/LAN boundary.

import { createHash, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, '..');
const e2eRoot = path.join(repositoryRoot, 'contracts', 'e2e');
const moduleRoot = path.join(e2eRoot, 'node_modules');
const linkedBuildRoot = path.join(e2eRoot, 'slip-build');
const canonicalBuildRoot = path.join(repositoryRoot, 'contracts', 'build');

export const DEFAULT_RELAY_PORT = 8_787;
export const MAX_BODY_BYTES = 64 * 1_024;
export const MAX_SEAL_TTL_SECONDS = 3_600;
export const MAX_CACHED_SUBMISSIONS = 1_024;
export const MAX_ACTIVE_SUBMISSIONS = 8;
export const MAX_SUBMISSIONS_PER_MINUTE = 12;
export const MAX_TRANSACTION_ID_CHARACTERS = 512;
export const SUBMISSION_CACHE_MILLISECONDS = (MAX_SEAL_TTL_SECONDS + 5 * 60) * 1_000;
export const READ_TIMEOUT_MILLISECONDS = 10_000;

const LOCAL_NETWORK = Object.freeze({
  walletNetworkId: 'undeployed',
  networkId: 'undeployed',
  indexer: 'http://localhost:8088/api/v4/graphql',
  indexerWS: 'ws://localhost:8088/api/v4/graphql/ws',
  node: 'http://localhost:9944',
  nodeWS: 'ws://localhost:9944',
  proofServer: 'http://localhost:6300',
  faucet: '',
});
const GENESIS_SEED = '0000000000000000000000000000000000000000000000000000000000000001';
const EFFECT_FIELDS = Object.freeze([
  'claimedNullifiers',
  'claimedShieldedReceives',
  'claimedShieldedSpends',
  'claimedContractCalls',
  'shieldedMints',
  'unshieldedMints',
  'unshieldedInputs',
  'unshieldedOutputs',
  'claimedUnshieldedSpends',
]);

export class RelayRequestError extends Error {
  constructor(status, code) {
    super(code);
    this.name = 'RelayRequestError';
    this.status = status;
    this.code = code;
  }
}

export class RelayPolicyError extends Error {
  constructor(code) {
    super(code);
    this.name = 'RelayPolicyError';
    this.code = code;
  }
}

const requestError = (status, code) => { throw new RelayRequestError(status, code); };
const policyError = (code) => { throw new RelayPolicyError(code); };
const moduleURL = (...components) => pathToFileURL(path.join(moduleRoot, ...components)).href;
const bytesEqual = (left, right) => {
  if (!ArrayBuffer.isView(left) || !ArrayBuffer.isView(right) || left.byteLength !== right.byteLength) {
    return false;
  }
  const leftBytes = new Uint8Array(left.buffer, left.byteOffset, left.byteLength);
  const rightBytes = new Uint8Array(right.buffer, right.byteOffset, right.byteLength);
  for (let index = 0; index < leftBytes.length; index += 1) {
    if (leftBytes[index] !== rightBytes[index]) return false;
  }
  return true;
};

export function normalizeHex(value, bytes, label = 'hex') {
  if (typeof value !== 'string' || !new RegExp(`^[0-9a-fA-F]{${bytes * 2}}$`).test(value)) {
    throw new Error(`${label} must be exactly ${bytes} bytes of hex`);
  }
  return value.toLowerCase();
}

export function isLoopbackHost(host) {
  return host === '127.0.0.1' || host === '::1' || host === 'localhost';
}

export function loadRelayConfiguration(environment = process.env) {
  const host = environment.SLIP_RELAY_HOST || '127.0.0.1';
  const allowLAN = environment.SLIP_RELAY_ALLOW_LAN === '1';
  if (!isLoopbackHost(host) && !allowLAN) {
    throw new Error('non-loopback relay binding requires SLIP_RELAY_ALLOW_LAN=1');
  }
  const token = environment.SLIP_RELAY_TOKEN;
  if (typeof token !== 'string' || !/^[0-9a-fA-F]{64}$/.test(token)) {
    throw new Error('SLIP_RELAY_TOKEN must be exactly 32 random bytes encoded as 64 hex characters');
  }
  const address = normalizeHex(environment.SLIP_CONTRACT_ADDRESS, 32, 'SLIP_CONTRACT_ADDRESS');
  const portText = environment.SLIP_RELAY_PORT || String(DEFAULT_RELAY_PORT);
  if (!/^\d+$/.test(portText)) throw new Error('SLIP_RELAY_PORT must be an integer');
  const port = Number(portText);
  if (!Number.isSafeInteger(port) || port < 1 || port > 65_535) {
    throw new Error('SLIP_RELAY_PORT must be between 1 and 65535');
  }
  return Object.freeze({
    host,
    port,
    token,
    contractAddress: address,
    network: LOCAL_NETWORK,
    maxBodyBytes: MAX_BODY_BYTES,
    maxTTLSeconds: MAX_SEAL_TTL_SECONDS,
  });
}

function tokenDigest(token) {
  return createHash('sha256').update(token, 'utf8').digest();
}

export function requestIsAuthorized(authorization, expectedToken) {
  const supplied = typeof authorization === 'string' && authorization.startsWith('Bearer ')
    ? authorization.slice('Bearer '.length)
    : '';
  return timingSafeEqual(tokenDigest(supplied), tokenDigest(expectedToken));
}

function sendJSON(response, status, payload, extraHeaders = {}) {
  const body = Buffer.from(JSON.stringify(payload));
  response.writeHead(status, {
    'cache-control': 'no-store',
    'content-type': 'application/json; charset=utf-8',
    'content-length': String(body.length),
    ...extraHeaders,
  });
  response.end(body);
}

function pathMatch(pathname, prefix, bytes) {
  const match = pathname.match(new RegExp(`^/${prefix}/([0-9a-fA-F]{${bytes * 2}})$`));
  return match?.[1]?.toLowerCase();
}

async function readBoundedBody(request, maximumBytes) {
  const declared = request.headers['content-length'];
  if (declared !== undefined) {
    if (!/^\d+$/.test(declared)) requestError(400, 'invalid_content_length');
    if (Number(declared) > maximumBytes) requestError(413, 'payload_too_large');
  }
  return new Promise((resolve, reject) => {
    let total = 0;
    let settled = false;
    const chunks = [];
    request.on('data', (chunk) => {
      if (settled) {
        chunk.fill(0);
        return;
      }
      total += chunk.length;
      if (total > maximumBytes) {
        settled = true;
        for (const prior of chunks) prior.fill(0);
        chunks.length = 0;
        chunk.fill(0);
        reject(new RelayRequestError(413, 'payload_too_large'));
        return;
      }
      chunks.push(chunk);
    });
    request.on('end', () => {
      if (!settled) {
        const body = Buffer.concat(chunks, total);
        for (const chunk of chunks) chunk.fill(0);
        chunks.length = 0;
        resolve(body);
      }
    });
    request.on('error', () => {
      if (!settled) {
        settled = true;
        for (const chunk of chunks) chunk.fill(0);
        chunks.length = 0;
        reject(new RelayRequestError(400, 'invalid_request'));
      }
    });
  });
}

function routeFor(request) {
  let url;
  try {
    url = new URL(request.url, 'http://relay.invalid');
  } catch {
    requestError(400, 'invalid_request');
  }
  if (url.search) requestError(400, 'query_not_allowed');
  if (url.pathname === '/health') return { kind: 'health', methods: ['GET'] };
  if (url.pathname === '/submit') return { kind: 'submit', methods: ['POST'] };
  const contextAddress = pathMatch(url.pathname, 'context', 32);
  if (contextAddress) return { kind: 'context', methods: ['GET'], value: contextAddress };
  const commitment = pathMatch(url.pathname, 'confirm', 32);
  if (commitment) return { kind: 'confirm', methods: ['GET'], value: commitment };
  return { kind: 'missing', methods: [] };
}

export function createRelayServer({
  configuration,
  getContext,
  submit,
  confirm,
  logger = {},
  now = Date.now,
  maximumSubmissionsPerMinute = MAX_SUBMISSIONS_PER_MINUTE,
}) {
  if (!configuration?.token || !configuration?.contractAddress) {
    throw new Error('relay configuration is incomplete');
  }
  if (!Number.isSafeInteger(maximumSubmissionsPerMinute) || maximumSubmissionsPerMinute < 1) {
    throw new Error('maximumSubmissionsPerMinute must be a positive integer');
  }
  let submissionWindowStartedAt = now();
  let submissionsInWindow = 0;
  const admitSubmission = () => {
    const currentTime = now();
    if (currentTime - submissionWindowStartedAt >= 60_000) {
      submissionWindowStartedAt = currentTime;
      submissionsInWindow = 0;
    }
    if (submissionsInWindow >= maximumSubmissionsPerMinute) {
      requestError(429, 'rate_limited');
    }
    submissionsInWindow += 1;
  };

  const handler = async (request, response) => {
    let activeRoute;
    try {
      const route = routeFor(request);
      activeRoute = route;
      if (route.kind === 'missing') requestError(404, 'not_found');
      if (!route.methods.includes(request.method)) {
        requestError(405, 'method_not_allowed');
      }
      if (route.kind === 'health') {
        sendJSON(response, 200, { status: 'ok' });
        return;
      }
      if (!requestIsAuthorized(request.headers.authorization, configuration.token)) {
        requestError(401, 'unauthorized');
      }
      if (route.kind === 'context') {
        if (route.value !== configuration.contractAddress) requestError(404, 'contract_not_found');
        const context = await getContext(route.value);
        const address = normalizeHex(context?.address, 32, 'context address');
        if (address !== configuration.contractAddress) throw new Error('context provider returned another contract');
        if (!(context.state instanceof Uint8Array) || context.state.length === 0) {
          throw new Error('context provider returned invalid state');
        }
        if (!Number.isSafeInteger(context.blockTimeSecs) || context.blockTimeSecs < 0) {
          throw new Error('context provider returned invalid block time');
        }
        sendJSON(response, 200, {
          address,
          stateHex: Buffer.from(context.state).toString('hex'),
          blockTimeSecs: context.blockTimeSecs,
        });
        return;
      }
      if (route.kind === 'submit') {
        if ((request.headers['content-type'] || '').trim().toLowerCase() !== 'application/octet-stream') {
          requestError(415, 'unsupported_media_type');
        }
        admitSubmission();
        const body = await readBoundedBody(request, configuration.maxBodyBytes ?? MAX_BODY_BYTES);
        if (body.length === 0) requestError(400, 'empty_payload');
        const txId = await submit(body);
        if (typeof txId !== 'string' || txId.length === 0
            || txId.length > MAX_TRANSACTION_ID_CHARACTERS) {
          throw new Error('submitter returned invalid transaction id');
        }
        sendJSON(response, 200, { txId });
        return;
      }
      const status = await confirm(route.value);
      if (!['pending', 'confirmed', 'rejected'].includes(status)) {
        throw new Error('confirmer returned invalid status');
      }
      sendJSON(response, 200, { status });
    } catch (error) {
      if (!request.readableEnded) request.resume();
      if (response.headersSent) {
        response.end();
        return;
      }
      if (error instanceof RelayRequestError) {
        const headers = error.status === 405 ? { allow: activeRoute?.methods.join(', ') ?? '' } : {};
        sendJSON(response, error.status, { error: error.code }, headers);
        return;
      }
      if (error instanceof RelayPolicyError) {
        sendJSON(response, 400, { error: 'transaction_rejected' });
        return;
      }
      logger.error?.('relay_request_failed');
      sendJSON(response, 500, { error: 'internal_error' });
    }
  };

  const server = createServer({
    maxHeaderSize: 16 * 1_024,
    requestTimeout: 15_000,
    headersTimeout: 10_000,
    keepAliveTimeout: 5_000,
  }, handler);
  server.maxHeadersCount = 64;
  server.maxRequestsPerSocket = 100;
  server.on('clientError', (_error, socket) => {
    if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
  });
  return server;
}

function collectionSize(value) {
  if (Array.isArray(value) || ArrayBuffer.isView(value)) return value.length;
  if (value instanceof Map || value instanceof Set) return value.size;
  if (value && Number.isSafeInteger(value.size) && value.size >= 0) return value.size;
  return undefined;
}

function assertEmptyCollection(value, code) {
  if (collectionSize(value) !== 0) policyError(code);
}

function entryPointText(value) {
  if (typeof value === 'string') return value;
  if (!ArrayBuffer.isView(value)) policyError('invalid_entry_point');
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(value);
  } catch {
    policyError('invalid_entry_point');
  }
}

export function inspectSealPickTransaction(transaction, { ContractCall, contractAddress }) {
  if (transaction?.rewards !== undefined) policyError('rewards_not_allowed');
  if (transaction?.guaranteedOffer !== undefined) policyError('guaranteed_offer_not_allowed');
  if (transaction?.fallibleOffer !== undefined) policyError('fallible_offer_not_allowed');
  if (!(transaction?.intents instanceof Map) || transaction.intents.size !== 1) {
    policyError('exactly_one_intent_required');
  }
  const [[segment, intent]] = transaction.intents;
  if (!Number.isSafeInteger(segment) || segment <= 0 || segment > 65_535) {
    policyError('invalid_segment');
  }
  if (intent?.guaranteedUnshieldedOffer !== undefined) policyError('unshielded_offer_not_allowed');
  if (intent?.fallibleUnshieldedOffer !== undefined) policyError('unshielded_offer_not_allowed');
  if (intent?.dustActions !== undefined) policyError('preexisting_dust_not_allowed');
  if (!Array.isArray(intent?.actions) || intent.actions.length !== 1) {
    policyError('exactly_one_action_required');
  }
  const [call] = intent.actions;
  if (!(call instanceof ContractCall)) policyError('contract_call_required');
  let callAddress;
  try {
    callAddress = normalizeHex(call.address, 32, 'call address');
  } catch {
    policyError('wrong_contract');
  }
  if (callAddress !== contractAddress) {
    policyError('wrong_contract');
  }
  if (entryPointText(call.entryPoint) !== 'sealPick') policyError('wrong_entry_point');
  if (call.guaranteedTranscript === undefined) policyError('guaranteed_transcript_required');
  if (call.fallibleTranscript !== undefined) policyError('fallible_transcript_not_allowed');
  const effects = call.guaranteedTranscript.effects;
  if (!effects || typeof effects !== 'object') policyError('effects_required');
  for (const field of EFFECT_FIELDS) assertEmptyCollection(effects[field], `external_effect_${field}`);
  if (!(intent.ttl instanceof Date) || !Number.isFinite(intent.ttl.getTime())) policyError('invalid_ttl');
  let identifiers;
  try {
    identifiers = transaction.identifiers();
  } catch {
    policyError('invalid_transaction_identifier');
  }
  if (!Array.isArray(identifiers) || identifiers.length !== 1
      || typeof identifiers[0] !== 'string' || !/^[0-9a-fA-F]{66}$/.test(identifiers[0])) {
    policyError('invalid_transaction_identifier');
  }
  return Object.freeze({
    transaction,
    ttl: new Date(intent.ttl.getTime()),
    idempotencyKey: identifiers[0].toLowerCase(),
  });
}

export function assertRelayTTL(ttl, blockTimeSecs, maximumTTLSeconds = MAX_SEAL_TTL_SECONDS) {
  if (!(ttl instanceof Date) || !Number.isFinite(ttl.getTime())) policyError('invalid_ttl');
  if (!Number.isSafeInteger(blockTimeSecs) || blockTimeSecs < 0) policyError('invalid_block_time');
  const ttlMillis = ttl.getTime();
  const blockMillis = blockTimeSecs * 1_000;
  if (ttlMillis <= blockMillis) policyError('expired_ttl');
  if (ttlMillis > blockMillis + maximumTTLSeconds * 1_000) policyError('ttl_too_far');
}

export function deserializeCanonicalTransaction(bytes, Transaction, maximumBytes = MAX_BODY_BYTES) {
  if (!(bytes instanceof Uint8Array) || bytes.length === 0 || bytes.length > maximumBytes) {
    policyError('invalid_transaction_size');
  }
  let transaction;
  try {
    transaction = Transaction.deserialize('signature', 'proof', 'pre-binding', bytes);
  } catch {
    policyError('invalid_transaction_encoding');
  }
  let canonical;
  try {
    canonical = transaction.serialize();
  } catch {
    policyError('invalid_transaction_encoding');
  }
  const isCanonical = bytesEqual(bytes, canonical);
  canonical.fill(0);
  if (!isCanonical) policyError('noncanonical_transaction');
  return transaction;
}

export function createSubmissionCoordinator({
  prepare,
  submitPrepared,
  now = Date.now,
  maximumEntries = MAX_CACHED_SUBMISSIONS,
  maximumActiveEntries = MAX_ACTIVE_SUBMISSIONS,
  cacheMilliseconds = SUBMISSION_CACHE_MILLISECONDS,
  maximumSubmitAttempts = 3,
}) {
  const entries = new Map();
  let walletTail = Promise.resolve();

  const prune = () => {
    const cutoff = now() - cacheMilliseconds;
    for (const [key, entry] of entries) {
      if (entry.completedAt !== undefined && entry.completedAt <= cutoff) entries.delete(key);
    }
  };

  const enqueue = (task) => {
    const result = walletTail.then(task, task);
    walletTail = result.catch(() => undefined);
    return result;
  };

  const isUncertain = (entry) => ['retryable', 'retrying', 'exhausted'].includes(entry.state);
  const hasUncertainEntry = (except) => [...entries.values()].some(
    (entry) => entry !== except && isUncertain(entry),
  );

  const reuse = (key, entry) => {
    if (entry.state === 'retryable') {
      entry.state = 'retrying';
      entry.attempts += 1;
      entry.promise = enqueue(async () => {
        try {
          const txId = await entry.retry();
          entry.retry = undefined;
          entry.state = 'success';
          entry.completedAt = now();
          return txId;
        } catch (error) {
          entry.completedAt = now();
          if (submissionWasExplicitlyRejected(error)) {
            entry.retry = undefined;
            entries.delete(key);
          } else if (entry.attempts < maximumSubmitAttempts) {
            entry.state = 'retryable';
          } else {
            entry.retry = undefined;
            entry.state = 'exhausted';
          }
          throw error;
        }
      });
    }
    return entry.promise;
  };

  return Object.freeze({
    async submit(bytes) {
      if (!(bytes instanceof Uint8Array)) policyError('invalid_transaction_size');
      const digest = createHash('sha256').update(bytes).digest('hex');
      prune();
      const existing = entries.get(digest);
      if (existing) {
        bytes.fill(0);
        return reuse(digest, existing);
      }
      if (hasUncertainEntry()) {
        bytes.fill(0);
        throw new RelayRequestError(409, 'submission_uncertain');
      }

      let prepared;
      try {
        prepared = prepare(bytes);
        if (prepared && typeof prepared.then === 'function') {
          policyError('asynchronous_prepare_not_allowed');
        }
      } finally {
        bytes.fill(0);
      }
      if (prepared?.idempotencyKey !== undefined) {
        const semanticExisting = [...entries.entries()].find(
          ([, entry]) => entry.idempotencyKey === prepared.idempotencyKey,
        );
        if (semanticExisting) {
          const [semanticKey, semanticEntry] = semanticExisting;
          if (['pending', 'success'].includes(semanticEntry.state)) {
            return reuse(semanticKey, semanticEntry);
          }
          throw new RelayRequestError(409, 'submission_uncertain');
        }
      }
      const activeEntries = [...entries.values()].filter(
        (entry) => ['pending', 'retryable', 'retrying'].includes(entry.state),
      ).length;
      if (activeEntries >= maximumActiveEntries) {
        throw new RelayRequestError(503, 'relay_busy');
      }
      if (entries.size >= maximumEntries) throw new RelayRequestError(503, 'relay_busy');

      const entry = {
        promise: undefined,
        completedAt: undefined,
        prepared,
        retry: undefined,
        state: 'pending',
        attempts: 1,
        idempotencyKey: prepared?.idempotencyKey,
      };
      entries.set(digest, entry);
      entry.promise = enqueue(async () => {
        if (hasUncertainEntry(entry)) {
          entry.prepared = undefined;
          entries.delete(digest);
          throw new RelayRequestError(409, 'submission_uncertain');
        }
        try {
          const txId = await submitPrepared(entry.prepared, {
            setSubmissionRetry: (retry) => {
              if (typeof retry !== 'function') policyError('invalid_submission_retry');
              entry.retry = retry;
            },
          });
          entry.prepared = undefined;
          entry.retry = undefined;
          entry.state = 'success';
          entry.completedAt = now();
          return txId;
        } catch (error) {
          entry.prepared = undefined;
          if (entry.retry && !submissionWasExplicitlyRejected(error)) {
            // Retry only the identical finalized transaction. Never rebalance an
            // ambiguous submission or let another job contend for its booked DUST.
            if (entry.attempts < maximumSubmitAttempts) {
              entry.state = 'retryable';
            } else {
              entry.retry = undefined;
              entry.state = 'exhausted';
            }
            entry.completedAt = now();
          } else {
            entry.retry = undefined;
            entries.delete(digest);
          }
          throw error;
        }
      });
      return entry.promise;
    },
    drain: () => walletTail,
    cacheSize: () => entries.size,
  });
}

export function submissionWasExplicitlyRejected(error) {
  const seen = new Set();
  let current = error;
  for (let depth = 0; depth < 12 && current && typeof current === 'object'; depth += 1) {
    if (seen.has(current)) break;
    seen.add(current);
    if (current._tag === 'TransactionInvalidError') {
      return true;
    }
    // Substrate's explicit transaction-pool rejection envelope. Midnight's inner
    // Custom error identifies the ledger validation failure, but no payload is logged.
    if (current.code === 1010 || current.code === '1010') return true;
    current = current.cause;
  }
  return false;
}

export async function withReadTimeout(operation, milliseconds = READ_TIMEOUT_MILLISECONDS) {
  let timeout;
  try {
    return await Promise.race([
      operation,
      new Promise((_, reject) => {
        timeout = setTimeout(() => reject(new Error('public read timed out')), milliseconds);
        timeout.unref?.();
      }),
    ]);
  } finally {
    clearTimeout(timeout);
  }
}

export async function queryLatestBlock(
  indexerURL,
  fetchImplementation = fetch,
  timeoutMilliseconds = READ_TIMEOUT_MILLISECONDS,
) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMilliseconds);
  timeout.unref?.();
  let payload;
  try {
    const response = await fetchImplementation(indexerURL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ query: '{ block { height hash timestamp } }' }),
      signal: controller.signal,
    });
    if (!response.ok) throw new Error('indexer block query failed');
    payload = await response.json();
  } catch {
    throw new Error('indexer block query failed');
  } finally {
    clearTimeout(timeout);
  }
  const block = payload?.data?.block;
  if (payload?.errors || !block || !/^[0-9a-f]{64}$/i.test(block.hash)
      || !Number.isSafeInteger(block.timestamp) || block.timestamp <= 1_000_000_000_000) {
    throw new Error('indexer returned invalid block context');
  }
  return Object.freeze({
    height: block.height,
    hash: block.hash.toLowerCase(),
    seconds: Math.floor(block.timestamp / 1_000),
  });
}

/// The indexer's block-pinned contract-state lookup answers only for blocks that CONTAIN an
/// action of that contract; pinning to the chain head returns null once the head has moved
/// past the contract's last action (verified against the local indexer, 2026-09-05). The
/// state as of the contract's latest action IS its current state, so pin to that block and
/// report the chain head's time as the device's tblock.
export async function queryLatestContractActionBlock(
  indexerURL,
  address,
  fetchImplementation = fetch,
  timeoutMilliseconds = READ_TIMEOUT_MILLISECONDS,
) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMilliseconds);
  timeout.unref?.();
  let payload;
  try {
    const response = await fetchImplementation(indexerURL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ query: `{ contractAction(address: "${address}") { transaction { block { height hash timestamp } } } }` }),
      signal: controller.signal,
    });
    if (!response.ok) throw new Error('indexer contract action query failed');
    payload = await response.json();
  } catch {
    throw new Error('indexer contract action query failed');
  } finally {
    clearTimeout(timeout);
  }
  const block = payload?.data?.contractAction?.transaction?.block;
  if (!block || typeof block.hash !== 'string' || !/^[0-9a-f]{64}$/.test(block.hash)) {
    throw new Error('contract has no indexed action');
  }
  return Object.freeze({ height: block.height, hash: block.hash });
}

export async function fetchContractContext({
  address,
  indexerURL,
  publicDataProvider,
  latestBlock = queryLatestBlock,
  latestActionBlock = queryLatestContractActionBlock,
}) {
  const block = await latestBlock(indexerURL);
  const actionBlock = await latestActionBlock(indexerURL, address);
  const state = await withReadTimeout(publicDataProvider.queryContractState(address, {
    type: 'blockHash',
    blockHash: actionBlock.hash,
  }));
  if (!state) throw new Error('contract state unavailable');
  return Object.freeze({
    address,
    state: Buffer.from(state.serialize()),
    blockTimeSecs: block.seconds,
  });
}

export async function balanceSignFinalizeSubmit({
  wallet,
  zswap,
  dust,
  keystore,
  transaction,
  ttl,
  setSubmissionRetry = () => {},
}) {
  const recipe = await wallet.balanceUnboundTransaction(
    transaction,
    { shieldedSecretKeys: zswap, dustSecretKey: dust },
    { ttl, tokenKindsToBalance: ['dust'] },
  );
  let finalized;
  try {
    const signed = await wallet.signRecipe(recipe, (payload) => keystore.signData(payload));
    finalized = await wallet.finalizeRecipe(signed);
  } catch (error) {
    try {
      await wallet.revert(recipe);
    } catch (revertError) {
      throw new AggregateError([error, revertError], 'wallet preparation and rollback failed');
    }
    throw error;
  }
  // The facade's submitTransaction hard-codes a Finalized wait. Finalization above
  // already booked this transaction and its DUST; the pending service independently
  // reconciles the indexed outcome after this Submitted event lets HTTP return.
  // Ambiguous errors before observing Submitted retain that booking for exact retry.
  // Only explicit node rejection proves it is safe to release the finalized transaction.
  let txId;
  try {
    txId = finalized.identifiers().at(-1);
    if (typeof txId !== 'string' || txId.length === 0
        || txId.length > MAX_TRANSACTION_ID_CHARACTERS) {
      throw new Error('finalized transaction has no valid identifier');
    }
  } catch (error) {
    try {
      await wallet.revert(finalized);
    } catch (revertError) {
      throw new AggregateError([error, revertError], 'wallet identifier and rollback failed');
    }
    throw error;
  }
  const submitFinalized = async () => {
    try {
      await wallet.submissionService.submitTransaction(finalized, 'Submitted');
      return txId;
    } catch (error) {
      if (submissionWasExplicitlyRejected(error)) {
        try {
          await wallet.revert(finalized);
        } catch (revertError) {
          throw new AggregateError([error, revertError], 'wallet submission and rollback failed');
        }
      }
      throw error;
    }
  };
  setSubmissionRetry(submitFinalized);
  return submitFinalized();
}

export function stateContainsCommitment(seals, commitmentHex) {
  const expected = Buffer.from(normalizeHex(commitmentHex, 32, 'commitment'), 'hex');
  if (!seals || typeof seals[Symbol.iterator] !== 'function') {
    throw new Error('contract seals map is not iterable');
  }
  for (const entry of seals) {
    if (Array.isArray(entry) && entry.length === 2 && bytesEqual(entry[1], expected)) return true;
  }
  return false;
}

async function waitForWalletSync(wallet) {
  await new Promise((resolve, reject) => {
    let subscription;
    let settled = false;
    let timeout;
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      queueMicrotask(() => subscription?.unsubscribe());
      callback(value);
    };
    timeout = setTimeout(() => finish(reject, new Error('wallet sync timed out')), 60_000);
    subscription = wallet.state().subscribe({
      next: (state) => {
        if (state.isSynced) finish(resolve);
      },
      error: () => finish(reject, new Error('wallet sync failed')),
      complete: () => {
        if (!settled) finish(reject, new Error('wallet sync ended before synchronization'));
      },
    });
  });
}

async function relativeFiles(root, relative = '') {
  const entries = await readdir(path.join(root, relative), { withFileTypes: true });
  const nested = await Promise.all(entries.map((entry) => {
    const child = path.join(relative, entry.name);
    return entry.isDirectory() ? relativeFiles(root, child) : [child];
  }));
  return nested.flat().sort();
}

async function verifyBuildMirror() {
  // The relay needs only generated public contract code. Never enumerate or read
  // top-level build scratch files: a local proving run may have left private
  // preimages/proofData there, and those are outside this process boundary.
  const [canonicalFiles, linkedFiles] = await Promise.all([
    relativeFiles(path.join(canonicalBuildRoot, 'contract')),
    relativeFiles(path.join(linkedBuildRoot, 'contract')),
  ]);
  if (canonicalFiles.join('\n') !== linkedFiles.join('\n')) {
    throw new Error('contracts/e2e/slip-build is stale');
  }
  for (const relative of canonicalFiles) {
    const [canonical, linked] = await Promise.all([
      readFile(path.join(canonicalBuildRoot, 'contract', relative)),
      readFile(path.join(linkedBuildRoot, 'contract', relative)),
    ]);
    if (!canonical.equals(linked)) throw new Error('contracts/e2e/slip-build is stale');
  }
}

export async function createStewardRuntime(configuration) {
  await verifyBuildMirror();
  const [
    { indexerPublicDataProvider },
    { setNetworkId },
    { ContractCall, DustSecretKey, LedgerParameters, Transaction, ZswapSecretKeys },
    { FluentWalletBuilder },
    { ledger },
  ] = await Promise.all([
    import(moduleURL('@midnight-ntwrk', 'midnight-js-indexer-public-data-provider', 'dist', 'index.mjs')),
    import(moduleURL('@midnight-ntwrk', 'midnight-js-network-id', 'dist', 'index.mjs')),
    import(moduleURL('@midnight-ntwrk', 'midnight-js-protocol', 'dist', 'ledger.mjs')),
    import(moduleURL('@midnight-ntwrk', 'testkit-js', 'dist', 'index.mjs')),
    import(pathToFileURL(path.join(linkedBuildRoot, 'contract', 'index.js')).href),
  ]);
  setNetworkId('undeployed');
  const built = await FluentWalletBuilder.forEnvironment(configuration.network)
    .withDustOptions({
      ledgerParams: LedgerParameters.initialParameters(),
      additionalFeeOverhead: 1_000n,
      feeBlocksMargin: 5,
    })
    .withSeed(GENESIS_SEED)
    .buildWithoutStarting();
  const { wallet, seeds, keystore } = built;
  const zswap = ZswapSecretKeys.fromSeed(seeds.shielded);
  const dust = DustSecretKey.fromSeed(seeds.dust);
  try {
    await wallet.start(zswap, dust);
    await waitForWalletSync(wallet);
  } catch (error) {
    try { await wallet.stop(); } catch { /* preserve the startup error */ }
    throw error;
  }

  try {
    const publicDataProvider = indexerPublicDataProvider(
      configuration.network.indexer,
      configuration.network.indexerWS,
    );
    const coordinator = createSubmissionCoordinator({
      prepare: (bytes) => inspectSealPickTransaction(
        deserializeCanonicalTransaction(bytes, Transaction, configuration.maxBodyBytes),
        { ContractCall, contractAddress: configuration.contractAddress },
      ),
      submitPrepared: async ({ transaction, ttl }, lifecycle) => {
        const block = await queryLatestBlock(configuration.network.indexer);
        assertRelayTTL(ttl, block.seconds, configuration.maxTTLSeconds);
        return balanceSignFinalizeSubmit({
          wallet,
          zswap,
          dust,
          keystore,
          transaction,
          ttl,
          setSubmissionRetry: lifecycle.setSubmissionRetry,
        });
      },
    });

    return Object.freeze({
      async getContext(address) {
        if (address !== configuration.contractAddress) throw new Error('wrong contract');
        return fetchContractContext({
          address,
          indexerURL: configuration.network.indexer,
          publicDataProvider,
        });
      },
      submit: (bytes) => coordinator.submit(bytes),
      async confirm(commitmentHex) {
        const state = await withReadTimeout(
          publicDataProvider.queryContractState(configuration.contractAddress),
        );
        if (!state) throw new Error('contract state unavailable');
        return stateContainsCommitment(ledger(state.data).seals, commitmentHex) ? 'confirmed' : 'pending';
      },
      drain: () => coordinator.drain(),
      async stop() {
        await coordinator.drain();
        await wallet.stop();
      },
    });
  } catch (error) {
    try { await wallet.stop(); } catch { /* preserve the construction error */ }
    throw error;
  }
}

async function listen(server, port, host) {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.off('error', reject);
      resolve();
    });
  });
}

async function close(server) {
  if (!server.listening) return;
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
}

export async function main() {
  const configuration = loadRelayConfiguration();
  const runtime = await createStewardRuntime(configuration);
  let server;
  try {
    server = createRelayServer({
      configuration,
      getContext: runtime.getContext,
      submit: runtime.submit,
      confirm: runtime.confirm,
      logger: { error: (event) => console.error(`steward-relay: ${event}`) },
    });
    await listen(server, configuration.port, configuration.host);
    console.log(`steward-relay: listening on http://${configuration.host}:${configuration.port}`);
    console.log(`steward-relay: contract ${configuration.contractAddress} (undeployed, DUST-only)`);

    await new Promise((resolve) => {
      process.once('SIGINT', resolve);
      process.once('SIGTERM', resolve);
    });
  } finally {
    let closeFailure;
    try {
      if (server) await close(server);
    } catch (error) {
      closeFailure = error;
    }
    try {
      await runtime.stop();
    } catch (error) {
      if (closeFailure) throw new AggregateError([closeFailure, error], 'relay cleanup failed');
      throw error;
    }
    if (closeFailure) throw closeFailure;
  }
  console.log('steward-relay: stopped');
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) {
  main().catch(() => {
    console.error('steward-relay: initialization failed');
    process.exitCode = 1;
  });
}

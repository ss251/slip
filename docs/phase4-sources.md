# Local round: sources and verification

Consulted 2026-09-05. Official documentation is consulted through Midnight's kapa
MCP, not substituted with model recall. The compiler and executable tests decide
version-specific behavior. Nothing here implies network submission or acceptance.

## Kapa queries

Q3 (verbatim main query, followed by six single-topic queries):

> Compact language 0.23.0 compiler 0.31.1 compact-runtime 0.16.0: witness callback arguments and [privateState, result] return order; CircuitResults.context threading and ProofData publicTranscript Op[] mixed string/object operations; commitment reveal recompute and assertion mismatch rejection; caller-supplied block time for local tests versus network acceptance.

Q4 (verbatim relevant queries):

- Does the midnight-zk or midnight-ledger CachedResolver require the exact bls_midnight_2p{k} SRS parameter file for each circuit's k, or can a larger installed bls_midnight_2p14 file serve k=12 and k=13 circuits automatically?
- Is the serialized ProofData produced by the compact-runtime sufficient on its own to generate a zero-knowledge proof after the JavaScript context that created it is discarded?
- Are circuit arguments in Compact private by default until they cross a public disclosure boundary via disclose()?

Actual `mcp__midnight__search_midnight_knowledge_sources` calls and responses were
inspected. Reproduce from this repository with the existing authenticated Claude
connection (ToolSearch must remain available for deferred MCP tools):

```sh
claude -p 'Use ToolSearch to load mcp__midnight__search_midnight_knowledge_sources, then ask: <query>. Do not substitute another source.' \
  --allowedTools 'mcp__midnight__search_midnight_knowledge_sources' \
  --strict-mcp-config \
  --mcp-config '{"mcpServers":{"midnight":{"type":"http","url":"https://midnight.mcp.kapa.ai"}}}'
```

## Official evidence and limits

- Witnesses receive context first and return `[updatedPrivateState, value]`.
  [Compact reference](https://docs.midnight.network/compact/reference/compact-reference#exports-of-the-generated-typescript-code).
- Circuit calls return updated context and data for proving. The app keeps runtime
  proof input private; it is not proof bytes.
  [JavaScript runtime guide](https://docs.midnight.network/guides/compact-javascript-runtime#calling-circuits-from-javascript),
  [ProofData](https://docs.midnight.network/api-reference/compact-runtime/interfaces/ProofData).
- `publicTranscript` contains both string and object operations, not only objects.
  [Op union](https://docs.midnight.network/api-reference/compact-runtime/type-aliases/Op).
- Reveal recomputes a commitment and asserts equality. New commitments require
  fresh randomness; opening an existing commitment requires its original opening.
  [Cryptographic primitives](https://docs.midnight.network/compact/smart-contract-security#cryptographic-primitives).
- Local tests supply block time; a local proof is not a submitted, included, or
  network-verified round. The demo advances its sample clock, not the real deadline.
  [Deadline tests](https://docs.midnight.network/guides/security-best-practices#enforcing-a-deadline).
- The prover requests the key's exact `k`; no automatic larger-file fallback.
  [Ledger-8 proving](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/zkir/src/ir.rs#L110-L203),
  [parameter provider and checksums](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/base-crypto/src/data_provider.rs#L79-L198).
- Arguments are private by default until a public boundary. Community skill prose
  claiming all circuit arguments are automatically public is not authoritative.
  [Explicit disclosure](https://docs.midnight.network/compact/reference/compact-reference#explicit-disclosure).

Version caveat: live runtime API pages include 0.19-era `callContext` and async
codegen. Slip uses installed 0.16.0 declarations and compiler 0.31.1 output instead.
No explicit documentation guarantees JavaScriptCore lifetime independence or
rollback isolation of a reused native query context. Recreating the synchronous
runtime and replaying accepted steps avoids relying on the latter; actual
execute-then-prove tests must establish the former for this build.

## Skills consulted

Midnight Expert (`compact-core` 0.12.0):

- `compact-witness-ts/SKILL.md` and its runtime, witness-implementation and type-mapping references.
- `compact-language-ref/SKILL.md`.
- `compact-transaction-model/SKILL.md`.
- `compact-privacy-disclosure/SKILL.md`, disclosure mechanics and privacy patterns.

Midnight Expert (`midnight-verify` 0.14.0): `verify-by-execution`,
`verify-witness`, and `verify-correctness`. Verification is by local execution;
this is not a claim that the Claude-only verification agents ran.

MIDSKILLS: `.agents/skills/SOURCE.md` LOCAL DELTA first, then `midnightskill`,
`compact`, and `midnight-security`. Examples targeting language 0.22 are hints,
not replacements for this repository's 0.23 contract.

## Repository referee

- `contracts/slip.compact`: exact arguments, witness names, disclosure sites and assertions.
- `contracts/test/slip.test.mjs`: lifecycle, phase bounds, flipped reveal, settlement,
  dispute eligibility, public tallies and distinct no-result/disputed sentinels.
- `contracts/test/export-preimage.mjs`: exact 0.16 runtime context and serialization.
- `MidnightKit/Tests/MidnightKitTests/ContractRuntimeTests.swift`: existing on-device
  execution parity with Node and native proof generation.

Read-only compiler check: 0.31.1; emitted runtime 0.16.0; temporary-directory
`--skip-zk` compilation succeeded. Node suite: `84 passed, 0 failed`.
Compiler `zkir mock-compile` reports k13 for enrollMember/createSlip/settle/dispute,
k14 for sealPick/reveal. Existing local parameter files match official SHA-256:

```text
bls_midnight_2p13 d3324910969c4cc54143b8045b649e5c3a4bd5fb7b8f85fe1b770f640ce1c803
bls_midnight_2p14 fc253016885ec830e97808c9ec920bb5cab5c21af590380a6cb5eb0538e2b244
```

`scripts/prepare-app-params.sh` stages only these public files in ignored app build
storage. It has no network fallback and does not alter contracts or MidnightKit.

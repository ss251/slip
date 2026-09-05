# Architecture

## System shape

```
iPhone (SwiftUI app)
 ├─ Slip UI  ── tokens/design system, no color/type literals
 ├─ MidnightKit (Swift + Rust staticlib)
 │    ├─ witness store   {choice, salt} — encrypted, device-only
 │    ├─ prover          Compact circuits proved ON DEVICE (no proof server)
 │    └─ params/keys     fetched on demand + cached (k≈10 needs ~200KB BLS params)
 └─ network prototype ── fetches public context; hands a proved/pre-binding seal
                         to an authenticated trusted developer relay

Trusted local steward relay
 ├─ strict sealPick-only policy ── adds DUST, signs and finalizes
 └─ chain/indexer ── submits the finalized transaction; confirms public state

Midnight network (dev: `undeployed` local trio)
 └─ slip.compact — ONE contract: rounds, commitments, deadline, reveals, scores
```

The defining decision: **Slip proves in-process on the phone.** State the reason precisely, because the sloppy version is wrong and a judge will catch it:

- Proving genuinely requires the witness in the clear. Official docs: *"the proof server performs arithmetic directly over those values, so whichever proof server does the proving receives them in the clear... It is a trust boundary."*
- **But a locally-run proof server is already private** — the docs call `localhost:6300` "the safe default", and 1AM already proves in-browser via WASM. On-device proving is not unprecedented, and desktop DApps are not leaking by default. Do not claim otherwise.
- **The gap is mobile.** You cannot run the Docker proof server on an iPhone, so a mobile Midnight app's realistic options are a *remote* proof server that sees every witness, or proving in-process. Slip does the latter.

So the honest claim is: *on iOS*, a sealed pick never leaves the device, and that is architecturally true rather than policy-true. Scope it to mobile and it holds; generalise it to "everyone else leaks" and it is false.

## Contract interface (target shape — keep circuits few and small)

- `createSlip(question_commit, deadline, crew_root)` — steward opens a round.
- `sealPick(round, commitment)` — commitment = binding+hiding commit over `{choice, salt}`; one per member per round (nullifier prevents double-seal).
- `reveal(round, choice, salt)` — accepted only after deadline AND only if it re-derives the stored commitment.
- `settle(round, outcome)` — steward-only; scores computed from verified reveals.

Constraints that shape this design:
- **Single contract.** Cross-contract calls exist in Compact 0.33.0+ but **not on any
  network we can reach**. Midnight DevRel (Jay Albert), 2026-08-31: *"0.34.0 is not
  currently supported by our networks. So it's a bit ahead of its time but we are
  steadily working towards making contract to contract calls available to everyone."*
  We build on 0.31.1, where the feature does not exist. We were never using it —
  verified: no `crossContractCall`, no contract types, no contract-typed ledger
  fields — and would not want to: a circuit reachable by a cross-contract call
  cannot call witnesses, and ours must.
- Circuit size stays small (k≈10 class) → proving in ~100ms-class on device and tiny params. Don't add circuit complexity without re-checking `midnightkit.md` budgets.
- Public ledger state is public: question commitment, seal commitments, reveal results, scores. Sides are hidden **until reveal, then public to the crew and chain** — that's the product contract, don't accidentally promise more.

## Crew membership & invites (v1)

Invite link carries the contract address + round id (+ crew secret for membership proof if enabled). Rendezvous is the chain itself; the app polls the indexer for roster/reveal state. **Caveat: "no backend" no longer survives contact with fees.** Every circuit call costs DUST, and DUST sponsorship — the mechanism that lets a member transact holding nothing — requires a sponsor *wallet*, which the protocol will not let a contract be (*"Smart contracts do not hold or spend DUST"*). **Decided: DUST redesignation, no sponsor service.** See below. Push/notifications come later and must not require witness-adjacent data.

## How members pay for transactions

Every circuit call costs DUST and the protocol will not let a contract hold any
(*"Smart contracts do not hold or spend DUST"*), so someone funds the crew. Two
mechanisms exist; we take the second.

**Rejected — sponsor service.** A backend holds NIGHT and attaches a DUST fee
offer to each member's already-bound transaction (`balanceFinalizedTransaction`
with `tokenKindsToBalance: ['dust']`). Members hold nothing and one sponsor
address serves unlimited members, because the sponsor spends its *own* DUST
rather than delegating any. It is the documented pattern with a reference
implementation — though see the caveat below: that reference does not currently
run on our toolchain. Rejected because it is a server: hosting, uptime during judging,
and a party who can decline to relay — a bad shape for an app whose claim is that
no one can interfere with a sealed pick. Its real ceiling is capacity, not
addressing: DUST refills toward ~5 per NIGHT over roughly a week, so a busy
sponsor runs dry.

**Chosen — DUST generation redesignation.** The steward points DUST generation at
each member's own DUST address via
`registerNightUtxosForDustGeneration(utxos, vk, sign, receiverDustAddress)`.
Members then pay their own fees while never holding NIGHT.

Measured on the local devnet (`scripts/measure-redesignation.ts`): a wallet
holding **zero NIGHT and zero DUST had spendable DUST 18.8s** after the steward
registered — 15.8s to submit, ~3s to appear. That cost lands at *enrollment*, not
at seal time, which is what makes this viable.

Three implementation traps, each found by hitting it:

1. **Registration is scoped to a Night ADDRESS, not a UTXO.** The ledger holds
   `address_delegation: Map<NightAddress, DustPublicKey>` — one address maps to
   exactly one DUST key. Respending NIGHT at a registered address yields
   *already-registered* UTXOs. Consequence: **the steward needs one Night address
   per member**, derived from the HD path `m/44'/2400'/account'/role/index`,
   each funded and registered separately at crew setup. Redesignating from a
   single address would redirect the steward's own generation away from itself.
2. **Redesignation must be explicitly DUST-balanced** before finalizing
   (`balanceUnprovenTransaction(..., tokenKindsToBalance: ['dust'])`). Plain
   self-registration self-funds from retroactive DUST; pointing generation at a
   third party does not. Skipping this gives `Malformed(BalanceCheckOverspend)`.
3. **Do not sign twice.** `registerNightUtxosForDustGeneration` already signs via
   its `signDustRegistration` callback; a following `signRecipe` produces
   `Malformed(InputsSignaturesLengthMismatch)`.

**Proven at crew scale** (`scripts/measure-n-members.ts`, local devnet): one
steward funded 3 sub-addresses, each designating a different member. All three
members — each starting with zero NIGHT and zero DUST — had spendable DUST at
**54.2s**, and the steward's own generation was untouched.

The finding that matters: **3/3 registrations were self-funded from retroactive
DUST.** Each sub-address held `DUST = 0` at registration and still paid its own
fee, so the bootstrap problem does not exist in practice — *the steward needs
NIGHT and never needs DUST*. Budget roughly 35s per member, sequential (~18s to
fund, ~17s to register); parallelisable, and one-time at crew setup.

**Still untested on `preview`/`preprod`,** where funding comes from a
human-facing faucet page with no programmatic drip, and B needs N funded
addresses rather than one. That, not latency, is the remaining risk that could
push us back to a sponsor service.

## Toolchain: we build on the stack the networks run

We briefly built on Compact 0.34.0 / ledger 9 and came back. The deciding input was
Midnight DevRel, 2026-08-31: *"0.34.0 is not currently supported by our networks."*

| | stable (ours) | ledger 9 (abandoned) |
|---|---|---|
| compiler / language | **0.31.1 / 0.23.0** | 0.34.0 / 0.26.0 |
| compact-runtime | **0.16.0** | 0.19.0 |
| midnight-js | **4.1.1** | 5.0.0-beta |
| node | **1.x** (`spec_version` 1_000_000) | 2.x (2_000_000) |
| deployable to preview/preprod/mainnet | **yes** | no |

Building ahead of the networks cost nothing at compile time and everything at deploy
time: a 0.34.0 contract has no public network to run on, and the matching DApp SDK is
a release candidate. `midnight-js` 4.1.1 hard-pins `compact-runtime` 0.16.0, so the
two stacks cannot be mixed — that pin is the mechanism, not an accident.

**What the move back cost:** a one-line pragma change (0.26 -> 0.23; the contract used
no 0.26-only features), a test-harness port (`createCircuitContext` has a different
signature and `currentQueryContext` sits directly on the context rather than under
`callContext`), and the e2e workspace moving to the 4.1.1 line. Prover keys grew
21 MB -> 22 MB. All 84 assertions still pass, and deploy+call still works.

**What it bought:** a contract that can actually be deployed to preview/preprod when
we want to, rather than only to a local release-candidate node.

Judge our own earlier reasoning honestly: staying on 0.34.0 was defensible while the
only evidence was that the kickoff scopes the buildathon to `undeployed` — but
"nothing forces us off it" is a weaker argument than "the vendor says the networks do
not support it", and we should have weighted the compatibility matrix more heavily
than the absence of a hard blocker.

## Stakes and offramping

**Stakes are a contract-minted token with no offramp, by design.** Not a
limitation we are working around — the exit does not exist: the Cardano bridge is
**one-way at mainnet launch** (*"there will not be, by mainnet launch, a
protocol-level bridging mechanism... from Midnight to Cardano"*), and DUST can
never be a stake (non-transferable, decays, *"cannot store value"* — deliberately,
for regulatory reasons). So value landing on Midnight has no sanctioned route out
regardless of what we build.

Every cryptographic property, the escrow, the sealed pot and the claim flow work
identically with a valueless token; what changes is that nothing converts to
money, which keeps Slip a game rather than a licensed betting operator. Real
money is a post-mainnet, licensed-entity conversation — pooled wagering with
payout is gambling plus money transmission in most jurisdictions, and App Store
real-money gaming requires per-territory licensed entities.

## Round lifecycle — four phases

```
..< sealDeadline                   SEAL     members seal picks
[sealDeadline, revealDeadline)     REVEAL   members open picks (24h) — opens the
                                            INSTANT sealing closes
[revealDeadline, settleDeadline)   SETTLE   steward records the outcome (12h)
[.., disputeDeadline)              DISPUTE  any member who sealed may void a
                                            wrong outcome (12h past settle close)
>= disputeDeadline                 CLOSED   next createSlip() may clear the round
```

Window lengths are **dials**; what matters is their sum, because
`sealDeadline -> disputeDeadline` is how long a crew waits before starting the
next slip. The defaults total 48h, leaving a weekly crew five clear days. A crew
playing daily should shorten all three.

### The security model: challengeable, not blind

The threat is **the steward lying about a fact the whole crew can verify**. The
defence is that any single member who sealed can veto the recorded outcome —
everybody can see whether it rained, so one honest participant suffices and no
quorum, stake, or tie-break is needed. Eligibility is *sealed*, not *revealed*: a
member who missed the reveal window can still see the outcome is wrong, and
requiring a reveal would disenfranchise exactly the people least able to keep up.

Disputes are attributable (`disputedBy` is written to the ledger) — the crew sees
who challenged and judges them for it. That visibility is most of what keeps it
honest.

**Rejected alternative — the blind settle window.** An earlier revision put
`settle` *between* sealing and revealing so the steward fixed the outcome before
seeing any pick. It was removed as **unsatisfiable, not unsafe**: for the steward
to settle honestly the outcome must be known during their window, but sealing
must close before the outcome becomes knowable, and the gap between the two is
the duration of the real-world event — which varies per question and which the
contract cannot know. "Will the home team win tonight?" seals at kickoff and
resolves three hours later; the blind window expires mid-game and the round can
never be settled. Most natural friend-crew questions would end permanently
unsettled. It also cost the shared open-together moment, and it only ever stopped
a steward targeting a *rival* — they always know their own pick, so it never
stopped self-favouring. Challengeability protects the centre of the threat model
instead of a corner of it.

### Accepted weaknesses (known, not oversights)

- **Dispute griefing.** A member can void a *correct* outcome by disputing it.
  Accepted: it is visible, attributable, equal-opportunity (anyone who sealed can
  do it, including against a griefer's own round), and it destroys the round for
  them too. Judged strictly better than a steward-only void, where one privileged
  party holds the same power unilaterally and unaccountably.
- **Settle griefing.** A steward who sees they are going to lose can simply not
  settle. Weaker than choosing the outcome — it cannot manufacture a win — and
  equally visible (`status == open`, `outcome == 2` after the window closed).
- **Wave 1 voids rather than re-settles.** One dispute ends it. Allowing a
  re-settle would let a dishonest steward re-post the same lie until the dispute
  window ran out. The Wave 2 path is escalation to majority attestation among
  members who sealed — same eligibility set, a real result instead of a hole, and
  the steward demoted from author to proposer.

A round can end three ways, and they are deliberately distinguishable from ledger
state alone:

| ending | `status` | `outcome` |
|---|---|---|
| settled, unchallenged | `settled` | `0` / `1` |
| settled, then disputed | `disputed` | `3` |
| steward never settled | `open` | `2` |

`outcome` never defaults to `0`, which a client reading the field alone would
misread as a real "No".

## Wave 2 — recorded, not yet addressed

Findings from design review that are out of scope for Wave 1 (unitless, points
only) but become load-bearing the moment stakes exist:

- **Steward key recovery.** `stewardAuth` is set once in the constructor and can
  never be changed, so a lost or wiped steward device means the crew can never
  open another slip on that contract. Tolerable while a slip is worth bragging
  rights; unacceptable once anything of value can be locked behind it. Needs a
  rotation or social-recovery path before stakes.
- **Sybil surface in enrollment.** The steward alone decides who is in the crew,
  and nothing bounds or attests the roster. Unexamined while Wave 1 is unitless
  and crews are real-life friend groups; once points or value matter, a steward
  can enroll confederates to swing a scoreboard or a dispute. Needs an
  invite-attestation or member-approval scheme before points count for anything.

## Disclosure ledger

### Experimental native seal relay (September 2026)

The optional undeployed-network path separates private execution/proving on the phone
from fee payment by a trusted local steward. `NetworkSealingService` receives from the
relay only the configured contract address plus a tagged public `ContractState` and its block time,
then executes `sealPick`, derives the ledger binding while assembling the call, and
proves it in process. The `{choice, salt}`, device secret, private runtime transcript
and `proofData` never cross that boundary. A planted 32-byte control verifies that the
device-secret pattern is absent from the 5,238-byte handoff.

What crosses from the app boundary is the proved/pre-binding `sealPick` transaction:
the zero-knowledge proof, public call transcript/commitment and ledger binding material
needed by the wallet. This is sensitive wallet-handoff data even though it contains no
witness. The authenticated developer relay deserializes it, admits exactly one
guaranteed effect-free `sealPick` call to one configured contract, adds only DUST,
signs/finalizes with the undeployed genesis wallet and submits the finalized
transaction to the node. Its confirmation endpoint reads only current public contract
state through the indexer. The relay never receives the private runtime `proofData`,
and neither request bodies, proof bytes, tokens, keys nor internal errors are logged or
echoed.

Every work endpoint requires a fresh 32-byte bearer token. The server binds loopback by
default; non-loopback binding needs an explicit opt-in and plain HTTP is limited to a
trusted local LAN/Tailscale developer demo—never public Wi-Fi, port forwarding or
production. The relay is a trusted wallet boundary, not trustless DUST sponsorship.
Only the finalized transaction crosses from that boundary to the node. The host
tooling proof service may prove setup calls and the steward wallet's separate DUST
transaction; it never proves Slip's native `sealPick` call.

Evidence remains deliberately split. A physical iPhone component test assembled and
proved against embedded post-create state, but used a stub relay with no HTTP, wallet,
node or indexer. Separately, `scripts/phase7-live-relay-demo.mjs` exercised the real
authenticated HTTP steward against the undeployed node and required `SucceedEntirely`
plus exact indexed commitment equality, but its producer was the host. The current
Swift HTTP client still needs the required bearer-token wiring before one run can prove
the combined physical-iPhone → relay → devnet path. Sources and limits:
`docs/phase6-sources.md` and `docs/phase7-sources.md`.

### App-only local proving demonstration (September 2026)

The default SwiftUI local demonstration does not invoke the experimental chain path
described above or an encrypted witness store. Each new local draft gets an immutable
UUID, question, ordered side labels, crew name, creation time and sealing deadline. A domain-separated,
length-prefixed canonical encoding of that public metadata is SHA-256 hashed and
passed as `createSlip`'s question commitment in an in-memory `ContractRuntime`.
No contract address or crew state is fetched from a network.

`LocalSealingService` owns execute → prove in an actor. The device secret, choice,
runtime proof-input JSON and private display snapshot stay in process memory;
none are logged, written to disk, exported or submitted. Salt remains derived
inside the existing circuit. Only the proof bytes, public commitment, round ID,
question commitment and real execution/key-load/prove durations form the public
receipt. A separate private display snapshot prevents a later draft edit from
relabeling an already-sealed pick. Results are cached by immutable local round
identity, not by a global one-shot flag.

The presentation model owns its task. Departing the active flow or inactivating
the scene invalidates late UI completion; native proving may finish and be cached by the actor, but
cannot navigate a departed screen. This is session-only: terminating the app loses
the witness, so that session cannot be revealed after relaunch. Preview rosters and results are
synthetic. In this mode the steward wallet, submission and indexer are not invoked;
the experimental seal-only boundary above is separate. Persistent witness storage and
verified network reveal remain unimplemented.

The same actor now proves all six steps: enroll → create → seal → reveal → settle
→ optional dispute. It retains the original device secret, choice, steward secret
and seal-time metadata for this session. Reveal accepts only a round ID, never a
new pick; the existing circuit derives the original salt and verifies the opening.
Each operation uses a fresh synchronous runtime to replay its accepted prefix,
then proves only the new step. Private proof-input JSON crosses the app's in-memory
execute/prove boundary; no JavaScript object crosses an actor suspension. Failed
execution is discarded rather than assuming native context rollback.

Accepted public ledger fields (opening, tallies, outcome, disputer identity) drive
the local reveal/verdict/standings views. These are deliberately public **after**
the relevant circuit succeeds and is proved; raw native errors remain sanitized.
The sample advances caller-supplied execution time to each legal window, not the
device clock, and never submits a proof. Per-step receipts expose only circuit name,
preparation/key/proving durations and byte count. Debug screenshot fixtures are
clearly labelled, synthetic, and execute no circuits; flags cannot carry witnesses.
Sources and exact mirrored Node tests: `docs/phase4-sources.md`.

Everything that intentionally becomes public, in one place. Update this list with every `disclose()`:

| What | When | Why |
|---|---|---|
| Seal commitment | on seal | binds the pick without revealing it |
| memberId (H(device secret)) | on enroll, seal, reveal | roster + "3 of 5 sealed" progress; identifies the member, not their pick |
| Question commitment | on createSlip | pins the off-chain question text so it can't be reworded after picks are sealed |
| Seal / reveal / settle / dispute deadlines | on createSlip | the crew must see when each phase opens and closes |
| Choice | on reveal (the instant sealing closes) | the whole point — verified against the seal |
| Outcome | on settle (after reveals close) | shared result the crew is scored against |
| Disputer's memberId | on dispute | a challenge must be attributable — that visibility is what deters a frivolous one |

**The salt is never disclosed, ever.** It used to be a host-supplied witness
(`localPickSalt()`); it is now derived in-circuit as
`H("slip:picksalt:v1" || round || deviceSecret)`, so it never crosses the FFI
boundary, never needs storing, and cannot be reused across members or rounds.
Hiding therefore rests on the same device-secret entropy that identity already
rests on. Scores are not stored on-chain at all — every input to them is public,
so clients compute the scoreboard deterministically from ledger state.

## Local development

`undeployed` is the target, not a stepping stone — the kickoff scopes the buildathon
to it explicitly (*"I highly encourage you to stick to undeployed... you can do all of
that without waiting for network syncs, without having to deal with faucets"*). Judges do not verify a testnet address, so a local demo is sufficient — but we build
on the supported stack anyway, so preview/preprod stay open to us.

Bring it up with `npm run devnet:up` (contracts/) — `infra/devnet-compose.yml`. Node
`ws://localhost:9944`, indexer `http://localhost:8088/api/v4/graphql`, proof server
`http://localhost:6300`. The proof server is for tooling/CLI parity only; the app path
must never depend on it.

**The node version is load-bearing.** Our contract is ledger 8 (Compact 0.31.1), so the
devnet must be midnight-node **1.x**. Mixing lines fails as "Failed to decode ledger
event payload" with no mention of a version, so `freshness-gate.sh` derives the
expected ledger from the compiler's runtime version and checks the running node
against it (0.16.x -> ledger 8, 0.19.x -> ledger 9).

**Proven on-chain** (`npm run test:network`, 2026-08-31): deployed at
`f081477a…3fed04f` in 21.8s, `createSlip` returned `SucceedEntirely` in 17.3s, ledger
advanced `status 0 -> 1` with `sealDeadline` written. A real proof was generated and
verified by the network, so the contract is no longer compiler-and-simulator only.

Because we build on the supported stack, the same artifacts target preview/preprod
when we want a publicly verifiable deployment.

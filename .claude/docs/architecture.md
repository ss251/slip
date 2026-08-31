# Architecture

## System shape

```
iPhone (SwiftUI app)
 ├─ Slip UI  ── tokens/design system, no color/type literals
 ├─ MidnightKit (Swift + Rust staticlib)
 │    ├─ witness store   {choice, salt} — encrypted, device-only
 │    ├─ prover          Compact circuits proved ON DEVICE (no proof server)
 │    └─ params/keys     fetched on demand + cached (k≈10 needs ~200KB BLS params)
 └─ chain client ── submits {commitment, proof}; reads contract state via indexer

Midnight network (dev: `undeployed` local trio)
 └─ slip.compact — ONE contract: rounds, commitments, deadline, reveals, scores
```

The defining decision: **standard Midnight apps delegate proving to a proof server, which necessarily receives witness data. Slip's prover runs on the phone**, so the privacy claim ("nobody can see a sealed pick") is architecturally true, not policy-true.

## Contract interface (target shape — keep circuits few and small)

- `createSlip(question_commit, deadline, crew_root)` — steward opens a round.
- `sealPick(round, commitment)` — commitment = binding+hiding commit over `{choice, salt}`; one per member per round (nullifier prevents double-seal).
- `reveal(round, choice, salt)` — accepted only after deadline AND only if it re-derives the stored commitment.
- `settle(round, outcome)` — steward-only; scores computed from verified reveals.

Constraints that shape this design:
- **No contract-to-contract calls on the network yet** → everything above lives in one contract.
- Circuit size stays small (k≈10 class) → proving in ~100ms-class on device and tiny params. Don't add circuit complexity without re-checking `midnightkit.md` budgets.
- Public ledger state is public: question commitment, seal commitments, reveal results, scores. Sides are hidden **until reveal, then public to the crew and chain** — that's the product contract, don't accidentally promise more.

## Crew membership & invites (v1)

Invite link carries the contract address + round id (+ crew secret for membership proof if enabled). No backend service in v1: rendezvous is the chain itself; the app polls the indexer for roster/reveal state. Push/notifications come later and must not require witness-adjacent data.

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

`undeployed` network via midnight-local-dev: node `ws://localhost:9944`, indexer `http://localhost:8088/api/v4/graphql`, proof server `http://localhost:6300`. The proof server exists for tooling/CLI parity only — the app path must never depend on it. Preprod/testnet deploys are a milestone step, not the daily loop.

# Product

## The one-liner

Sealed predictions with friends: a pick is committed on the player’s phone, and a valid opening proves it matches that seal. The proof does not establish that a pick was never copied or seen on an unlocked phone. The current app demonstrates a single-player local round; the connected crew experience below is the product direction.

## Who it's for

A crew: 3–8 friends who already banter — group chats, offices, fantasy leagues. The intended connected flow lets one person create a slip and invite friends. Today, an invite imports public metadata only. The steward must enrol each member before the round opens; a link does not grant membership or bind its text to chain state. Connected play requires relay, node and indexer infrastructure; the local single-player demo keeps its proofs on device.

## Intended connected loop (not the current local demo)

1. **Create** — a question ("Will it rain on Saturday?"), two sides, a reveal time, a crew.
2. **Seal** — each player picks a side privately; the phone generates a proof and posts only a commitment. Sealing feels physical: hold-to-seal, a stamp, a haptic.
3. **The quiet wait** — roster shows who's sealed (never *what*); nudges for stragglers; deadline locks the round.
4. **Open together** — the deadline starts an opening window; participants open their own picks and each reveal is checked against its seal; the verdict lands ("It rained."), winners take points, losers take banter.
5. **Standings** — weekly crown, season tally, straight into the next slip.

## Product laws

- **The reveal is the peak.** Build anticipation around the opening window. Do not promise simultaneous arrivals: the current contract publishes each accepted opening separately.
- **Losing is banter, not failure.** Losses render muted/strikethrough — never red, never shameful.
- **Sealed is a feeling.** The commit action gets weight (hold gesture, stamp animation, heavy haptic); the ticket screen makes the seal a keepable artifact.
- **Zero crypto vocabulary in the UI.** "Sealed", "proof", "opened together" — never "zk", "witness", "commitment hash" in user-facing copy (mono receipt rows may show the hash as a artifact detail).
- **Single-player screens must demo well** — every screen renders meaningfully with one user + placeholder crew, because onboarding starts alone.

## Resolution model (v1)

The slip creator is the named steward: they settle the outcome ("it rained / it didn't") after the reveal time. The contract permits any enrolled member who sealed to dispute a settled outcome before the dispute deadline. One accepted dispute voids the result and publicly records the disputer; judging the real-world outcome remains social. Oracle-based settlement is explicitly out of scope for now (see `roadmap.md`).

## Copy voice

Warm, dry, short. The app narrates like a friend keeping score, not a protocol. Reference strings live with the designs; keep questions in examples mundane and human ("Does the demo survive the all-hands?").

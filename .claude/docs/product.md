# Product

## The one-liner

Every pick'em app promises "picks are hidden until lockout." That promise is enforced by trusting an operator's server. Slip is the version where nobody *can* peek — the pick is sealed cryptographically on the player's own phone, and the reveal proves it was never changed or copied. Hide-until-reveal is a mass-market mechanic (office pools, fantasy pick'em, group polls); Slip makes it trustless and makes the *reveal* the product moment.

## Who it's for

A crew: 3–8 friends who already banter — group chats, offices, fantasy leagues. One person creates a slip; everyone else joins from an invite link. Value must exist with as few as two humans and zero external infrastructure.

## The loop (one round)

1. **Create** — a question ("Will it rain on Saturday?"), two sides, a reveal time, a crew.
2. **Seal** — each player picks a side privately; the phone generates a proof and posts only a commitment. Sealing feels physical: hold-to-seal, a stamp, a haptic.
3. **The quiet wait** — roster shows who's sealed (never *what*); nudges for stragglers; deadline locks the round.
4. **Open together** — all picks reveal simultaneously; each reveal is checked against its seal; the verdict lands ("It rained."), winners take points, losers take banter.
5. **Standings** — weekly crown, season tally, straight into the next slip.

## Product laws

- **The reveal is the peak.** Everything funnels tension into that one simultaneous moment. Never leak partial results early.
- **Losing is banter, not failure.** Losses render muted/strikethrough — never red, never shameful.
- **Sealed is a feeling.** The commit action gets weight (hold gesture, stamp animation, heavy haptic); the ticket screen makes the seal a keepable artifact.
- **Zero crypto vocabulary in the UI.** "Sealed", "proof", "opened together" — never "zk", "witness", "commitment hash" in user-facing copy (mono receipt rows may show the hash as a artifact detail).
- **Single-player screens must demo well** — every screen renders meaningfully with one user + placeholder crew, because onboarding starts alone.

## Resolution model (v1)

The slip creator is the named steward: they settle the outcome ("it rained / it didn't") after the reveal time. Disputes are social, not protocol — the crew can see the steward and the question. Oracle-based settlement is explicitly out of scope for now (see `roadmap.md`).

## Copy voice

Warm, dry, short. The app narrates like a friend keeping score, not a protocol. Reference strings live with the designs; keep questions in examples mundane and human ("Does the demo survive the all-hands?").

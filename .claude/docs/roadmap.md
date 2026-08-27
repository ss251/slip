# Roadmap

Built in the open during Midnight's WaveHack buildathon; waves are our milestone rhythm, but scope decisions follow the product, not the calendar.

## Wave 1 — the playable sealed round (by 2026-09-16)

Ordered so the riskiest thing is proven earliest:

1. `slip.compact` compiles clean + simulator test suite (create/seal/reveal/settle, adversarial + privacy probes). *A compiling contract is the non-negotiable core.*
2. MidnightKit proves `sealPick` and `reveal` **on an iPhone** (simulator, then device) within budget.
3. Two-device happy path on the local network: invite link → both seal → deadline → simultaneous reveal → standings.
4. A real round with 3–4 actual humans, captured as the demo video — real people, real phones, real proofs.
5. Polish + README + TestFlight build.

**Definition of done (W1):** unitless (points only) · single contract · witness never leaves device (probes prove it) · design gate green · e2e round green on `undeployed` · repo public under Apache-2.0 with topics `midnightntwrk`, `compact`.

**Known fallback:** if live reveal proving feels slow in-hand, reveals become async "open at the deadline" (which is arguably truer to the product) — the contract shape already supports it.

## Wave 2 — the crew grows up

- Crews as first-class (recurring slips, season standings), push notifications, share-sheet invites.
- Explore stakes via shielded tokens — **eyes open:** with today's token patterns, contract-held pot *amounts* are publicly visible and payouts are claim-based; ship only if the honest version is still fun. Membership proofs (Merkle crew root) land here too.
- Preprod deployment + faucet flow.

## Wave 3 — polish & keys

- Passkey-derived keys (PRF, iOS 18+) with Keychain fallback; Face ID gating.
- Viewing-key style sharing of a crew's history; App Store submission track (unitless framing keeps this in "social gaming", not real-money gaming; org developer account required for wallet-class features — decide when stakes decide).

## Out of scope (deliberately)

Oracles/automated settlement · public global markets · Android · any feature requiring the witness to leave the device.

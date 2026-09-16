# Design system — "Sealed, native"

Native iOS structure carrying one confident brand accent. The bar is Luma-class quiet craft: white cards on a near-white ground, exact HIG type, tiny meta-icons, per-item art tiles, one accent with one meaning. No poster shadows, no outlined-pill buttons, no crypto-dark theme, no decorative moods. Personality lives in content (crew art, copy, the seal moment), not in chrome.

## Tokens (canonical — mirror into `DesignTokens.swift`, no literals in views)

| Token | Light | Dark | Role |
|---|---|---|---|
| bg | `#F7F7F6` | `#0A0A0A` | ground (grouped) |
| card | `#FFFFFF` | `#1C1C1E` | hero and grouped-card surface |
| fill | `#EFEFED` | `#232326` | secondary buttons, chips, wells |
| separator | `#E8E8E6` | `#2C2C2E` | hairlines (inset 16pt in rows) |
| ink | `#17171A` | `#F2F2F7` | primary label |
| secondary | `#66666E` | `#98989F` | secondary label (AA on all light surfaces) |
| **seal** | `#C63A2B` | same | THE accent — means seal/commit only; white text on it |
| sealText | `#C63A2B` | `#E45D4E` | inline Sealed text only; AA on ground and cards |
| seal-tint | `#FAE8E5` | derive | selected-state tint (ink text on top) |
| win | `#1F7A43` | `#67D08F` | won/verified ONLY |
| ambient | `#5E5560` | — | seal-sheet ground (crew art washed over it; white text) |
| ticket | `#232126` | — | the sealed-ticket surface (the one dark artifact screen) |

Crew identity = gradient art tiles (radial blobs from a per-crew palette) — the only decoration budget. Avatars are neutral (`fill` bg, ink initials).

## Type (system-ui/SF only; HIG default sizes)

Large 34/41·700 — Title2 22/28·700 — Title3 20/25 — Headline 17/22·600 — Body 17/22 — Sub 15/20 — Footnote 13/18 — Caption 12/16 — tab labels 10. Machine truth (hashes, receipts, block numbers) is JetBrains Mono 12/16, never the brand voice.

## Laws

1. **One seal moment** — the accent appears as one big moment per screen (seal button, stamp, primary CTA); tiny seal-dots marking sealed state may repeat. Seal red never means error.
2. **Losing isn't red** — muted ink + strikethrough; banter, not failure.
3. **Machine truth is mono** — and only machine truth.
4. **Native first** — real status bar, home indicator, 44×44pt hit regions (visual can be smaller; hit slop can't), safe areas, Dynamic Type scaling, no edge-to-edge buttons (20pt insets, concentric radii: card 20 / control 14 / round 999 / crest 12).
5. **Hierarchy is spacing** — related 8–12, unrelated 24–32; no divider between things a gap can separate.

## Surfaces & signature moves

- Feed: hero card (full-bleed art banner + floating solid-white chips) above uncarded rows; day-grouped headers ("Today / Wednesday").
- Seal flow: registration-sheet grammar — art-washed ambient ground, grabber, context row, white selected card vs translucent option, seal-red hold action, generous emptiness.
- Sealed ticket: dark `ticket` surface, one giant white card with a dotted-QR of the commitment + art chip, spec rows, white pill.
- Reveal: verdict as Large title, poll-split bars (win green vs faded struck-through), "you" hero card, compact roster.
- **Liquid Glass is chrome only** (iOS 26 `glassEffect`; pre-26 `ultraThinMaterial`): tab bar, floating pills, sheet grabbers — content cards never glass; two glass layers never stack; the seal is never glass; Reduce Transparency → solid fill.

## Motion & haptics

Press = scale 0.97 on pointer-down, 150 ms strong ease-out, no haptic.

**Hold to seal** = 1.2 s linear with visible progress (the seal disc fills); release
before completion cancels in ~200 ms ease-out with no haptic and no state change.
Linear, not eased — a hold is a *timer*, and easing makes remaining time unreadable.
**Never shorten it under Reduce Motion**: it is a safety-timed confirmation, not
decoration. It is the one gesture the product is named after; treat its timing as a
product decision, not a tuning knob.

Seal lands = stamp scale 1.15→1.0 `spring(0.4, bounce 0.2)` + heavy impact (bounce
earned by the gesture's momentum, and 0.2 is the ceiling — above that it reads as a
toy). The rare opening moment (06a) uses a per-row 3D flip, 60 ms stagger capped at 5, `spring(0.5, 0)`, `.success` haptic on your row; **Reduce Motion → crossfade**. The sealed-room roster (05) appears instantly. Sheets `spring(0.45, bounce 0.2)` only after drag-release (button-open = bounce 0), always interruptible. Routine lists/tabs/keyboard actions never animate. Never `easeIn`.

**Accessibility states live in the app, not the pixels.** Reduce Motion → crossfade
(never a blanket `animation: none`, and never shorten the hold). Reduce Transparency
→ solid fill. **Increase Contrast → add borders** to cards, chips and the tab bar.
Dynamic Type scales layout, not just glyphs.

**Shadows get their own token** (`--shadow`), never a reuse of `bg` or a literal —
a shadow whose hex happens to equal today's background is white shadows in dark mode
waiting to happen. Cards carry elevation, so the token exists even though the house
style forbids *poster* shadows. `paper-gate.py` does not inspect shadows; that makes
the token discipline load-bearing rather than optional.

## Visual reference

**Canonical: [docs/design/v6/](../../docs/design/v6/) — thirty boards** (`00-how-slip-works` …
`11e-reveal-mismatch`: 24 routes plus three dark and three accessibility boards).
Produced from the committed [app snapshots](../../SlipTests/Snapshots/) on
**2026-09-05**, after the Luma pass and opening-motion restoration (`b1f2915`).
These are reviewed app renders, losslessly compacted at 1×, not Paper exports.
Board names match v5: plain names copy `-light.png`, `-dark` names copy `-dark.png`,
and `-ax` names copy `-accessibility.png` (AX1, not AX5). Standard boards are
393×852; accessibility boards are 393×1100. Approved UI changes refresh only the
affected snapshots and their matching v6 boards.

**[v5 (Paper)](../../docs/design/v5/) is superseded and kept for diffing.** The owner
will refresh the Paper file later; it does not govern the current app reference.
The public explainer page is [docs/how-slip-works.html](../../docs/how-slip-works.html): static HTML in these tokens, built from the v6 boards.

`docs/design/*.png` (v4, eight boards) is **superseded** — kept only for diffing.
Do not build against it.

**Verify a board before trusting it.** The v4 set sat in git for a week fully
transparent, seven of the eight byte-identical, because a failed export was
committed and never re-opened. Binary assets have no reviewable diff. Open the PNG.

The three ideas the boards encode, so code doesn't quietly drop them:

1. **One object.** The pick card is a single thing in four states — chosen,
   sealing under the disc, the ticket, flipped open. "Sealed" is never a word, a
   colour, and an icon meaning three different things.
2. **Asymmetry is the proof.** You can see your own pick; nobody else's. Other rows
   show only inline Sealed/Waiting status until their picks open. This is why no padlock icon
   appears anywhere in the app — the behaviour states the privacy model.
3. **Open ≠ Verdict.** Picks open at the deadline (sides in ink, no green, no
   winner); the steward records the outcome later (green, points, provenance).
   These are separate screens because they are separate moments.

## Luma pass (2026-09-05)

- **Inline status tags:** Sealed uses an SF Symbol interpolated into the text run; Waiting is plain secondary text. No control-shaped status coins.
- **Who → what → when:** crew identity/status, Headline question, then quiet metadata with regular SF Symbols. Accessibility sizes allow wrapping and stacked layouts.
- **Uncarded feed:** rows sit on the ground with 64pt art tiles and spacing as the separator. The hero and grouped settings/form cards retain their surfaces.
- **Deterministic crew palettes:** UTF-8 DJB2 selects one of ten tokenized triads, excluding seal-red and verdict-green families. The same crew key produces the same art across screens and launches.
- **Art-washed ambient:** crew art uses blur 60, scale 1.3, wash .35, overlay .55 and shade .52. Every rendered palette clears 7:1 for `onTicket` (minimum 7.1197:1). Reduce Transparency keeps the flat ambient fallback (6.3919:1 for `onTicket`).

`sealText` is a scheme-adaptive text pair: **#C63A2B light / #E45D4E dark**.
Only the inline Sealed tag uses it; seal buttons, hold progress and the wax mark
keep `seal`. Measured WCAG ratios for the resolved tokens:

| Appearance | Page background | Card background |
|---|---:|---:|
| Light | 4.847474:1 | 5.196400:1 |
| Dark | 5.632618:1 | 4.840731:1 |

All clear 4.5:1. Sources: [tokens](../../Slip/DesignSystem/DesignTokens.swift),
[status/art components](../../Slip/DesignSystem/Components/SharedViews.swift),
[token contrast and identity tests](../../SlipTests/CrewArtTests.swift), and
[rendered ambient/snapshot tests](../../SlipTests/ScreenSnapshotTests.swift).

## Enforcement

The v6 boards are verified against their mapped committed snapshots: matching
names, dimensions and decoded pixels, with no transparent or missing frames.
**`scripts/paper-gate.py`** checks Paper-authored boards against the live Paper file
(palette, type scale, HIG body length, contrast, tap targets, one-wax-moment, board
hygiene). Run it for Paper edits, including the owner's later refresh; it needs
Paper running at `127.0.0.1:29979`. It does not gate copies of app-rendered v6 snapshots.
**`scripts/design-gate.sh <src-dir>`** runs
the mechanical subset (token discipline, raw font sizes, glass-outside-chrome, missing Reduce Motion guards, sub-44pt tappables, easeIn). Run it on every UI diff; fix causes at the token/system level — exemptions are design debt. Contrast targets: 4.5:1 (<18pt), 3:1 large — verify against the *effective* background, translucent chips get solid backing when text sits on art.


## The mark (2026-09-05)

Slip's mark is a **pressed wax seal**, not a flat disc. A solid seal-red circle on a light
ground reads as the Japanese flag (Hinomaru) — a real tone problem given AkinDo and Midnight
are Japan-based — so the mark carries a scalloped rim, a soft sheen, and a debossed inner
ring, and the app icon sits on the brand's near-black ground (red-on-dark, never red-on-white).
Seal-red (`SlipColor.seal`) stays the one accent; only the SHAPE changed. Implemented as
`SealMark` + `Scallop` in `SharedViews.swift` (used for the 56pt ticket disc; small ≤28pt
status dots stay plain — a dot isn't a flag). Icon source: `AppIcon.appiconset/icon-source.svg`
(wax seal on `#0A0A0A`), rasterized 1024² via `rsvg-convert`. Run through the Emil design
doctrine (design-sauce); upstream emilkowalski/skills verified current at commit d23d7f8.

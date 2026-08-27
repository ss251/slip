# Design system — "Sealed, native"

Native iOS structure carrying one confident brand accent. The bar is Luma-class quiet craft: white cards on a near-white ground, exact HIG type, tiny meta-icons, per-item art tiles, one accent with one meaning. No poster shadows, no outlined-pill buttons, no crypto-dark theme, no decorative moods. Personality lives in content (crew art, copy, the seal moment), not in chrome.

## Tokens (canonical — mirror into `DesignTokens.swift`, no literals in views)

| Token | Light | Dark | Role |
|---|---|---|---|
| bg | `#F7F7F6` | `#0A0A0A` | ground (grouped) |
| card | `#FFFFFF` | `#1C1C1E` | list/card surface |
| fill | `#EFEFED` | `#232326` | secondary buttons, chips, wells |
| separator | `#E8E8E6` | `#2C2C2E` | hairlines (inset 16pt in rows) |
| ink | `#17171A` | `#F2F2F7` | primary label |
| secondary | `#66666E` | `#98989F` | secondary label (AA on all light surfaces) |
| **seal** | `#C63A2B` | same | THE accent — means seal/commit only; white text on it |
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

- Feed: hero card (full-bleed art banner + floating solid-white chips + Title2) above compact rows; day-grouped headers ("Today · Wednesday").
- Seal flow: registration-sheet grammar — ambient ground, grabber, context row, white selected card vs translucent option, floating white pill CTA, generous emptiness.
- Sealed ticket: dark `ticket` surface, one giant white card with a dotted-QR of the commitment + art chip, spec rows, white pill.
- Reveal: verdict as Large title, poll-split bars (win green vs faded struck-through), "you" hero card, compact roster.
- **Liquid Glass is chrome only** (iOS 26 `glassEffect`; pre-26 `ultraThinMaterial`): tab bar, floating pills, sheet grabbers — content cards never glass; two glass layers never stack; the seal is never glass; Reduce Transparency → solid fill.

## Motion & haptics

Press = scale 0.97 on pointer-down, 150 ms strong ease-out, no haptic. Seal lands = stamp scale 1.15→1.0 `spring(0.4, bounce 0.25)` + heavy impact (bounce earned by the gesture). Reveal flip = per-row 3D flip, 60 ms stagger capped at 5, `spring(0.5, 0)`, `.success` haptic on your row; **Reduce Motion → crossfade**. Sheets `spring(0.45, bounce 0.2)` only after drag-release (button-open = bounce 0), always interruptible. Lists/tabs/keyboard actions never animate. Never `easeIn`.

## Visual reference

The eight target screens live at `docs/design/00-how-slip-works.png` … `07-standings.png` (exported from the maintained design file). UI work reproduces these — when code and PNG disagree, the PNG wins until the design file itself changes. The interactive flow explainer is `docs/how-slip-works.html`.

## Enforcement

`scripts/design-gate.sh <src-dir>` runs the mechanical subset (token discipline, raw font sizes, glass-outside-chrome, missing Reduce Motion guards, sub-44pt tappables, easeIn). Run it on every UI diff; fix causes at the token/system level — exemptions are design debt. Contrast targets: 4.5:1 (<18pt), 3:1 large — verify against the *effective* background, translucent chips get solid backing when text sits on art.

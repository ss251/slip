# Resources

## Official Midnight

- Docs: `https://docs.midnight.network` — **agent tip:** `https://docs.midnight.network/llms.txt` is a full index and every page under it serves raw markdown (`/compact.md`, `/api-reference/compact-runtime.md`, …). Prefer it over scraping.
- Compact language + stdlib reference: `https://docs.midnight.network/compact` (stdlib exports page has exact signatures for commit/hash/token primitives).
- Tutorials: bulletin-board series (contract → API → CLI → deploy) and the private-party tutorial — both map closely to Slip's shape.
- Academy: `https://academy.midnight.network` — 101 (fundamentals), 201 (ZK + architecture: Kachina, dual ledger, tx lifecycle), 301 (full DApp build), plus a Wallet SDK course (HD keys per CIP-1852, DUST registration, tx pipeline `transfer → sign → prove/bind → submit`).
- Developer hub, faucet (`https://midnight.network/test-faucet`), forum (`https://forum.midnight.network`), Discord (active dev chat), weekly Dev Hangouts on the Midnight YouTube.
- Token standards discussions: the MIPs repo (public design debates worth reading before inventing anything token-shaped).

## AI toolkit (officially recommended by Midnight)

- **Midnight Expert** — Claude Code plugin suite: writes/reviews Compact and verifies against the real compiler; `/midnight-expert:doctor` checks the toolchain. Install: `claude plugin marketplace add https://midnightntwrk.expert` (or use the `midnightntwrk/midnight-expert` repo as marketplace for latest). Third-party models get Compact wrong without this loop — always use it.
- **Kapa MCP** — docs Q&A endpoint (setup in the docs' AI-integration page).
- Community skills: `adavault/midnight-skill` (large set of compiler-validated Compact examples incl. prediction-market, RPS, escrow + a long gotchas list), `Kali-Decoder/Midnight-skills` (has full dapp templates incl. a private-party Next.js app), `mzf11125/midnight_agent_skills`.
- Compatibility matrix in the docs is the source of truth before pinning any package versions.

## Examples & prior art worth reading

- `midnightntwrk/example-bboard` — ZK-ownership pattern ("only the poster can take it down") ≈ our "only the sealer can reveal".
- `midnightntwrk/midnight-awesome-dapps` — ecosystem index; the RPS sample (commit–reveal) and football prediction-market sample are the closest contract prior art.
- `Moonsong-Labs/midnight-rs` — actively maintained Rust SDK (deploy/call/query) — useful reference for MidnightKit's chain client.
- Kuira (Android): an Android SDK + a Unity commit-reveal game exist in the ecosystem — the closest analog to MidnightKit on the other platform; our on-device-proving claim is scoped **to iOS**.
- Wallets: Lace, 1AM, Gero (newest; ships passkey support — precedent for our PRF plans), plus the official Wallet SDK for embedded flows.
- `midnight-local-dev` — the local `undeployed` network tooling (node/indexer/proof-server trio).

## Platform (Apple)

- HIG: `https://developer.apple.com/design/human-interface-guidelines/` — the numbers we hold: default type scale (34/28/22/20/17/16/15/13/12/11), 44×44pt hit regions, safe areas, Dynamic Type, Reduce Motion/Transparency behaviors.
- iOS 26 Liquid Glass: `glassEffect` APIs — chrome only (see `design.md`); current-API truth lives in Xcode's bundled AdditionalDocumentation, check it before hand-rolling 26.x surfaces.

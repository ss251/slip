# Resources

## Official Midnight

- Docs: `https://docs.midnight.network` — **agent tip:** `https://docs.midnight.network/llms.txt` is a full index and every page under it serves raw markdown (`/compact.md`, `/api-reference/compact-runtime.md`, …). Prefer it over scraping.
- Compact language + stdlib reference: `https://docs.midnight.network/compact` (stdlib exports page has exact signatures for commit/hash/token primitives).
- Tutorials: bulletin-board series (contract → API → CLI → deploy) and the private-party tutorial — both map closely to Slip's shape.
- Academy: `https://academy.midnight.network` — 101 (fundamentals), 201 (ZK + architecture: Kachina, dual ledger, tx lifecycle), 301 (full DApp build), plus a Wallet SDK course (HD keys per CIP-1852, DUST registration, tx pipeline `transfer → sign → prove/bind → submit`).
- Developer hub, faucet (`https://midnight.network/test-faucet`), forum (`https://forum.midnight.network`), Discord (active dev chat), weekly Dev Hangouts on the Midnight YouTube.
- Token standards discussions: the MIPs repo (public design debates worth reading before inventing anything token-shaped).

## MCP servers (committed — no setup command needed)

Both live in `.mcp.json` at the repo root, so cloning the repo is the install. Claude Code picks them up **at session start** — if you add or change one mid-session, restart the session or it will not appear in `/mcp` (the config is right; the running session simply bound its servers at launch). Subagents spawn fresh and do see current config, which can make this confusing to diagnose.

| server | what it answers | notes |
|---|---|---|
| `midnight` (kapa) | "what does Midnight *say* about X" — docs-grounded, indexes the docs, ledger/midnight.js/node repos, and the whitepaper | HTTP, `https://midnight.mcp.kapa.ai`. Requires an **OAuth step the docs page omits**: run `/mcp`, pick `midnight`, approve. Until then it shows `Needs authentication`. |
| `octocode-mcp` | "what does the code actually *do*" — GitHub source search; the `midnight-verify` agents use it | stdio via `npx`; no auth |

Reach for kapa when docs suffice, octocode when docs and behaviour might disagree — that split is how the block-time enforcement claim got settled at ledger source rather than taken on faith. The raw `llms.txt` markdown route stays useful when you want the page itself, not an answer.

## AI toolkit (officially recommended by Midnight)

- **Midnight Expert** — Claude Code plugin suite: writes/reviews Compact and verifies against the real compiler; `/midnight-expert:doctor` checks the toolchain. Install: `claude plugin marketplace add https://midnightntwrk.expert` (or use the `midnightntwrk/midnight-expert` repo as marketplace for latest). Third-party models get Compact wrong without this loop — always use it.
- **Kapa MCP** — docs Q&A endpoint (setup in the docs' AI-integration page).
- Community skills exist (`adavault/midnight-skill` — good gotchas list; `Kali-Decoder/Midnight-skills` — dapp templates; `mzf11125/midnight_agent_skills`) but are **not vendored here on purpose.** They duplicate a slice of the official suite with examples pinned to older language versions, and a stale reference is worse than none: their `compact-runtime` ceiling was correct for compiler 0.31.1 and wrong for ours (see ADAvault/midnight-skill#11 and #12, which we filed). Consult them upstream for patterns if useful; verify everything against the compiler.
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

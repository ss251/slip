# Security policy

Slip is pre-alpha. This policy covers the current development branch; any supported release lines will be documented when releases are published. See the [README](README.md) for demonstrated behavior and limitations. A local proof, a synthetic screenshot, and a confirmed network transaction establish different things.

## Report a vulnerability privately

Private reporting contact: sailesh.e123@gmail.com.

Do not publish a real vulnerability in a public issue. Report it privately to the address above first.

Include the affected commit or release, platform and toolchain versions, expected and observed behavior, a minimal reproduction using synthetic data, and the impact you believe is possible. Redact credentials, personal identifiers, private picks, salts, device secrets and private proving transcripts. Do not send a live user's witness to demonstrate a leak. If sensitive material is essential to understanding the report, first arrange a private handling method with the owner.

The owner will review the report privately, agree on any additional evidence needed, and coordinate a fix and disclosure. No response deadline or bounty is promised by this policy.

## The privacy invariant

**The witness `{choice, salt}` never leaves the device.** During sealing, only the commitment and the zero-knowledge proof may travel for the private pick. Never export witness data or private runtime/proving transcripts as logs, analytics, crash payloads, screenshots, launch arguments, clipboard content or network requests. Do not persist private pick material unencrypted.

Opening is an intentional disclosure: after the opening is verified against its original commitment, the choice may become public. That does not make the salt or device secret public. Public round metadata and verified openings must remain distinct from private witness material in both implementation and documentation.

The current local round retains its private pick material in memory; terminating the app loses that session. On-device proof generation has no remote proving fallback. A valid opening proves agreement with the original seal; it does not prove that nobody saw an unlocked phone. The [privacy rules](.claude/rules/privacy.md), [architecture](.claude/docs/architecture.md) and [testing guide](.claude/docs/testing.md) define the corresponding implementation and evidence requirements.

## Release blockers

Do not release a change while any of these remain unresolved:

- Witness data, device secrets or private transcripts escape the device, enter diagnostic output, or are persisted without encryption.
- An opening that does not match its commitment is accepted, or client behavior disguises circuit rejection as success.
- A new disclosure or data flow lacks an explicit review and a corresponding entry in the architecture's disclosure ledger. Each Compact `disclose()` must name what becomes public and why.
- A required compile, privacy probe, app test or applicable design/freshness gate fails or is bypassed. A skipped check is not passing evidence.
- Public materials contain credentials, real private-pick captures, private session links or an unconfigured security-reporting contact.

Use synthetic fixtures and the smallest reproducible case when investigating. Changes to contracts, proving, persistence or networking require their own authorized scope and relevant verification; a UI or documentation task does not authorize them. See [CONTRIBUTING.md](CONTRIBUTING.md).

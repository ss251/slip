# Privacy invariant

The witness — a player's `{choice, salt}` — never leaves the device. Concretely:

- Never log, print, snapshot, or persist it outside the encrypted local store.
- Never add analytics, crash-reporting payloads, or network calls that could carry it.
- Only the commitment and the zero-knowledge proof may travel.
- Every `disclose()` in Compact is deliberate and carries a one-line comment naming what becomes public and why.
- New data flows of any kind get a note in `.claude/docs/architecture.md` §Disclosure ledger before they ship.

If a feature seems to need the witness elsewhere, the feature is redesigned, not the invariant.

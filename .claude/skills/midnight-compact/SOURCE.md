# Source & attribution

Vendored from [adavault/midnight-skill](https://github.com/adavault/midnight-skill) at commit **869fb24** (2026-08-30 — "OpenZeppelin identity model moved to account IDs; add composition example"; upstream re-ran 11/11 suites / 676 tests at that commit).
License: MIT (see LICENSE in this directory). All credit to ADAvault.

Why vendored: gives any agent working in this repo compiler-validated Compact examples and a field-tested gotchas list, offline. Complementary to the official Midnight Expert plugin, which adds the compile-and-verify loop.

Freshness check: `git ls-remote https://github.com/adavault/midnight-skill HEAD` and compare to the commit above — **by commit, never by a version string in a file**.

---

## LOCAL DELTA — read before trusting version numbers in this skill

Upstream validates against **compiler 0.31.1 / language 0.23**. This repo builds on **compiler 0.34.0 / language 0.26** (verified 2026-08-31). Two consequences:

1. **`pragma language_version`** — upstream examples use `>= 0.23`. Ours use `>= 0.26`. A 0.23 example is not automatically wrong, but it has not been compiled against our toolchain. Treat every example here as a *pattern*, and let the compiler be the referee (that is what the Midnight Expert verify loop is for).

2. **The `compact-runtime` version warning is right in principle, wrong in its numbers for us.** Upstream says (SKILL.md §"Never npm install compact-runtime@latest") that npm `latest` is ahead of every released compiler and that **0.16.0 is the ceiling** — true *for compiler 0.31.1*. On our compiler the correct pin is different:

   ```
   compact compile -- --runtime-version   # -> 0.19.0 on compiler 0.34.0
   npm view @midnight-ntwrk/compact-runtime version   # -> 0.19.0 (they coincide right now)
   ```

   **Keep the rule, drop the constant:** the compiler decides the runtime version, not npm. Always pin `@midnight-ntwrk/compact-runtime` to whatever `compact compile -- --runtime-version` prints for the compiler you are actually building with. Blindly following upstream's "pin 0.16.0" would break against our 0.34.0 output; blindly taking npm `latest` breaks whenever npm runs ahead. Re-derive it, every time the toolchain moves.

3. Upstream's newest commit changes the **OpenZeppelin identity model to account IDs** — relevant if we ever adopt OZ Compact contracts; our own contract does not depend on it today.

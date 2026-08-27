# Verification bar

A change is done when the evidence says so, in this order:

1. `contracts/` touched → the contract **compiles** (paste compiler output) and simulator tests pass.
2. UI touched → `scripts/design-gate.sh` passes and the change was looked at rendered (simulator screenshot), not inferred from code.
3. Any claim in a summary ("faster", "fixed", "private") → backed by command output, a measurement, or a test name.

Prefer showing one failing command over describing three passing ones from memory.

# Contributing to Slip

Start with the [README](README.md) for the current build and its fresh-clone limitations, then [AGENTS.md](AGENTS.md) for repository conventions. Keep changes focused and follow the agreed task scope. A UI or documentation task does not authorize changes to MidnightKit, contracts, generated proving artifacts or networking.

Read the [product](.claude/docs/product.md) and [design](.claude/docs/design.md) references before changing UX or copy, the [architecture](.claude/docs/architecture.md) before changing data flow, and the [testing guide](.claude/docs/testing.md) before adding functionality. Read [SECURITY.md](SECURITY.md) before reporting a vulnerability; use a private report for sensitive findings.

## Prepare the checkout

Follow the README's build-input and parameter-staging instructions. The required native archive and generated artifacts are not all distributed in a fresh clone. Report missing inputs honestly; do not substitute placeholder proofs or describe skipped native checks as passing.

The [CI app-test job](.github/workflows/ci.yml) checks for `MidnightKit/Vendor/libslip_prove_ffi.a`, the six circuits' ZKIR/prover/verifier files under `contracts/build/`, and staged k13/k14 public parameters under `.build/app-proof-params/`. These inputs are not tracked, and the Rust archive's source lives outside this repository. A fresh clone therefore warns and skips app tests; a green workflow does **not** establish that the app suite passed. The app target exists in `project.yml`; the ignored `Slip.xcodeproj` is generated with XcodeGen 2.45+ when the inputs are available. CI does not download or fabricate them. Run the app suite locally with the matching inputs and include its actual passed-count line.

Install the repository hooks from the checkout root:

```sh
sh scripts/install-hooks.sh
```

Run commits with the normal pre-commit hook enabled. It checks that the local, gitignored progress note is current: update the note named in the hook's diagnostic with what changed, verification, blockers and next steps before retrying. Keep that private note out of commits and public documentation. Do not bypass the hook with `--no-verify`, an alternate hooks path or a replacement no-op hook.

The installed pre-push hook runs toolchain freshness, design/privacy checks and a contract compile. Respect the task's authorization before pushing or generating contract artifacts. If a required check cannot run within that scope, report the limitation instead of disabling the check.

## Verify the change

For app changes, run the app suite and include its actual passed-count line in the review evidence:

```sh
xcodebuild -scheme Slip -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

**Debug is the tested configuration.** The unsigned arm64 simulator Release app builds, but the current app suite uses `@testable import Slip`: running it with `-configuration Release` fails before test execution because that module is built without `-enable-testing` (`ENABLE_TESTABILITY=NO`). Do not count that attempt as a pass or enable testability in the shipping configuration to hide the distinction. The local native prover archive supports arm64 simulators only. See the [Release build audit](docs/release-audit.md) for the build, bundle and DEBUG-surface evidence.

For every UI change, also run:

```sh
scripts/design-gate.sh Slip/
```

Use the shared design tokens, preserve 44×44pt hit targets and Dynamic Type, and inspect the changed screens on the simulator in light and dark. Check affected Reduce Motion and Reduce Transparency behavior. Screenshots establish layout; they do not establish gesture timing, haptic delivery, proof correctness or network acceptance. Record the device/runtime actually tested rather than inferring compatibility from the deployment target. **Full-app runtime verification is currently on iOS 27 only.** The iOS 17 deployment target is unverified as a supported minimum, and physical iOS 26.6.1 proving-component results do not establish full UI compatibility. The pre-iOS 26 material fallback and signing/archive path still need separate verification. See [runtime compatibility](docs/runtime-compatibility.md).

Run the toolchain freshness gate:

```sh
sh scripts/freshness-gate.sh
```

`--no-network` is available for local iteration; label that result as local checks only. It does not establish upstream freshness. Inspect the output: a successful process exit with “skipping” because Compact is missing is not a completed freshness check. The [verification rules](.claude/rules/verification.md) and [CI configuration](.github/workflows/ci.yml) describe the applicable gates. Add tests for new behavior and targeted regressions; do not weaken assertions or snapshot thresholds to make a failure disappear.

## Snapshot updates

Review the rendered change against the [canonical design boards](docs/design/v6/) before recording. Re-record only the affected routes with an explicit allowlist. For example, for an approved change to the home route:

```sh
TEST_RUNNER_SLIP_RECORD_SNAPSHOTS=1 \
TEST_RUNNER_SLIP_SNAPSHOT_SCREENS=01-home \
xcodebuild -scheme Slip -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The allowlist accepts comma-separated route identifiers. Recording without a nonempty valid allowlist is rejected by [ScreenSnapshotTests](SlipTests/ScreenSnapshotTests.swift). Run the suite again without recording to verify the references. Keep PNGs compact with lossless compression and verify decoded pixel identity; avoid unrelated snapshot churn. Refresh only the corresponding canonical v6 boards, using the filename mapping in the design reference. Use synthetic fixtures, never real private picks, and serialize simulator capture and test runs.

## Compact and dependency changes

Contract changes require explicit scope. When authorized, the contract must compile and its simulator tests must pass before the change can land:

```sh
compact compile contracts/slip.compact contracts/build
```

An iteration using `--skip-zk` is not the final compile gate. The compiler is the referee for Compact: documentation, generated code and examples must be checked by actual compilation and execution. Follow the [mandatory Midnight tooling](.claude/rules/midnight-tooling.md) and [Compact reference](.claude/docs/compact.md).

Use the compiler pin in CI and the repository's matching dependency pins. The compiler decides the runtime version, not npm: check `compact compile -- --runtime-version` before changing the runtime dependency. Do not move to `latest` or regenerate artifacts as incidental cleanup. Every deliberate `disclose()` needs a one-line explanation of what becomes public and why.

## Commits and review

Use atomic conventional commits, such as `design(feed): clarify row hierarchy`, `fix(app): preserve cancellation`, or `docs: clarify local proof evidence`. Do not include private session links, credentials, real private-pick captures or machine-specific personal details in commit messages, patches or review attachments.

Describe the resulting behavior, why the change is needed, the exact checks run and their output, and anything unverified or skipped. Keep claims proportional to the evidence. The witness `{choice, salt}` never leaves the device; redesign any proposal that depends on exporting it. Push, publish and release only within explicit owner authorization.

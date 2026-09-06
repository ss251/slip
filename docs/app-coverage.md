# App coverage — 2026-09-06

Measured on the iPhone 17 Pro simulator, iOS 27, with Debug instrumentation and
`-enableCodeCoverage YES`. Baseline is `ca540a1`; the after run adds the 23 tests
in the five linked test files below. No production Swift behavior or snapshot pixels
changed. The after build also contains the draft privacy resource; this report does
not establish that its pending collection declaration is ready for submission.

```text
Before: ✔ Test run with 73 tests in 14 suites passed after 110.182 seconds.
After:  ✔ Test run with 96 tests in 19 suites passed after 112.374 seconds.
Both:   ** TEST SUCCEEDED **
```

This is Xcode executable **line coverage**, not a percentage of branches or proof of
all possible states. Fractions are exact; percentages are rounded to six decimals.
Only `Slip/` paths are included, excluding MidnightKit and SlipTests. All 120 existing
snapshot comparisons pass without recording or threshold changes.

## Five least-covered non-view files

Ranked by baseline line coverage among `Slip/Sealing` and `Slip/Models`.
`DebugPublicProofExport.swift` is a DEBUG ViewModifier;
`LocalRoundPreviewFixture.swift` provides DEBUG screenshot fixtures and a ViewModifier.
Both appear in the full table but are excluded from this non-view target selection.

| Target | Before | After | Focused tests |
|---|---:|---:|---|
| [NetworkSetup.swift](../Slip/Sealing/NetworkSetup.swift) | 34/62 (54.838710%) | 44/62 (70.967742%) | [NetworkSetupCoverageTests](../SlipTests/NetworkSetupCoverageTests.swift) |
| [SealFlowModel.swift](../Slip/Sealing/SealFlowModel.swift) | 225/264 (85.227273%) | 254/264 (96.212121%) | [SealFlowCoverageTests](../SlipTests/SealFlowCoverageTests.swift) |
| [Screen.swift](../Slip/Models/Screen.swift) | 48/54 (88.888889%) | 54/54 (100.000000%) | [AppModelCoverageTests](../SlipTests/AppModelCoverageTests.swift) |
| [LocalSealingService.swift](../Slip/Sealing/LocalSealingService.swift) | 693/764 (90.706806%) | 743/764 (97.251309%) | [LocalSealingCoverageTests](../SlipTests/LocalSealingCoverageTests.swift) |
| [NetworkSealAdapter.swift](../Slip/Sealing/NetworkSealAdapter.swift) | 74/80 (92.500000%) | 80/80 (100.000000%) | [NetworkSealAdapterCoverageTests](../SlipTests/NetworkSealAdapterCoverageTests.swift) |

The tests cover isolated defaults round trips/removal and malformed setup, identity
store errors, relay transport/cancellation/confirmation errors, local fallback,
model failure/retry and cached-result identity, busy-operation guards, lifecycle
transitions and navigation fallback. A native test corrupts only a temporary copy of
public circuit data, verifies the safe error and absent cached result, restores the
file, then proves successfully through the same service. No test sends a real relay
request or writes a witness to disk. Suspended model operations use continuations.

Remaining uncovered native Keychain return codes and secure-random failures have no
safe injectable seam. Internal parser/ledger-validation defensive errors and some
native error mappings cannot be induced through the public service API without
changing production injection points or corrupting runtime behavior. Those gaps are
left explicit; production behavior was not changed to raise coverage.

## Every app source file

| File | Before: covered/executable | Before % | After: covered/executable | After % |
|---|---:|---:|---:|---:|
| [App/SlipApp.swift](../Slip/App/SlipApp.swift) | 72/114 | 63.157895 | 72/114 | 63.157895 |
| [App/SlipRootView.swift](../Slip/App/SlipRootView.swift) | 95/98 | 96.938776 | 95/98 | 96.938776 |
| [DesignSystem/AccessibilityOverrides.swift](../Slip/DesignSystem/AccessibilityOverrides.swift) | 5/5 | 100.000000 | 5/5 | 100.000000 |
| [DesignSystem/Chrome/GlassTabBar.swift](../Slip/DesignSystem/Chrome/GlassTabBar.swift) | 57/60 | 95.000000 | 57/60 | 95.000000 |
| [DesignSystem/Components/SharedViews.swift](../Slip/DesignSystem/Components/SharedViews.swift) | 489/508 | 96.259843 | 489/508 | 96.259843 |
| [DesignSystem/DesignTokens.swift](../Slip/DesignSystem/DesignTokens.swift) | 19/19 | 100.000000 | 19/19 | 100.000000 |
| [DesignSystem/HeadingAccessibility.swift](../Slip/DesignSystem/HeadingAccessibility.swift) | 0/1 | 0.000000 | 0/1 | 0.000000 |
| [DesignSystem/ResultAccessibility.swift](../Slip/DesignSystem/ResultAccessibility.swift) | 42/54 | 77.777778 | 42/54 | 77.777778 |
| [DesignSystem/RowAccessibility.swift](../Slip/DesignSystem/RowAccessibility.swift) | 36/37 | 97.297297 | 36/37 | 97.297297 |
| [DesignSystem/SealAccessibility.swift](../Slip/DesignSystem/SealAccessibility.swift) | 51/60 | 85.000000 | 51/60 | 85.000000 |
| [Models/Screen.swift](../Slip/Models/Screen.swift) | 48/54 | 88.888889 | 54/54 | 100.000000 |
| [Screens/CreationScreens.swift](../Slip/Screens/CreationScreens.swift) | 820/959 | 85.505735 | 820/959 | 85.505735 |
| [Screens/CrewScreens.swift](../Slip/Screens/CrewScreens.swift) | 1391/1454 | 95.667125 | 1391/1454 | 95.667125 |
| [Screens/HomeScreens.swift](../Slip/Screens/HomeScreens.swift) | 940/967 | 97.207859 | 940/967 | 97.207859 |
| [Screens/ResultScreens.swift](../Slip/Screens/ResultScreens.swift) | 2333/3289 | 70.933414 | 2333/3289 | 70.933414 |
| [Screens/SealScreens.swift](../Slip/Screens/SealScreens.swift) | 794/998 | 79.559118 | 794/998 | 79.559118 |
| [Sealing/DebugPublicProofExport.swift](../Slip/Sealing/DebugPublicProofExport.swift) | 56/106 | 52.830189 | 56/106 | 52.830189 |
| [Sealing/LocalRoundPreviewFixture.swift](../Slip/Sealing/LocalRoundPreviewFixture.swift) | 24/163 | 14.723926 | 24/163 | 14.723926 |
| [Sealing/LocalSealingService.swift](../Slip/Sealing/LocalSealingService.swift) | 693/764 | 90.706806 | 743/764 | 97.251309 |
| [Sealing/NetworkSealAdapter.swift](../Slip/Sealing/NetworkSealAdapter.swift) | 74/80 | 92.500000 | 80/80 | 100.000000 |
| [Sealing/NetworkSealingService.swift](../Slip/Sealing/NetworkSealingService.swift) | 74/76 | 97.368421 | 74/76 | 97.368421 |
| [Sealing/NetworkSetup.swift](../Slip/Sealing/NetworkSetup.swift) | 34/62 | 54.838710 | 44/62 | 70.967742 |
| [Sealing/SealFlowModel.swift](../Slip/Sealing/SealFlowModel.swift) | 225/264 | 85.227273 | 254/264 | 96.212121 |
| [DesignSystem/Typography.swift](../Slip/DesignSystem/Typography.swift) | Not emitted | N/A | Not emitted | N/A |
| **Slip total** | **8372/10192** | **82.142857** | **8473/10192** | **83.133830** |

Xcode emitted 23 source-file records; Typography.swift has no emitted executable-line
record in either report and is not represented as 0% coverage. All non-target records
are unchanged between runs. The five targets gain 101 covered lines in total.

## Reproduction

Use the existing locally prepared native archive, public proof artifacts and params;
see [CONTRIBUTING](../CONTRIBUTING.md). No dependency or network changes are required.
Run the baseline at `ca540a1` before adding these tests and use a fresh result path
for each run. The commands used were:

```sh
xcodegen generate
xcodebuild -scheme Slip \
  -destination 'platform=iOS Simulator,id=670DB62C-18B0-49C0-A910-FD8C45E4B951' \
  -derivedDataPath /tmp/slip-luma-build -enableCodeCoverage YES \
  -resultBundlePath /tmp/slip-coverage-before-20260906.xcresult test
# After adding the focused tests, repeat with:
# -resultBundlePath /tmp/slip-coverage-final-20260906.xcresult
xcrun xccov view --report --json /tmp/slip-coverage-before-20260906.xcresult
xcrun xccov view --report --json /tmp/slip-coverage-final-20260906.xcresult
xcrun xccov view --archive --file "$PWD/Slip/Sealing/SealFlowModel.swift" \
  /tmp/slip-coverage-before-20260906.xcresult
scripts/design-gate.sh Slip/
sh scripts/freshness-gate.sh --no-network
```

Keep only file records whose absolute path starts with the repository's `Slip/`
directory when processing `xccov` JSON. Do not use a package-wide aggregate that
includes test or native-package sources. Design and local freshness gates pass.

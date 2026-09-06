# Runtime compatibility

Recorded on 2026-09-06. **The Debug suite passed on iOS 27.0 and iOS 18.6; canonical pixel references are recorded on iOS 27.0.0.** iOS 18.6 also has reviewed light/dark renders and a completed real local rehearsal. Other runtimes explicitly skip canonical comparison and recording while all remaining tests must pass. The iOS 17 deployment setting is not a verified supported minimum or archive result.

| Runtime and device | Observed evidence |
|---|---|
| iOS 27.0 (24A5423a), iPhone 15 Pro simulator | Debug build succeeded; `✔ Test run with 96 tests in 19 suites passed after 130.395 seconds.` All 120 reviewed snapshots pass without re-recording. |
| iOS 27, iPhone 17 Pro simulator | Accepted app gate: 96 tests in 19 suites passed after 114.134 seconds. The fixed snapshot canvas also passes on this destination. |
| iOS 26.6.1, physical iPhone 15 Pro | [Recorded component measurements](../README.md#native-proof-and-network-evidence) cover sealing, native proving and the six-circuit local lifecycle. They do not establish full-app UI, accessibility or archive compatibility. |
| iOS 18.6 (22G86), iPhone 15 Pro simulator | Debug build and suite succeeded: 96 passed, one explicit canonical-comparison skip, zero failures. Real local rehearsal completed in 180.05 seconds; eight light/dark captures exercise the app and material tab-bar fallback. Exact final output is below. |
| iOS 17 | Runtime behavior and archive compatibility remain unverified. |

## Snapshot runtime contract

The owner-approved contract scopes [ScreenSnapshotTests.allScreens](../SlipTests/ScreenSnapshotTests.swift), including comparison and recording, to the recorded **iOS 27.0.0** runtime. The version decision matches **major, minor and patch**: a different version, including 27.0.1 or 27.1.0, does not match the reference runtime. Swift Testing's conditional disabled trait reports an **explicit skip** with a reason identifying the reference and running versions. On iOS 18.6.0 the reason is:

```text
Snapshot pixel comparisons skipped by runtime: references recorded on iOS 27.0.0; running iOS 18.6.0.
```

Only `allScreens` is skipped. Accessibility layout rendering, machine-font availability, rendered contrast and all other tests still run and must pass. The skipped comparison must not silently return success or be reported as a PNG-match pass. On the canonical runtime, the `SNAPSHOT_REFERENCE_COMPARISONS` completion marker records the comparison count and threshold.

The 120 canonical PNGs and the `0.012` comparison threshold are unchanged. Runtime-only font, symbol or native-chrome differences do not authorize re-recording, a weaker threshold or OS-specific references. Recording remains limited to authorized changes that alter the default app's pixels on iOS 27.0.0, using the route allowlist described in [CONTRIBUTING](../CONTRIBUTING.md#snapshot-updates). Render verification on iOS 18.6 consists of the reviewed native captures and real local rehearsal below.

### Final Debug gates

Runtime-contract test change: `46db91b`. Final iOS 18.6 run used an arm64 iPhone 15 Pro simulator and this Debug command, with no recording flags:

```sh
xcodebuild -scheme Slip -configuration Debug \
  -destination 'platform=iOS Simulator,id=2537569D-906C-4B04-A67C-B8D03231EF12' \
  -derivedDataPath /tmp/slip-ios18-build -parallel-testing-enabled NO test
```

The disposable device was shut down and deleted immediately after the command finished; the temporary build directory was removed after preserving the test summary. Reproduction needs a newly created device ID.

| Runtime | Exact final test output |
|---|---|
| iOS 27.0.0 | `✔ Test run with 97 tests in 19 suites passed after 117.925 seconds.` |
| iOS 18.6.0 | `✔ Test run with 97 tests in 19 suites passed after 51.076 seconds.` |

The iOS 27 result summary contains **97 passed, zero skipped, zero failed**, and the log confirms `SNAPSHOT_REFERENCE_COMPARISONS: 120 compared against iOS 27.0.0 references; threshold 0.012.` The iOS 18.6 result summary contains **96 passed, one skipped, zero failed**: the run headline includes the skipped test in its count of 97. Every remaining test passed. The actual iOS 18.6 log reports:

```text
Test "Every screen matches its reviewed light, dark, XL and accessibility snapshots" skipped: "Snapshot pixel comparisons skipped by runtime: references recorded on iOS 27.0.0; running iOS 18.6.0."
** TEST SUCCEEDED **
```

No canonical pixel comparisons ran on iOS 18.6. These are Debug gates. The separate [Release audit](release-audit.md) establishes an unsigned arm64 simulator Release build and bundle inspection; its Release test attempt failed before executing tests because the app module lacked testability. A Debug rehearsal or test result does not turn that attempt into a Release test pass.

## Runtime installation history

Before the follow-up installation, `xcrun simctl list runtimes` reported only iOS 27.0 (24A5423a). Apple's [simulator catalog](https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex) listed iOS 18.6 (22G86) as the newest 18.x entry, with an asset size of **8,858,413,428 bytes (8.86 GB)**. The earlier attempt was bounded to 40 minutes:

```sh
xcodebuild -downloadPlatform iOS -buildVersion 18.6
```

It returned `iOS 18.6 is not available for download.` with exit **70** after **2.874 seconds**. No login or download occurred in that attempt. The installed-runtime inventory remained unchanged. The attempt stopped at this refusal; the catalog size is an expected download size, not downloaded bytes. No cached iOS runtime disk image or `xcodes` installation was available through the checked local paths.

The owner subsequently downloaded and installed iOS 18.6 through Xcode's UI. It was Ready at 10:53:33 on 2026-09-06, with iOS 27 and iOS 18.6 both installed. No command-line download was attempted in this follow-up. The earlier CLI refusal remains historical evidence; it is not the current installation state.

## iOS 18.6 render and local-run evidence

The Debug app ran the [three-minute runbook](demo.md) in **180.05 seconds**, in one in-memory local round with no network configuration: create → full hold-to-seal → ticket → room → opening → call → verdict → standings. The run verified the expected route labels and displayed five native proof receipts. The seal receipt showed **0.999 s** and **4,480 bytes**. These are single-run simulator observations, not latency promises or a performance budget.

| Local step | Prepare | Key load | Proof | Proof bytes |
|---|---:|---:|---:|---:|
| Enroll | 138.4 ms | 15 ms | 550 ms | 4,480 |
| Create | 24.3 ms | 15 ms | 523 ms | 4,480 |
| Seal | 25.8 ms | 29 ms | 999 ms | 4,480 |
| Open | 38.1 ms | 28 ms | 989 ms | 4,480 |
| Call | 51.0 ms | 17 ms | 514 ms | 4,480 |

Eight reviewed native captures cover Home, Seal your pick, Sealed ticket and Sealed room in light and dark; no layout defect was found in those captures. The [tab bar](../Slip/DesignSystem/Chrome/GlassTabBar.swift) is the only explicit OS-availability branch in `Slip/`: `glassEffect` on iOS 26 and later, `ultraThinMaterial` before iOS 26, with Reduce Transparency choosing a separate solid-fill branch first. The normal-transparency iOS 18.6 Home captures therefore exercise the actual material fallback. Floating hero pills and custom sheet grabbers have solid/token-colored implementations on all OS versions. This evidence does not establish every accessibility or motion state.

Baseline motion recordings also cover opening and the sealed-room roster in light and dark with Reduce Motion off. Opening uses a labelled synthetic revealed fixture; the room uses preview content. These recordings are visual evidence, separate from the real proving rehearsal, and do not establish Reduce Motion behavior or physical haptic delivery.

### Why the canonical comparison is runtime-scoped

Before the explicit runtime contract, the first iOS 18.6 Debug run reported:

```text
Snapshot changed: 08-crews-accessibilityMax, mean pixel difference 0.02094339442924984
✘ Test run with 96 tests in 19 suites failed after 114.062 seconds with 1 issue.
** TEST FAILED **
```

The other 119 reference variants passed. A repeat produced the same difference. Inspection of the exact 393×1100 canvas and native AX5 captures found the same text wrapping and usable layout. Vertical text/symbol metrics around the repeated document metadata rows accumulated roughly 2–5 points of displacement in later crew rows. The [row implementation](../Slip/DesignSystem/Components/SharedViews.swift) aligns the SF Symbol and text by their first baseline; the observed pixel difference did not establish a product layout defect.

The owner resolved the comparison-scope mismatch by approving the explicit runtime contract above. No production layout change, reference re-recording or threshold adjustment was made for this difference. The failed historical run remains a failed run; it is not retroactively counted as passing.

## Earlier iOS 27 UI and test evidence

The first iPhone 15 Pro test attempt reported a runner restart during enrollment proving and then snapshot mismatches. Its incomplete result is not counted as a pass; the restart cause was not established. The subsequent complete run passed all 96 tests without a restart.

The light/dark iOS 27 captures exercise the [tab bar's](../Slip/DesignSystem/Chrome/GlassTabBar.swift) actual `glassEffect` branch with Reduce Transparency off. The later iOS 18.6 captures described above exercise its pre-iOS 26 material branch. Enabling Reduce Transparency exercises the separate solid-fill branch and cannot substitute for either normal-transparency runtime check.

The snapshot harness fixes the content safe area as well as the image dimensions. The reviewed 393×852 canvas uses 62-point top / 12-point bottom insets, and the 393×1100 accessibility canvas uses 62/34. These are reference-canvas metrics, not app layout rules. Previously the iPhone 15 Pro inherited 59/34 and shifted otherwise unchanged content. That test-only correction retained every reviewed PNG and the original comparison threshold; actual simulator captures retain their natural device safe areas.

The iPhone 15 Pro on iOS 27 completed the [three-minute runbook](demo.md) in **180.08 seconds**, in one app process: create → full hold-to-seal → ticket → room → opening → call → verdict → standings. Ten screenshots cover the steps and receipt details; light/dark Home captures exercise the live glass chrome. No app crash or layout defect appeared in the completed rehearsal. The seal receipt showed **1.587 s** and **4,480 bytes**; this is one simulator observation, not a latency promise.

Coordinates were remeasured from accessibility frames for the 393×852-point device. With this idb build, explicit `--duration 0.1` ordinary HID taps delivered the transitions reliably; a default-duration tap had not delivered Create slip. The seal command retained `--duration 1.4`, crossing the unchanged 1.2-second threshold. Initial harness failures are excluded from the completed-run result.

| Local step | Prepare | Key load | Proof | Proof bytes |
|---|---:|---:|---:|---:|
| Enroll | 117.0 ms | 23 ms | 853 ms | 4,480 |
| Create | 34.0 ms | 29 ms | 853 ms | 4,480 |
| Seal | 25.6 ms | 28 ms | 1,587 ms | 4,480 |
| Open | 80.4 ms | 30 ms | 1,104 ms | 4,480 |
| Call | 34.6 ms | 15 ms | 678 ms | 4,480 |

## Remaining scope

The [demo runbook](demo.md) exercises a single-player local sample. Its proofs remain local, and the later verified opening deliberately reveals the choice while the salt stays private. Neither runtime rehearsal establishes relay acceptance, connected crews, simultaneous arrivals, haptic delivery on hardware, or that nobody saw an unlocked phone. iOS 17 runtime acquisition and validation, any owner-managed Apple ID steps needed for it, signing/device archive validation and TestFlight remain separate follow-ups. The deployment target is not a verified minimum.

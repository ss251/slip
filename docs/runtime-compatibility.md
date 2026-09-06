# Runtime compatibility

Recorded on 2026-09-06. Full-app runtime verification is **iOS 27 only**. The iOS 17 deployment setting is not a verified supported minimum or archive result.

| Runtime and device | Observed evidence |
|---|---|
| iOS 27.0 (24A5423a), iPhone 15 Pro simulator | Debug build succeeded; `✔ Test run with 96 tests in 19 suites passed after 130.395 seconds.` All 120 reviewed snapshots pass without re-recording. |
| iOS 27, iPhone 17 Pro simulator | Accepted app gate: 96 tests in 19 suites passed after 114.134 seconds. The fixed snapshot canvas also passes on this destination. |
| iOS 26.6.1, physical iPhone 15 Pro | [Recorded component measurements](../README.md#native-proof-and-network-evidence) cover sealing, native proving and the six-circuit local lifecycle. They do not establish full-app UI, accessibility or archive compatibility. |
| iOS 18.6 (22G86) | Download command refused; runtime not installed or tested. |
| iOS 17 | Runtime behavior and archive compatibility remain unverified. |

## Older-runtime attempt

`xcrun simctl list runtimes` reported only iOS 27.0 (24A5423a). Apple's [simulator catalog](https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex) listed iOS 18.6 (22G86) as the newest 18.x entry, with an asset size of **8,858,413,428 bytes (8.86 GB)**. The attempt was bounded to 40 minutes:

```sh
xcodebuild -downloadPlatform iOS -buildVersion 18.6
```

It returned `iOS 18.6 is not available for download.` with exit **70** after **2.874 seconds**. No login or download occurred. The installed-runtime inventory remained unchanged. The attempt stopped at this refusal; the catalog size is an expected download size, not downloaded bytes. No cached iOS runtime disk image or `xcodes` installation was available through the checked local paths.

## UI and test evidence

The first iPhone 15 Pro test attempt reported a runner restart during enrollment proving and then snapshot mismatches. Its incomplete result is not counted as a pass; the restart cause was not established. The subsequent complete run passed all 96 tests without a restart.

The [tab bar](../Slip/DesignSystem/Chrome/GlassTabBar.swift) uses `glassEffect` on iOS 26 and later when Reduce Transparency is off. The light/dark iOS 27 captures exercise this actual branch. The pre-iOS 26 `ultraThinMaterial` fallback remains untested; enabling Reduce Transparency exercises the separate solid-fill branch and cannot substitute for an older runtime.

The snapshot harness now fixes the content safe area as well as the image dimensions. The reviewed 393×852 canvas uses 62-point top / 12-point bottom insets, and the 393×1100 accessibility canvas uses 62/34. These are reference-canvas metrics, not app layout rules. Previously the iPhone 15 Pro inherited 59/34 and shifted otherwise unchanged content. The test-only correction retains every reviewed PNG and the original comparison threshold; actual simulator captures retain their natural device safe areas.

The iPhone 15 Pro completed the [three-minute runbook](demo.md) in **180.08 seconds**, in one app process: create → full hold-to-seal → ticket → room → opening → call → verdict → standings. Ten screenshots cover the steps and receipt details; light/dark Home captures exercise the live glass chrome. No app crash or layout defect appeared in the completed rehearsal. The seal receipt showed **1.587 s** and **4,480 bytes**; this is one simulator observation, not a latency promise.

Coordinates were remeasured from accessibility frames for the 393×852-point device. With this idb build, explicit `--duration 0.1` ordinary HID taps delivered the transitions reliably; a default-duration tap had not delivered Create slip. The seal command retained `--duration 1.4`, crossing the unchanged 1.2-second threshold. Initial harness failures are excluded from the completed-run result.

| Local step | Prepare | Key load | Proof | Proof bytes |
|---|---:|---:|---:|---:|
| Enroll | 117.0 ms | 23 ms | 853 ms | 4,480 |
| Create | 34.0 ms | 29 ms | 853 ms | 4,480 |
| Seal | 25.6 ms | 28 ms | 1,587 ms | 4,480 |
| Open | 80.4 ms | 30 ms | 1,104 ms | 4,480 |
| Call | 34.6 ms | 15 ms | 678 ms | 4,480 |

The [demo runbook](demo.md) exercises a single-player local sample. Its proofs remain local, and the later verified opening deliberately reveals the choice while the salt stays private. This does not establish relay acceptance, connected crews, simultaneous arrivals, haptic delivery on hardware, or that nobody saw an unlocked phone. TestFlight, signing/archive and an older-runtime run remain owner follow-ups.

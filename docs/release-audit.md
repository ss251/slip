# Release configuration audit — 2026-09-06

The unsigned **arm64 iOS Simulator Release app builds successfully** after four corrections. Its DEBUG controls are excluded and its bundle metadata and resources pass inspection. The app suite remains **Debug-tested**: the Release test attempt failed before executing tests because the suite requires testability.

Audited app source: `7f34ae9`, following accepted `ee8657d`. Environment: Xcode 27.0 (`27A5252f`), iOS 27.0 simulator, shared iPhone 17 Pro `670DB62C-18B0-49C0-A910-FD8C45E4B951`. No additional simulator was booted. This establishes an unsigned simulator build, not a signed device archive, TestFlight acceptance or older-runtime compatibility. See [runtime compatibility](runtime-compatibility.md).

## Build and corrections

The requested build was run with an isolated derived-data directory:

```sh
xcodegen generate
xcodebuild -scheme Slip -configuration Release -sdk iphonesimulator \
  -destination id=670DB62C-18B0-49C0-A910-FD8C45E4B951 \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/slip-release-audit build
```

The first attempt exited 65. Release tried to link x86_64 against the arm64-only native prover archive:

```text
ld: symbol(s) not found for architecture x86_64
** BUILD FAILED **
```

`lipo -info MidnightKit/Vendor/libslip_prove_ffi.a` reported `architecture: arm64`. The [project configuration](../project.yml) now explicitly targets arm64 for the simulator; it does not claim Intel simulator support. No native archive or contract was changed.

| Commit | Finding | Correction |
|---|---|---|
| `8b1767c` | Release requested an architecture unavailable in the local native archive. | Set the simulator architecture to arm64. |
| `df000b6` | Release help contained `Launch with --relay and --contract, or ask your steward for a setup link.` despite lacking those launch controls or a setup-link handler. | Guard the developer help and launch-argument parser. Release explains that no steward connection is configured and local proving remains available. Verified through actual You → Steward relay navigation in light and dark. |
| `0fc5c08` | The bundle lacked standard version/build keys. | Supply `CFBundleShortVersionString` and `CFBundleVersion` from project settings, preserving the existing 0.1.0 / 1 values. |
| `7f34ae9` | XcodeGen's app-target device family overrode the project-level iPhone-only setting with `[1, 2]`. | Set `TARGETED_DEVICE_FAMILY: 1` on the app target explicitly. |

The final command repeated the build above with `clean build` to inspect fresh resources:

```text
** CLEAN SUCCEEDED **
** BUILD SUCCEEDED **
```

The resulting executable is Mach-O arm64. Its SHA-256 is `8420693474bb0401ff1e61d572f833cbf6ca44f99ab57912bb8e47fe73c2b767`. The clean compilation used optimization and no `-D DEBUG` / `-DDEBUG`. No optimizer-only Swift failure or unguarded testability dependency blocked the app build.

Existing linker warnings remain: some native objects were built for simulator iOS 27 while the app advertises deployment target 17, and a relative `Vendor` search path is absent while the configured absolute search path resolves the archive. Neither establishes support for an older runtime. Rebuilding the native archive and validating a signed device archive remain separate work.

## DEBUG surface evidence

Inspected the final executable with `xcrun strings -a`, `xcrun nm`, demangled symbol names and raw-byte searches. There is one Mach-O code image in this bundle. The source guards, three Slip compiler command records without DEBUG, and zero marker matches together establish exclusion; a zero string or stripped-symbol count alone would not.

The original 12 guards and the two guards added during this audit are listed below. Every marker count is zero in the final Release executable. Source links identify the guard, rather than a private evidence directory.

| # | Guarded source and behavior | Evidence line: Release marker hits |
|---|---|---|
| 1 | [SlipApp: launch properties](../Slip/App/SlipApp.swift#L13) | `localFixture`, `exportPublicProof`: **0** symbol/metadata hits |
| 2 | [SlipApp: launch overrides](../Slip/App/SlipApp.swift#L23) | All 13 override flags listed below, `steward.local`, `SLIP_MEMBER_ID=`: **0** string hits |
| 3 | [SlipApp: fixture/export attachment](../Slip/App/SlipApp.swift#L101) | `DebugLocalFixtureLaunch`, `DebugPublicProofExport`: **0** symbol/metadata hits |
| 4 | [LocalSealingService: adversarial reveal](../Slip/Sealing/LocalSealingService.swift#L563) | `rejectMismatchedReveal`: **0** symbol/metadata hits |
| 5 | [ResultScreens: opening shortcut](../Slip/Screens/ResultScreens.swift#L159) | `Preview opening`: **0** string hits |
| 6 | [ResultScreens: opening/call shortcuts](../Slip/Screens/ResultScreens.swift#L258) | `Preview everyone opened`, `Preview call sheet`: **0** string hits |
| 7 | [ResultScreens: standings shortcut](../Slip/Screens/ResultScreens.swift#L405) | `Preview standings`: **0** string hits |
| 8 | [CrewScreens: footer capture](../Slip/Screens/CrewScreens.swift#L287) | `--profile-footer`: **0** string/raw-byte hits |
| 9 | [ResultAccessibility: preview actions](../Slip/DesignSystem/ResultAccessibility.swift#L35) | `ResultPreviewAction`, `ResultPreviewAccessibility`: **0** symbol/metadata hits; preview hint: **0** string hits |
| 10 | [DebugPublicProofExport: whole file](../Slip/Sealing/DebugPublicProofExport.swift#L1) | `phase6-public-seal.json`, `Public proof export ready.`, `Public proof export failed.`: **0** string hits |
| 11 | [NetworkSealAdapter: diagnostics](../Slip/Sealing/NetworkSealAdapter.swift#L52) | `network seal failed:`, `urlError=`: **0** string hits |
| 12 | [LocalRoundPreviewFixture: whole file](../Slip/Sealing/LocalRoundPreviewFixture.swift#L1) | `Synthetic QA fixture`, `synthetic-public-player`: **0** string hits; fixture type/launch modifier: **0** symbol/metadata hits |
| 13 | [CrewScreens: developer relay help, added](../Slip/Screens/CrewScreens.swift#L421) | `Launch with --relay and --contract.`: **0** string hits |
| 14 | [NetworkSetup: launch parser, added](../Slip/Sealing/NetworkSetup.swift#L32) | `--relay`, `--contract`, `--relay-token`: **0** string/raw-byte hits; `fromLaunchArguments`: **0** symbol/metadata hits |

The 13 flags in guard 2 are `--screen`, `--preview`, `--slip-local-fixture`, `--appearance`, `--accessibility`, `--accessibility-max`, `--xl`, `--reduce-motion`, `--reduce-transparency`, `--contrast`, `--export-public-proof`, `--network-preview` and `--print-member-id`. The setup parser's `--relay`, `--contract`, `--relay-token` and the separate `--profile-footer` were also checked. All custom launch flags have zero raw-byte matches. The [root view's editor previews](../Slip/App/SlipRootView.swift#L79) have no `PreviewRegistry`, `makePreview` or `DeveloperToolsSupport` symbols in the executable. The ordinary pre-alpha display content remains; it is not a DEBUG navigation control.

### Production relay names are not absent

The literal broad-word requirement is **not satisfied**: `strings` reports 13 lines containing `relay`, and 13 lines containing `token` (20 occurrences). The approved [Release initialization](../Slip/App/SlipApp.swift#L80) still loads saved [relay configuration](../Slip/Sealing/NetworkSetup.swift#L12) and can construct the [network seal flow](../Slip/Sealing/NetworkSealAdapter.swift#L82). That leaves `slip.network.relayURL`, `slip.network.relayToken`, relay type/member names and the normal `Steward relay` label. Other token names include cancellation UUIDs and native dependency parser/type names. These names are not embedded credential values.

`localhost`, `127.0.0.1`, `steward.local`, the DEBUG relay flags and the word `Bearer` have zero string/raw-byte matches. The sole HTTP(S) byte match is a native `getrandom` diagnostic's documentation URL (`https://docs.rs/getrandom#nodejs-es-module-support`), not a configured relay endpoint. Credential-shape searches found no bearer values, JWT-shaped values, private-key headers or credential assignments. These searches do **not** prove the absence of runtime credentials or all possible secret encodings: the retained [relay client](../MidnightKit/Sources/MidnightKit/Network/StewardRelayClient.swift#L52) still constructs an Authorization bearer header from a configured token. Removing that feature would change the approved release scope and the [privacy declarations](app-store-privacy.md); it was not done as a binary-string cleanup. The witness `{choice, salt}` path was unchanged, and no relay request or proof export was performed during this audit.

## Bundle evidence

```sh
AUDIT_APP=/tmp/slip-release-audit/Build/Products/Release-iphonesimulator/Slip.app
shasum -a 256 "$AUDIT_APP/PrivacyInfo.xcprivacy"
git show 7f34ae9:Slip/Resources/PrivacyInfo.xcprivacy | shasum -a 256
plutil -p "$AUDIT_APP/Info.plist"
xcrun assetutil --info "$AUDIT_APP/Assets.car"
```

The bundled [privacy manifest](../Slip/Resources/PrivacyInfo.xcprivacy) is **1,960 bytes**, byte-identical to the committed file. Both SHA-256 values are:

```text
4e4ef0a2792cbffa3b1e55e63121ef92dab0f67edd5a8beef54628af9b96f0bd
```

It retains the approved User ID and Other Data Types declarations, linked for App Functionality with no tracking, plus the two required-reason API entries. This audit did not revise those owner-to-confirm [nutrition-label answers](app-store-privacy.md).

| Built Info.plist key | Value | Configuration source |
|---|---|---|
| `CFBundleDisplayName` | `Slip` | `INFOPLIST_KEY_CFBundleDisplayName` |
| `LSApplicationCategoryType` | `public.app-category.social-networking` | `INFOPLIST_KEY_LSApplicationCategoryType` |
| `MinimumOSVersion` | `17.0` | `IPHONEOS_DEPLOYMENT_TARGET` — metadata, not verified minimum support |
| `CFBundleIdentifier` | `com.sailesh.slip` | `PRODUCT_BUNDLE_IDENTIFIER` |
| `CFBundleShortVersionString` | `0.1.0` | `MARKETING_VERSION`, expanded through [Info.plist](../Slip/Resources/Info.plist) |
| `CFBundleVersion` | `1` | `CURRENT_PROJECT_VERSION`, expanded through Info.plist |
| `UIDeviceFamily` | `[1]` | App target `TARGETED_DEVICE_FAMILY` |

All seven match [project.yml](../project.yml). The bundle contains **34 regular files, 48,600,898 logical bytes (46.35 MiB)**; `du -sk` reports 47,536 KiB allocated. Neither number is an App Store compressed download size.

| Largest 10 bundle files | Bytes |
|---|---:|
| `Slip` | 21,306,648 |
| `ProofArtifacts/keys/reveal.prover` | 5,242,796 |
| `ProofArtifacts/keys/sealPick.prover` | 5,242,026 |
| `ProofArtifacts/params/bls_midnight_2p14` | 3,146,116 |
| `ProofArtifacts/keys/createSlip.prover` | 2,822,229 |
| `ProofArtifacts/keys/enrollMember.prover` | 2,820,553 |
| `ProofArtifacts/keys/settle.prover` | 2,820,445 |
| `ProofArtifacts/keys/dispute.prover` | 2,820,376 |
| `ProofArtifacts/params/bls_midnight_2p13` | 1,573,252 |
| `JetBrainsMono-Regular.ttf` | 270,224 |

All 20 proving resources—six ZKIR files, six prover/verifier pairs and two parameters—match their configured input SHA-256 values. They are copied by the [project's proving-artifact build phase](../project.yml); its `outputFiles` list is incremental-build bookkeeping, not the full resource inventory. Other resources are the expected runtime JavaScript, font/license, asset catalog, icons and bundle metadata. No unexpected file exceeds 1 MiB.

There are **zero** snapshot-reference filenames, fixture or handoff paths, test bundles, Swift source files or logs in the bundle. `Assets.car` contains only named `AppIcon` assets. The two standalone PNGs are generated app icons, including a small iPad-named rendition produced from the universal icon catalog even with `actool --target-device iphone`; the actual device-family declaration is `[1]`. No snapshot or design board PNG was copied or re-recorded.

## App tests and gates

The full Release test attempt used separate derived data so its instrumented build could not replace the inspected app:

```sh
xcodebuild -scheme Slip -configuration Release -sdk iphonesimulator \
  -destination id=670DB62C-18B0-49C0-A910-FD8C45E4B951 \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/slip-release-tests \
  -parallel-testing-enabled NO test
```

It exited 65 with **zero tests executed**. The observed diagnostic is at [AppModelCoverageTests.swift:3](../SlipTests/AppModelCoverageTests.swift#L3), `@testable import Slip`:

```text
error: Unable to resolve Swift module dependency to a compatible module: 'Slip'
note: ... module built without '-enable-testing'
Testing cancelled because the build failed.
** TEST FAILED **
```

The build environment reported `ENABLE_TESTABILITY=NO`. All 19 suite files import Slip with `@testable`; some also exercise DEBUG-only hooks. Testability was not enabled in Release and production APIs were not made public to accommodate the harness. [CONTRIBUTING](../CONTRIBUTING.md#verify-the-change) now names Debug explicitly.

The final Debug command was:

```sh
xcodebuild -scheme Slip -configuration Debug \
  -destination 'platform=iOS Simulator,id=670DB62C-18B0-49C0-A910-FD8C45E4B951' \
  -derivedDataPath /tmp/slip-luma-build -parallel-testing-enabled NO test
scripts/design-gate.sh Slip/
sh scripts/freshness-gate.sh --no-network
git diff --check
```

```text
✔ Test run with 96 tests in 19 suites passed after 111.335 seconds.
** TEST SUCCEEDED **
design gate: PASS
freshness gate: PASS (local checks only)
```

Each fix had its own successful full Debug gate and normal pre-commit hook. All 120 snapshot references stayed unchanged. Signing, device archive validation, external relay acceptance and older-runtime support are not established by these checks. The retained production relay names are explicitly disclosed above; this is not a claim that every occurrence of `relay` or `token` has disappeared.

# App Store privacy draft

Reviewed 2026-09-06. **Owner to confirm before TestFlight or App Store submission.**
This draft describes the current local demonstration and the optional experimental
relay separately. It is not a submitted App Store Connect answer or a privacy policy.
The manifest declares the available relay path: **User ID** and **Other Data Types**,
both linked to the user, used for App Functionality, and not used for tracking.
The default local demonstration alone does not justify “Data Not Collected” for this build.

## Disclosure ledger and nutrition-label answers

The witness `{choice, salt}` never leaves the device. The device secret, private
runtime transcript and proof-input JSON remain in the device's execution/proving
boundary. A zero-knowledge proof can demonstrate a valid commitment without exposing
the witness. That privacy invariant does not itself determine whether the public
data sent to a relay is collected under Apple's definitions. Sources:
[architecture disclosure ledger](../.claude/docs/architecture.md#disclosure-ledger),
[local service](../Slip/Sealing/LocalSealingService.swift),
[network service](../Slip/Sealing/NetworkSealingService.swift), and
[relay HTTP boundary](../MidnightKit/Sources/MidnightKit/Network/StewardRelayClient.swift).

| Data or behavior | Default local demonstration | Optional relay path | Draft owner answer |
|---|---|---|---|
| Witness, device secret, private transcript, proof-input JSON | Session memory; no submission | Local execution and proving; never in relay request | Not collected by these app paths. The network identity secret is kept in the device-only Keychain. |
| Question, ordered sides, crew name, dates, local round identity | Local draft and session state | This seal-only path does not upload the draft text; it uses existing contract state | Not collected by the current local draft flow. Reassess when connected creation or crew features ship. |
| Commitment, proof and public transaction transcript | Public receipt remains local | Proved transaction goes to the authenticated relay, then finalized transaction goes to the node and indexed public state | **Other Data Types**, linked to the user, for App Functionality, no tracking. Public commitments and proof transcripts are not exempt from collection disclosure. |
| Public member ID, derived from the device secret | No outbound request | Stable device member identifier sent to the authenticated relay; identifies the enrolled member in public contract execution across network sessions | **User ID**, linked to the user, for App Functionality, no tracking. Hashing a stable identity does not establish that it is anonymous. |
| Relay URL, contract address and bearer credential | Absent on a fresh install | App-only defaults; credential authorizes requests, contract address selects context | Check retention and operator practices before relying on request-only processing. |
| Execution/key-load/proving durations and byte counts | Displayed in the local receipt | Displayed in the network receipt; not uploaded as performance telemetry by the app | Not collected as diagnostics by these app paths. |
| Advertising, analytics, tracking domains | No advertising or analytics integration | No advertising or analytics integration | Tracking: **No**. Tracking domains: none. |
| Contact details, contacts, location, photos, audio, health, purchases | No collection API or upload flow | No collection API or upload flow | No collection identified in the audited paths. |

Apple treats data transmitted off-device and retained beyond servicing the real-time
request as collection, including collection solely for app functionality. The relay
path retains member identifiers, commitments and public proof/transaction records;
retention is not limited to the initiating app session. A commitment being public is
not an exemption. On-device-only processing is excluded, while derived data sent
off-device must be assessed separately. The chosen declaration therefore covers the
stable member identifier as User ID and the retained commitment plus public proof
transcript as Other Data Types. The witness `{choice, salt}` never leaves the device
and is **not listed** as collected data. “Proof transcript” here means the public
transaction transcript, never the private runtime transcript or proof-input JSON.
This classification follows the audited boundary and Apple's
[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/);
it is a draft for owner confirmation, not an Apple review decision.

The [relay coordinator](../scripts/steward-relay.mjs#L437) retains pending records
and caches completed submission identities/results. Completed records become eligible
for pruning after 65 minutes; cleanup runs on later submissions, and pending records
can remain longer. Successful transactions become public node/indexer state. The
[Release launch path](../Slip/App/SlipApp.swift#L80) still loads saved relay setup,
even though a fresh installation has none. The current path therefore needs more
than the fact that the raw pick is concealed to justify no collection.
Review the [tracked relay evidence](phase7-sources.md#boundary-and-protocol-decisions)
and [transaction boundary evidence](phase6-sources.md#official-conclusions).

| App Store Connect question | Draft answer awaiting owner confirmation |
|---|---|
| Does this app collect data? | **Yes.** The available relay path transmits and retains a stable member identifier and public commitment/proof records. The default local demonstration does not submit its receipts. |
| Is data used for tracking? | **No**, based on the audited code. |
| What purpose applies to collected relay data? | **App Functionality** for both entries; no advertising or analytics purpose. |
| Is collected relay data linked to the user? | **Yes** for both entries, through the persistent pseudonymous member identifier and associated records. |
| Which categories apply to relay records? | **User ID** for the stable device member identifier; **Other Data Types** for the retained commitment and public proof transcript. |

The [app manifest](../Slip/Resources/PrivacyInfo.xcprivacy) contains exactly these
two `NSPrivacyCollectedDataTypes` entries:

| `NSPrivacyCollectedDataType` | `NSPrivacyCollectedDataTypeLinked` | `NSPrivacyCollectedDataTypeTracking` | `NSPrivacyCollectedDataTypePurposes` |
|---|---|---|---|
| `NSPrivacyCollectedDataTypeUserID` | `true` | `false` | `[NSPrivacyCollectedDataTypePurposeAppFunctionality]` |
| `NSPrivacyCollectedDataTypeOtherDataTypes` | `true` | `false` | `[NSPrivacyCollectedDataTypePurposeAppFunctionality]` |

If a future release build **compiles the relay path out**, delete the
`NSPrivacyCollectedDataTypeUserID` and `NSPrivacyCollectedDataTypeOtherDataTypes`
entries, leaving `NSPrivacyCollectedDataTypes` empty after verifying no other
off-device collection path remains. Merely leaving relay setup empty on a fresh
install is insufficient. Update the matching App Store Connect answers and re-audit
the required-reason API entries against the code that remains in that release.

The owner must confirm the actual distribution configuration, relay/node/indexer
retention and linkage, the final manifest's collection entries, the matching App Store
Connect answers, and a public privacy-policy URL. Apple requires disclosure of
collection across available app experiences, not only the default screen. Its
[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
also distinguishes collection by Apple from the developer's own collection.

## Required-reason API audit

Apple's required-reason API declaration is separate from the nutrition-label
collection questions. The current source and linked simulator executable establish
the following two API categories. The reasons were read from Apple's current
[API category and reason list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
including its structured documentation data, on 2026-09-06.

| Category and verified reason | Code evidence | Purpose matching Apple's allowed reason |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` — `CA92.1` | [NetworkSetup.swift, lines 16–29](../Slip/Sealing/NetworkSetup.swift#L16): `string(forKey:)`, `set`, `removeObject` | Read and write this app's relay configuration in its own defaults domain; no other app's defaults or shared group suite. |
| `NSPrivacyAccessedAPICategoryFileTimestamp` — `C617.1` | [ProofArtifacts.swift, lines 43–45](../MidnightKit/Sources/MidnightKit/ProofArtifacts.swift#L43), [Prover.swift, line 169](../MidnightKit/Sources/MidnightKit/Prover.swift#L169), [LocalSealingService.swift, lines 654–669](../Slip/Sealing/LocalSealingService.swift#L654), and native prover file reads described below | Read metadata/size for files in the app's containers while locating and loading bundled proving artifacts. The native standard-library read consults file metadata before allocating its buffer. |

[DebugPublicProofExport.swift, lines 22–37](../Slip/Sealing/DebugPublicProofExport.swift#L22)
also locates/removes the app's public diagnostic export in its Documents container.
That launch-flag-only path is excluded from Release builds; it does not export the
witness. The release-required file category is supported independently by proving
artifact reads.

The native archive audit was read-only. Its source is external to this repository,
as documented in [MidnightKit/Package.swift](../MidnightKit/Package.swift) and
[sync-prover.sh](../scripts/sync-prover.sh). Local validation found:

- `slip-prove-ffi/src/lib.rs:185,191` reads the circuit and proving key;
  `src/tx_assembly.rs:40,53,84` reads circuit, proving-key and verifier-key files.
- The locally installed Rust standard library's `std/src/fs.rs:340–345` calls
  `file.metadata()` in `std::fs::read`; `std/src/sys/fs/unix.rs:1394–1410` uses
  `fstat` for that metadata. These external line references record the inspected
  local source, not a tracked dependency guarantee.
- `nm -u` found `_fstat` and `_fstatat` in the vendored archive. The linked Debug
  app library imports `_stat`, `_fstat`, `_fstatat` and `_lstat`.
- The vendored archive and the external simulator build archive had identical
  SHA-256: `7dafa05ee72c13a4a8151d1f437e6f7e9acbb3019f9cf076630421e3bec5c5e0`.

Repeat the symbol/source audit when the native archive or toolchain changes. The
independently built physical-device archive also needs this check before submission.

## Categories excluded by the current audit

| Category | Evidence and decision |
|---|---|
| System boot time | Apple's current list names `ProcessInfo.systemUptime` and `mach_absolute_time()`. Neither appears in app/kit source or the inspected imported symbols. [LocalSealingService.swift, lines 699–701](../Slip/Sealing/LocalSealingService.swift#L699), [NetworkSealingService.swift, lines 57–63](../Slip/Sealing/NetworkSealingService.swift#L57) and [Prover.swift, lines 173–187](../MidnightKit/Sources/MidnightKit/Prover.swift#L173) use `ContinuousClock`; native timing uses Rust `Instant`. The inspected imports use `clock_gettime`/`clock_gettime_nsec_np`, which are absent from Apple's current required-reason list. Do not add a boot-time declaration solely because elapsed durations are measured. |
| Disk space | No listed capacity-property access or `statfs`, `fstatfs`, `statvfs`, `fstatvfs`, or `getattrlist` import was found. File size metadata above is not a free-disk-capacity query. |
| Active keyboards | No `activeInputModes` access was found. Showing the standard keyboard for a form does not itself establish an active-keyboard-list query. |

## Apple documentation provenance and packaging

The requested `/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/`
path was absent on this machine. The selected toolchain is `Xcode-beta.app`; its
corresponding `AdditionalDocumentation/` directory was inspected first and has no
required-reason code list. The installed iPhoneOS SDK's
`Foundation.framework/Headers/NSFileManager.h:1285,1323` points to Apple's policy
without listing reasons. Xcode's local `App Privacy.xctemplate` supplies the privacy
manifest template.

The audit then read Apple's current
[required-reason guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
and [category list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
The category page's Markdown export omits its possible-value definitions; its
[official structured documentation](https://developer.apple.com/tutorials/data/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype.json)
contains the API lists and approved reasons used here.

MidnightKit is first-party code statically linked into the app. The app bundle must
contain the manifest for its executable; future independent SDK distribution needs
its own manifest rather than relying on a consuming app's declarations. Follow
Apple's [privacy manifest packaging guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
and verify the actual built bundle, not just the source plist.

## Verified Debug bundle

On 2026-09-06, XcodeGen placed the manifest exactly once in Copy Bundle Resources.
A fresh Debug rebuild on iPhone 17 Pro / iOS 27 included
`Slip.app/PrivacyInfo.xcprivacy`. The source, built file and file extracted from a
ZIP of that built app were byte-identical: **1,960 bytes**, SHA-256:

```text
4e4ef0a2792cbffa3b1e55e63121ef92dab0f67edd5a8beef54628af9b96f0bd
```

The parsed bundle contains exactly the two collected-data entries and the two
required-reason entries documented above, with tracking disabled and no tracking
domains. Verification used the existing local native/proving inputs:

```sh
xcodegen generate
xcodebuild -scheme Slip \
  -destination 'platform=iOS Simulator,id=670DB62C-18B0-49C0-A910-FD8C45E4B951' \
  -derivedDataPath /tmp/slip-luma-build \
  -resultBundlePath /tmp/slip-privacy-final-20260906.xcresult test
plutil -p /tmp/slip-luma-build/Build/Products/Debug-iphonesimulator/Slip.app/PrivacyInfo.xcprivacy
scripts/design-gate.sh Slip/
sh scripts/freshness-gate.sh --no-network
```

```text
✔ Test run with 96 tests in 19 suites passed after 114.134 seconds.
** TEST SUCCEEDED **
design gate: PASS
freshness gate: PASS (local checks only)
```

The 120 existing snapshot references passed without re-recording. This is Debug
simulator and bundle evidence; the owner still confirms the actual signed device
archive and App Store Connect answers before submission.

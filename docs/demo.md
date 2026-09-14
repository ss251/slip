# Three-minute Wave 1 demo

For the 2026-09-16 submission. Rehearsed on 2026-09-06 with the accepted app at `8781a3d`, iPhone 17 Pro / iOS 27 simulator, UDID `670DB62C-18B0-49C0-A910-FD8C45E4B951`.

This walkthrough creates a **real, single-player local round** and runs native proofs. Use the disposable built-in question, “Will it rain on Saturday?”, with Yes/No. It sends no invites or transactions. The README phone strip shows the intended crew experience; this run deliberately displays “On-device sample · no shared round.” A shared deadline creates an opening window; connected crews and simultaneous arrivals are not demonstrated here.

## Prepare before the timer

Use the [README build prerequisites](../README.md#build-and-test), existing verified native archive, generated contract artifacts and staged public parameters. Xcode, XcodeGen and `idb` with a working simulator companion must already be installed. Keep other capture/test jobs off this simulator during the walkthrough.

From the repository root, use the rehearsed simulator below. On another machine, find an available iPhone 17 Pro with `xcrun simctl list devices available` and replace `SLIP_DEMO_UDID`; the coordinates still require the stated screen size and runtime.

```sh
export SLIP_DEMO_UDID=670DB62C-18B0-49C0-A910-FD8C45E4B951
export SLIP_DEMO_BUILD=/tmp/slip-luma-build

# An already-booted device is fine; bootstatus must succeed.
xcrun simctl boot "$SLIP_DEMO_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SLIP_DEMO_UDID" -b
xcodebuild -scheme Slip -destination "platform=iOS Simulator,id=$SLIP_DEMO_UDID" \
  -derivedDataPath "$SLIP_DEMO_BUILD" build
xcrun simctl install "$SLIP_DEMO_UDID" \
  "$SLIP_DEMO_BUILD/Build/Products/Debug-iphonesimulator/Slip.app"
xcrun simctl ui "$SLIP_DEMO_UDID" appearance light
xcrun simctl ui "$SLIP_DEMO_UDID" content_size large
xcrun simctl status_bar "$SLIP_DEMO_UDID" override --time '9:41' \
  --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl terminate "$SLIP_DEMO_UDID" com.sailesh.slip 2>/dev/null || true
xcrun simctl launch "$SLIP_DEMO_UDID" com.sailesh.slip \
  --screen 02-new-slip --appearance light \
  -slip.network.relayURL '' -slip.network.contractAddress ''
sleep 4
```

The last two arguments override saved relay defaults **only for this process**; they do not erase the owner's configuration. There are no `--preview`, fixture, relay credentials or proof-export flags. Confirm “local proof only” at the seal step and “Stays here in this local build” on the ticket.

Coordinates below are **402×874 simulator points**, with Dynamic Type set to `large`; screenshots are 1206×2622 pixels. On another size, inspect `idb ui describe-all --udid "$SLIP_DEMO_UDID" --json` and remeasure. Start the timer with New slip visible. Keep the app active while proving, and preserve this one app process through the entire loop: terminating it loses the local round.

## 0:00–0:20 — New slip

Show the question, Yes/No and the future Friday schedule. Keep these defaults for reproducible taps. Explain: “Everyone commits to a pick before opening. This sample is local; no invitations are sent.”

At 0:20, create it, acknowledge the notice, then enter sealing:

```sh
idb ui tap 201 769 --udid "$SLIP_DEMO_UDID"  # Create slip
sleep 1
idb ui tap 201 507 --udid "$SLIP_DEMO_UDID"  # OK: local preview / no invites
sleep 1
idb ui tap 201 797 --udid "$SLIP_DEMO_UDID"  # Seal a local pick
sleep 1
```

## 0:20–0:50 — Seal with the hold

The default pick is Yes. Show the phone glyph and “local proof only.” At about 0:35, hold the red control; an ordinary tap does not seal:

```sh
idb ui tap 201 769 --duration 1.4 --udid "$SLIP_DEMO_UDID"
sleep 8
```

The gesture crosses the app's 1.2-second hold threshold. Wait for the ticket; the app locally proves enrollment, round creation and sealing. Do not relaunch or tap through a proving/error state. If proving takes longer, let it finish and shorten narration rather than treating a timeout as success.

## 0:50–1:15 — Sealed ticket and timing

Expected: “Sealed on this iPhone,” concealed dots, wax seal, “Stays here in this local build.” The UI's device wording does not make this a physical-phone measurement.

**Point at the live `Proof time` line**, then scroll to show `Key load`, `Proof size` and the local-only explanation:

```sh
idb ui swipe 201 680 201 420 --duration 0.5 --udid "$SLIP_DEMO_UDID"
sleep 1
```

Say: “That is this run's native seal-proof time. The proof is 4,480 bytes. The pick and salt are not exported.” The 2026-09-06 rehearsal displayed **1.028 s** on that line. It is one observation, not a latency promise or total tap-to-ticket time. Enrollment/creation and preparation are separate costs. This local demo retains even the proof on device; the later verified opening deliberately makes the choice public while the salt and device secret stay private.

## 1:15–1:35 — Sealed room

```sh
idb ui tap 201 741 --udid "$SLIP_DEMO_UDID"  # Done on the ticket
sleep 1
```

Show the single You row and the local-round disclosure. Explain the on-screen sample-clock action: it advances this round to its opening window without changing the device clock or opening a shared round early.

## 1:35–2:00 — Opening

```sh
idb ui tap 201 797 --udid "$SLIP_DEMO_UDID"  # Open this local sample
sleep 5
```

Expected: “Your pick opened.” and “Your opened pick matched its seal.” The original stored pick is proved against its commitment; no new pick is supplied through the command. The opening uses the rare row flip, or its crossfade if Reduce Motion is enabled. Explain: “Opening establishes what was sealed. It does not decide what happened.”

## 2:00–2:20 — Call the outcome

```sh
idb ui tap 201 797 --udid "$SLIP_DEMO_UDID"  # Call this local round
sleep 1
idb ui tap 107 408 --udid "$SLIP_DEMO_UDID"  # Yes outcome
# At about 2:10:
idb ui tap 201 797 --udid "$SLIP_DEMO_UDID"  # Call it: Yes
sleep 5
```

Show “What happened?” before confirming. The call advances the sample clock past the opening window and proves settlement. Say: “The result is called after opening; the two are separate operations.”

## 2:20–2:40 — Verdict

Expected: “The call is in.”, Yes with one pick, and You at +1. Explain that this is a score for the one proved local round, not connected season history. The separate Challenge action can void it; leave that outside this three-minute sequence.

## 2:40–3:00 — Standings and evidence

```sh
idb ui tap 201 731 --udid "$SLIP_DEMO_UDID"  # See local standings
sleep 1
# After showing the score, scroll to the proof receipts:
idb ui swipe 280 680 280 280 --duration 0.5 --udid "$SLIP_DEMO_UDID"
idb ui swipe 280 680 280 280 --duration 0.5 --udid "$SLIP_DEMO_UDID"
sleep 1
```

Expected: “Local standings,” the one-player score, and a “Proved on this device” panel. Its rows cover Add the local player, Create the round, Seal the pick, Open the pick and Call the outcome. Each separates Prepare, Key and Proof timing. Finish on “Measured locally. These proofs have not been submitted to a network.”

## Where the on-chain evidence lives

Keep these documents ready in the host editor; do not start a relay during the timed walkthrough:

- [Phase 6 — bound native acceptance](phase6-sources.md#bound-native-acceptance): native transaction assembly/proving, node `SucceedEntirely` at blocks 1251, 1772 and 1923, and exact indexed commitment equality. These were host-referee runs.
- [Phase 7 — evidence matrix](phase7-sources.md#evidence-matrix): the post-fix authenticated host → relay → undeployed devnet run produced a 5,238-byte transaction in 1,256 ms, reached `SucceedEntirely` at block 3672, and records its public transaction ID and exact indexed commitment. The matrix separately identifies simulator submission and physical-phone stub-relay tests.

These are dated local-devnet records, not permanent public-network deployments or proof that this walkthrough posted a transaction. `Submitted` means node/pool acceptance; use the recorded node outcome and independent indexed commitment when discussing chain acceptance. Host tooling proved setup calls and the separate wallet DUST transaction; Slip's seal proof was native.

## Owner-only extensions before submission

| Item | Owner action / required evidence |
|---|---|
| Physical phone and relay | Authorize signing/pairing and the authenticated phone → trusted developer relay → undeployed devnet run with a fresh eligible member/round. Record the physical phone/build/runtime, public timings, transaction ID, node outcome and independent exact commitment match from the same run. Earlier phone local proofs and stub-relay tests do not close this step. Keep witness/transcripts and relay credentials out of screenshots and logs. |
| Device UX and TestFlight | Verify hold, haptics, privacy cover, Dynamic Type and Reduce Motion on a physical phone; validate the supported runtime, signing/archive and distribution configuration; then upload through the owner's App Store Connect/TestFlight account. Simulator success is not archive or device evidence. |
| Security reporting | Done 2026-09-14: [SECURITY.md](../SECURITY.md) names a monitored private reporting address. |
| Public repository and submission | Review release contents/history and private scratch, resolve build-input distribution and outstanding owner checks, then explicitly approve the repository visibility flip and the Wave 1 submission. No push, public flip, TestFlight upload or relay operation is part of this simulator runbook. |

Use the normal [contribution gates](../CONTRIBUTING.md): design gate, freshness gate (`--no-network` for local checks), full app suite with its passed-count line, and the normal handoff-freshness pre-commit hook. UI defects require their own focused fix and only affected snapshot/board updates. Screenshots and rehearsal notes are local evidence, not new canonical boards or network receipts.

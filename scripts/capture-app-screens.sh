#!/bin/sh
# Capture synthetic preview screens only; never snapshot a live private pick.
# Usage: sh scripts/capture-app-screens.sh OUTPUT [SCREEN ...]
# Set SLIP_CAPTURE_VARIANT=accessibility for large text + reduced motion,
# reduced transparency and increased contrast; accessibility-max selects AX5.
# All captures use synthetic data.
set -eu
OUTPUT=${1:?Provide an evidence output directory}
shift
mkdir -p "$OUTPUT"
if [ "$#" -eq 0 ]; then
  set -- 00-how-slip-works 01-home 01b-home-first-run 02-new-slip 02b-invite \
    03-seal-your-pick 03b-sealing 04-sealed-ticket 05-sealed-room 06a-opening \
    06b-verdict 07-standings 08-crews 08b-crew-detail 09-you 10-settle \
    10b-awaiting-the-call 10c-challenge 10d-voided 11a-proof-failed \
    11b-sealed-posting-later 11c-already-sealed 11d-verdict-sat-out 11e-reveal-mismatch
fi
xcrun simctl status_bar booted override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
FIRST_CAPTURE=1
for THEME in light dark; do
  xcrun simctl ui booted appearance "$THEME"
  for SCREEN in "$@"; do
    xcrun simctl terminate booted com.sailesh.slip >/dev/null 2>&1 || true
    if [ "${SLIP_CAPTURE_VARIANT:-standard}" = accessibility-max ]; then
      xcrun simctl launch booted com.sailesh.slip --screen "$SCREEN" --preview --appearance "$THEME" --accessibility-max --reduce-motion --reduce-transparency --contrast >/dev/null
    elif [ "${SLIP_CAPTURE_VARIANT:-standard}" = accessibility ]; then
      xcrun simctl launch booted com.sailesh.slip --screen "$SCREEN" --preview --appearance "$THEME" --accessibility --reduce-motion --reduce-transparency --contrast >/dev/null
    else
      xcrun simctl launch booted com.sailesh.slip --screen "$SCREEN" --preview --appearance "$THEME" >/dev/null
    fi
    if [ "$FIRST_CAPTURE" -eq 1 ]; then
      sleep 10
      FIRST_CAPTURE=0
    else
      sleep 4
    fi
    xcrun simctl io booted screenshot "$OUTPUT/$SCREEN-$THEME.png" 2>&1
  done
done

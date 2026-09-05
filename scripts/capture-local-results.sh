#!/bin/sh
# DEBUG synthetic public results only. No circuits run and no witness flags exist.
# Usage: sh scripts/capture-local-results.sh OUTPUT
# Set SLIP_CAPTURE_VARIANT=accessibility-max for AX5 + all reduced-effects paths.
set -eu
SLIP_CAPTURE_OUTPUT=${1:?Provide an evidence output directory}
mkdir -p "$SLIP_CAPTURE_OUTPUT"
xcrun simctl status_bar booted override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
for SLIP_CAPTURE_THEME in light dark; do
  xcrun simctl ui booted appearance "$SLIP_CAPTURE_THEME"
  for SLIP_CAPTURE_CASE in \
    sealed:05-sealed-room revealed:06a-opening revealed:10-settle \
    settled-won:06b-verdict settled-lost:06b-verdict \
    settled-won:07-standings settled-lost:07-standings \
    settled-won:10c-challenge disputed:10d-voided \
    mismatch:11e-reveal-mismatch parametersMissing:06a-opening sealed:10b-awaiting-the-call; do
    SLIP_CAPTURE_FIXTURE=${SLIP_CAPTURE_CASE%%:*}
    SLIP_CAPTURE_SCREEN=${SLIP_CAPTURE_CASE#*:}
    xcrun simctl terminate booted com.sailesh.slip >/dev/null 2>&1 || true
    if [ "${SLIP_CAPTURE_VARIANT:-standard}" = accessibility-max ]; then
      xcrun simctl launch booted com.sailesh.slip --slip-local-fixture "$SLIP_CAPTURE_FIXTURE" --screen "$SLIP_CAPTURE_SCREEN" --appearance "$SLIP_CAPTURE_THEME" --accessibility-max --reduce-motion --reduce-transparency --contrast >/dev/null
    else
      xcrun simctl launch booted com.sailesh.slip --slip-local-fixture "$SLIP_CAPTURE_FIXTURE" --screen "$SLIP_CAPTURE_SCREEN" --appearance "$SLIP_CAPTURE_THEME" >/dev/null
    fi
    sleep 4
    xcrun simctl io booted screenshot "$SLIP_CAPTURE_OUTPUT/$SLIP_CAPTURE_SCREEN-$SLIP_CAPTURE_FIXTURE-$SLIP_CAPTURE_THEME.png"
  done
done

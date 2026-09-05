#!/bin/sh
# Stage existing public SRS files for the app without modifying contracts or MidnightKit.
# No network fallback. Hashes: ledger-8/base-crypto/src/data_provider.rs EXPECTED_DATA.
set -eu
SOURCE=${1:?Usage: sh scripts/prepare-app-params.sh /path/to/existing/params}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEST="$ROOT/.build/app-proof-params"
check() {
  actual=$(shasum -a 256 "$SOURCE/$1" | cut -d ' ' -f 1)
  [ "$actual" = "$2" ] || { echo "public parameter checksum mismatch: $1" >&2; exit 1; }
}
check bls_midnight_2p13 d3324910969c4cc54143b8045b649e5c3a4bd5fb7b8f85fe1b770f640ce1c803
check bls_midnight_2p14 fc253016885ec830e97808c9ec920bb5cab5c21af590380a6cb5eb0538e2b244
mkdir -p "$DEST"
cp "$SOURCE/bls_midnight_2p13" "$DEST/"
cp "$SOURCE/bls_midnight_2p14" "$DEST/"
echo 'app parameters: PASS (k13 + k14, SHA-256 verified; no network)'

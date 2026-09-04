#!/bin/sh
# Copies the built Rust prover archive into MidnightKit/Vendor/.
#
# The Rust source lives outside this repo (external volume, with the rest of the
# spike) and stays there deliberately: the archives are ~60 MB per architecture and
# rebuild from source. Vendor/ is gitignored.
#
# Toolchain trap this script exists to survive: Homebrew's rustc is new enough for
# the ledger dependency tree but ships NO iOS targets, while rustup's may be too old
# for the tree. The error is "can't find crate for `core`", which blames neither.
# Always build through rustup's toolchain.
set -eu
FFI="${SLIP_PROVER_SRC:-$HOME/Developer/midnight-ios-spike/slip-prove-ffi}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/MidnightKit/Vendor"
TARGET="${1:-aarch64-apple-ios-sim}"   # tests + CI link the simulator slice; pass aarch64-apple-ios for a device build

[ -d "$FFI" ] || { echo "prover source not found at $FFI (set SLIP_PROVER_SRC)"; exit 1; }
mkdir -p "$DEST"

echo "building slip-prove-ffi for $TARGET…"
( cd "$FFI" && PATH="$HOME/.cargo/bin:$PATH" cargo build --release --target "$TARGET" )

SRC="$FFI/target/$TARGET/release/libslip_prove_ffi.a"
[ -f "$SRC" ] || { echo "archive not produced at $SRC"; exit 1; }
cp "$SRC" "$DEST/libslip_prove_ffi.a"
cp "$FFI/include/slip_prove_ffi.h" "$(dirname "$DEST")/Sources/CSlipProve/include/"
echo "vendored $(du -h "$DEST/libslip_prove_ffi.a" | cut -f1) for $TARGET -> MidnightKit/Vendor/"

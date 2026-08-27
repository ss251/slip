#!/bin/sh
# Slip design gate — mechanical enforcement of .claude/docs/design.md.
# Usage: scripts/design-gate.sh [src-dir]   (exit 0 pass / 1 fail)
SRC="${1:-Slip}"
[ -d "$SRC" ] || { echo "design gate: source dir '$SRC' not found (pre-scaffold?) — nothing to check"; exit 0; }
fail=0
say() { printf '  [%s] %s\n' "$1" "$2"; fail=1; }

# R1: color literals outside DesignTokens.swift
hits=$(grep -RnE 'Color\((red:|#colorLiteral|hex)|Color\("[#0-9a-fA-F]' "$SRC" --include='*.swift' | grep -v DesignTokens.swift)
[ -n "$hits" ] && say R1 "color literals outside DesignTokens.swift:
$hits"

# R2: raw font sizes outside the typography file
hits=$(grep -RnE '\.font\(\.system\(size:' "$SRC" --include='*.swift' | grep -v Typography.swift)
[ -n "$hits" ] && say R2 "raw .system(size:) outside Typography.swift:
$hits"

# R3: glass is chrome-only
hits=$(grep -Rnl '\.glassEffect' "$SRC" --include='*.swift' | grep -v '/Chrome/')
[ -n "$hits" ] && say R3 "glassEffect outside Chrome/:
$hits"

# R4: animation without reduce-motion awareness in the same file
for f in $(grep -RlE 'withAnimation|\.animation\(' "$SRC" --include='*.swift' 2>/dev/null); do
  grep -q 'accessibilityReduceMotion' "$f" || say R4 "$f animates without a reduceMotion guard"
done

# R5: sub-44pt explicit heights on tappables
hits=$(grep -RnE 'frame\((height|minHeight): ?(1?[0-9]|2[0-9]|3[0-9]|4[0-3])([,.)])' "$SRC" --include='*.swift' | grep -iE 'button|tap|chip|pill')
[ -n "$hits" ] && say R5 "explicit tappable height < 44pt:
$hits"

# R6: no easeIn
hits=$(grep -RnE '\.easeIn\b' "$SRC" --include='*.swift')
[ -n "$hits" ] && say R6 "easeIn found (use easeOut or a spring):
$hits"

# R7: witness never logged (privacy rule, mechanical slice)
hits=$(grep -RnE '(print|Logger|os_log|NSLog)\(.*(salt|witness|choice)' "$SRC" --include='*.swift')
[ -n "$hits" ] && say R7 "possible witness data in logging:
$hits"

if [ "$fail" -eq 0 ]; then echo "design gate: PASS"; else echo "design gate: FAIL"; fi
exit $fail

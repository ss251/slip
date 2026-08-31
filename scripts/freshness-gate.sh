#!/bin/sh
# Slip freshness gate — keeps the repo honest about a fast-moving toolchain.
#
# Split by consequence:
#   FAIL  = internal inconsistency we control and that is guaranteed-broken
#           (runtime pin != what our compiler emits, CI pin != local compiler,
#            pragma above the language version we actually have).
#   WARN  = the world moved (new compiler, new CLI, vendored skill behind
#           upstream). Not broken, so it must never block a push — but it must
#           be impossible to miss.
#
# Usage: scripts/freshness-gate.sh [--no-network]
# Exit 0 = no fatal drift. Exit 1 = fatal drift.
set -u
NO_NET=0
[ "${1:-}" = "--no-network" ] && NO_NET=1
fail=0
warned=0
FAIL() { printf '  [FAIL] %s\n' "$1"; fail=1; }
WARN() { printf '  [warn] %s\n' "$1"; warned=1; }
OK()   { printf '  [ ok ] %s\n' "$1"; }

command -v compact >/dev/null 2>&1 || { echo "freshness gate: 'compact' CLI not on PATH — skipping (see AGENTS.md Setup)"; exit 0; }

COMPILER=$(compact compile --version 2>/dev/null | tr -d '[:space:]')
LANGUAGE=$(compact compile --language-version 2>/dev/null | tr -d '[:space:]')
RUNTIME=$(compact compile -- --runtime-version 2>/dev/null | tr -d '[:space:]')
echo "freshness gate: compiler=$COMPILER language=$LANGUAGE runtime=$RUNTIME"

# --- FAIL 1: the runtime pin must be whatever OUR compiler emits, never npm 'latest',
# never a constant copied from a doc written against a different compiler.
for pj in package.json contracts/package.json MidnightKit/package.json; do
  [ -f "$pj" ] || continue
  PINNED=$(grep -oE '"@midnight-ntwrk/compact-runtime"[[:space:]]*:[[:space:]]*"[^"]+"' "$pj" 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/' | tr -d '^~')
  [ -z "$PINNED" ] && continue
  if [ -n "$RUNTIME" ] && [ "$PINNED" != "$RUNTIME" ]; then
    FAIL "$pj pins compact-runtime $PINNED but compiler $COMPILER emits code for $RUNTIME (the compiler decides, not npm) — repin to $RUNTIME"
  else
    OK "$pj compact-runtime pin matches compiler output ($RUNTIME)"
  fi
done

# --- FAIL 2: CI must build with the compiler we develop against.
if [ -f .github/workflows/ci.yml ]; then
  CI_PIN=$(grep -oE 'COMPACT_COMPILER_VERSION:[[:space:]]*"?[0-9][0-9.]*' .github/workflows/ci.yml | grep -oE '[0-9][0-9.]*$')
  if [ -n "$CI_PIN" ] && [ -n "$COMPILER" ] && [ "$CI_PIN" != "$COMPILER" ]; then
    FAIL "ci.yml pins compiler $CI_PIN but local toolchain is $COMPILER — CI would validate different code than you wrote"
  elif [ -n "$CI_PIN" ]; then
    OK "ci.yml compiler pin matches local ($COMPILER)"
  fi
fi

# --- FAIL 3: a pragma above the installed language version can never compile.
# A pragma below it is drift, not breakage -> warn.
if [ -d contracts ]; then
  for f in contracts/*.compact; do
    [ -f "$f" ] || continue
    P=$(grep -oE 'pragma[[:space:]]+language_version[[:space:]]*>=[[:space:]]*[0-9.]+' "$f" | grep -oE '[0-9.]+$')
    [ -z "$P" ] && { WARN "$f has no language_version pragma"; continue; }
    LOWEST=$(printf '%s\n%s\n' "$P" "$LANGUAGE" | sort -V | head -1)
    if [ "$LOWEST" != "$P" ]; then
      FAIL "$f requires language >= $P but installed language is $LANGUAGE"
    elif [ "$P" != "$LANGUAGE" ]; then
      WARN "$f pragma $P is below installed language $LANGUAGE — compiles, but re-verify the examples it was written from"
    else
      OK "$f pragma matches language $LANGUAGE"
    fi
  done
fi

# --- FAIL 4: docs must not advertise a stack we no longer run.
if [ -f AGENTS.md ] && [ -n "$COMPILER" ]; then
  grep -q "compiler $COMPILER" AGENTS.md 2>/dev/null \
    && OK "AGENTS.md documents the running compiler" \
    || FAIL "AGENTS.md does not mention compiler $COMPILER — update the verified-stack line when the toolchain moves"
fi

[ "$NO_NET" = "1" ] && { echo; [ "$fail" = "0" ] && echo "freshness gate: PASS (local checks only)" || echo "freshness gate: FAIL"; exit $fail; }

# --- WARN: the world moved. Network checks, never fatal.
UP=$(compact check 2>/dev/null | grep -oE 'Latest version available: [0-9.]+' | grep -oE '[0-9.]+$')
[ -n "$UP" ] && [ "$UP" != "$COMPILER" ] && WARN "compiler $COMPILER installed, $UP available — 'compact update' (language may move too; re-verify examples)"
compact self check 2>/dev/null | grep -qi "update available" && WARN "Compact CLI update available — 'compact self update'"

# vendored skills: compare by COMMIT against upstream, never by a version file
for s in .claude/skills/*/SOURCE.md; do
  [ -f "$s" ] || continue
  REPO=$(grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$s" | head -1)
  PIN=$(grep -oE 'commit \*\*?[0-9a-f]{7,40}' "$s" | grep -oE '[0-9a-f]{7,40}' | head -1)
  [ -z "$REPO" ] || [ -z "$PIN" ] && continue
  HEAD_SHA=$(git ls-remote "$REPO" HEAD 2>/dev/null | cut -f1)
  [ -z "$HEAD_SHA" ] && continue
  case "$HEAD_SHA" in
    "$PIN"*) OK "$(dirname "$s" | xargs basename) is at upstream HEAD" ;;
    *) WARN "$(dirname "$s" | xargs basename) pinned at $PIN, upstream HEAD is $(echo "$HEAD_SHA" | cut -c1-7) — re-vendor and re-read its LOCAL DELTA section" ;;
  esac
done

echo
if [ "$fail" = "0" ]; then
  [ "$warned" = "1" ] && echo "freshness gate: PASS (with staleness warnings above)" || echo "freshness gate: PASS"
else
  echo "freshness gate: FAIL — fix the [FAIL] lines above before pushing"
fi
exit $fail

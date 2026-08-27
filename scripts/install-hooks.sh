#!/bin/sh
# Wire the repo's gates into git (gates are hooks, not prose).
# Run once after cloning: sh scripts/install-hooks.sh
set -e
HOOK=".git/hooks/pre-push"
[ -d .git ] || { echo "run from the repo root of a git checkout"; exit 1; }
cat > "$HOOK" <<'EOF'
#!/bin/sh
# Slip pre-push gate: design/privacy gate + contract compile (when present).
set -e
sh scripts/design-gate.sh Slip
if [ -f contracts/slip.compact ]; then
  if command -v compact >/dev/null 2>&1; then
    # Exact invocation pinned in AGENTS.md §Commands once verified:
    compact compile contracts/slip.compact build/slip
  else
    echo "pre-push: contracts/ exists but 'compact' CLI not on PATH — refusing to push unverified contract" >&2
    exit 1
  fi
fi
EOF
chmod +x "$HOOK"
echo "installed $HOOK"

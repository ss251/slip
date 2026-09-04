#!/bin/sh
# Handoff gate — a living handoff/HANDOFF.md must be at least as fresh as the work.
#
# Claude usage is finite; another agent must be able to pick up mid-stream. So the
# handoff file is enforced by machinery, not remembered: as a Claude Code `Stop` hook
# (blocks the turn from ending while the handoff is staler than the changes) and as a
# git pre-commit hook (a commit boundary must refresh it). Same script, two callers.
#
# Stop-hook contract (docs/en/hooks): read JSON on stdin; if `stop_hook_active` is
# true we are already continuing because of this hook — never block again (Claude
# Code also caps at 8 consecutive blocks). To block: print
# {"decision":"block","reason":"..."} and exit 0. Silent exit 0 = allow.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HANDOFF="$ROOT/handoff/HANDOFF.md"
MODE="${1:-stop}"   # stop | pre-commit

newest_change() {
  # newest mtime among files git considers changed (tracked+untracked, excluding handoff/)
  ( cd "$ROOT" && git status --porcelain --untracked-files=all 2>/dev/null \
    | awk '{print $NF}' | grep -v '^handoff/' \
    | while IFS= read -r f; do [ -e "$f" ] && stat -f %m "$f"; done; \
    git log -1 --format=%ct 2>/dev/null ) | sort -n | tail -1
}

if [ "$MODE" = "stop" ]; then
  INPUT=$(cat 2>/dev/null || true)
  case "$INPUT" in *'"stop_hook_active": true'*|*'"stop_hook_active":true'*) exit 0 ;; esac
fi

if [ ! -f "$HANDOFF" ]; then
  MSG="handoff/HANDOFF.md does not exist. Create it (gitignored) with: current goal, state of each workstream, where artifacts live, exact commands that work, blockers, and next actions — so another agent can continue."
else
  H=$(stat -f %m "$HANDOFF"); N=$(newest_change); N=${N:-0}
  [ "$H" -ge "$N" ] && exit 0
  MSG="handoff/HANDOFF.md ($(date -r "$H" '+%H:%M:%S')) is older than your latest change ($(date -r "$N" '+%H:%M:%S')). Update it — state, what just changed, exact next steps and commands — before stopping. Claude usage is finite; the next agent starts from this file."
fi

if [ "$MODE" = "stop" ]; then
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$MSG" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"
  exit 0
else
  echo "pre-commit: $MSG" >&2; exit 1
fi

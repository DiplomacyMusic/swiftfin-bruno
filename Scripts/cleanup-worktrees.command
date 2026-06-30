#!/bin/bash
# cleanup-worktrees.command — double-click front door for cleanup-worktrees.sh.
#
# Double-clicking this in Finder opens Terminal and:
#   1. shows the DRY-RUN preview (merged/stale worktrees + orphaned DerivedData
#      it would reclaim, with sizes) — nothing is deleted yet;
#   2. asks you to confirm [y/N];
#   3. only on "y", runs the real deletion (--apply) against the SAME snapshot
#      you just saw (--no-fetch, so the preview and the apply can't drift).
#
# All the real logic lives in the sibling cleanup-worktrees.sh — this is just
# the friendly, safe-by-default front door. To run unattended/scripted, call
# cleanup-worktrees.sh directly (that's what the launchd job does).

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/cleanup-worktrees.sh"

pause_and_exit() {  # keep the Terminal window readable after a double-click
  echo
  printf 'Press any key to close this window… '
  read -r -n 1 _ </dev/tty 2>/dev/null || true
  echo
  exit "${1:-0}"
}

if [ ! -x "$SCRIPT" ]; then
  echo "!! Cannot find executable: $SCRIPT" >&2
  pause_and_exit 1
fi

echo "============================================================"
echo " Worktree + DerivedData cleanup"
echo " PREVIEW first — nothing is deleted until you confirm."
echo "============================================================"
echo
"$SCRIPT"   # dry-run (default)

echo
printf 'Proceed and DELETE everything listed above? [y/N] '
reply=""
read -r reply </dev/tty 2>/dev/null || true
case "$reply" in
  [yY] | [yY][eE][sS])
    echo
    echo "── Applying ──"
    "$SCRIPT" --apply --no-fetch
    ;;
  *)
    echo "Aborted — nothing deleted."
    ;;
esac

pause_and_exit 0

#!/bin/bash
#
# Pull the Bruno DEBUG perf-telemetry JSONL sessions off the booted tvOS simulator into the repo.
#
# The app (BrunoPerfLog) writes one session-<stamp>.jsonl per recording to its sandbox at
# Library/Caches/BrunoPerf/. This copies them into <repo>/PerfLogs/ (gitignored) so they can be
# inspected against a screen recording. Double-click it in Finder or run it from a shell.
#
set -euo pipefail

BUNDLE_ID="org.jellyfin.swiftfin"

# Repo root = parent of this script's Scripts/ dir.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$REPO_ROOT/PerfLogs"

echo "Bruno perf-log pull"
echo "  bundle: $BUNDLE_ID"

# Resolve the booted sim's data container for the app.
CONTAINER=""
if CONTAINER="$(xcrun simctl get_app_container booted "$BUNDLE_ID" data 2>/dev/null)"; then
    :
else
    echo "  ! No booted simulator with $BUNDLE_ID installed."
    echo "    Boot a tvOS sim and run the app once, then retry."
    exit 0
fi

SRC="$CONTAINER/Library/Caches/BrunoPerf"
if [[ ! -d "$SRC" ]]; then
    echo "  ! No perf logs found at:"
    echo "    $SRC"
    echo "    Enable Settings → 'Perf logging → disk' and record a session first."
    exit 0
fi

shopt -s nullglob
LOGS=("$SRC"/*.jsonl)
if [[ ${#LOGS[@]} -eq 0 ]]; then
    echo "  ! BrunoPerf dir exists but holds no .jsonl sessions yet."
    exit 0
fi

mkdir -p "$DEST"
echo "  copying ${#LOGS[@]} session(s) → $DEST"
for f in "${LOGS[@]}"; do
    cp -p "$f" "$DEST/"
    echo "    + $(basename "$f")"
done

echo "Done."

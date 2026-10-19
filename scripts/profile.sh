#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
MODE="${1:-idle}"
SECONDS_TO_SAMPLE="${2:-15}"
if [[ "$MODE" != idle && "$MODE" != settings ]]; then
  echo "Usage: ./scripts/profile.sh [idle|settings] [5-60 seconds]" >&2
  exit 1
fi
APP="$PWD/dist/LightSnap.app"
[[ -x "$APP/Contents/MacOS/LightSnap" ]] || { echo "Run ./scripts/build-app.sh first." >&2; exit 1; }
mkdir -p reports
REPORT="$PWD/reports/${MODE}-$(date +%Y%m%d-%H%M%S).json"
echo "Close any running LightSnap instance first. Avoid interacting with the app during this measurement."
echo "Measuring $MODE mode; first 3 seconds are excluded. The profiling app exits when done."
if ! open -W -n "$APP" --args "--profile-$MODE" "$REPORT" "$SECONDS_TO_SAMPLE"; then
  echo "macOS could not launch the profiling app. No performance result was produced." >&2
  exit 1
fi
[[ -f "$REPORT" ]] || { echo "No report was produced; check the app's launch/crash status." >&2; exit 1; }
cat "$REPORT"
echo "\nSaved: $REPORT"

#!/bin/zsh
# Records the three catchlight.app phone clips from the real app, in the Cobalt Scene, Daylight
# and Night: six MP4s, six WebP stills and a contact sheet per clip, with the app commit noted.
#
#   scripts/site-clips/record.sh [--draft] [--clip shaping-a-take|setting-a-reminder|sequence]
#                                [--appearance daylight|night] [--out DIR]
#
# Needs xcodegen, ffmpeg (libx264) and cwebp. Uses the simulator "Claude iPhone 17" (created if
# missing, never deleted, shut down at the end). Debug build only: the demo Takes and the flows
# are compiled out of Release. See scripts/site-clips/README.md.
set -euo pipefail

ROOT="${0:A:h:h:h}"
WORK="$HOME/CatchlightBuild/site-clips-work"
DEVICE_NAME="${CLIP_DEVICE:-Claude iPhone 17}"
DRAFT=0; ONLY_CLIP=""; ONLY_APPEARANCE=""; OUT=""
while (( $# )); do
  case "$1" in
    --draft) DRAFT=1 ;;
    --clip) ONLY_CLIP="$2"; shift ;;
    --appearance) ONLY_APPEARANCE="$2"; shift ;;
    --out) OUT="$2"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
if [[ -z "$OUT" ]]; then
  OUT="$HOME/Library/Caches/considus/handover/$(date +%F)_site-clips$([[ $DRAFT == 1 ]] && echo -draft)"
fi
mkdir -p "$OUT" "$WORK"

for tool in xcodegen ffmpeg cwebp xcrun; do command -v $tool >/dev/null || { echo "missing $tool" >&2; exit 1; }; done

# --- the simulator -----------------------------------------------------------------------
UDID="$(xcrun simctl list devices available | grep -F "    $DEVICE_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
if [[ -z "$UDID" ]]; then
  RUNTIME="$(xcrun simctl list runtimes available | grep -E '^iOS' | tail -1 | sed -E 's/.* - //')"
  UDID="$(xcrun simctl create "$DEVICE_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$RUNTIME")"
  echo "created $DEVICE_NAME $UDID"
fi
RECORDER_PID=""
cleanup() {
  [[ -n "$RECORDER_PID" ]] && kill -INT "$RECORDER_PID" 2>/dev/null || true
  xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
}
trap cleanup EXIT
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --operatorName ""

# --- build once --------------------------------------------------------------------------
cd "$ROOT"
xcodegen generate >/dev/null
DD="$WORK/DerivedData"
xcodebuild build-for-testing -scheme CatchlightSiteClips -derivedDataPath "$DD" \
  -destination "platform=iOS Simulator,id=$UDID" -quiet >"$WORK/build.log" 2>&1 \
  || { tail -30 "$WORK/build.log"; exit 1; }
XCTESTRUN="$(ls "$DD"/Build/Products/*.xctestrun | head -1)"

# --- record each clip --------------------------------------------------------------------
typeset -A TESTS=( shaping-a-take testClip1_shapingATake setting-a-reminder testClip2_settingAReminder sequence testClip3_sequence )
CLIPS=(shaping-a-take setting-a-reminder sequence)
[[ -n "$ONLY_CLIP" ]] && CLIPS=("$ONLY_CLIP")
APPEARANCES=(daylight night)
[[ -n "$ONLY_APPEARANCE" ]] && APPEARANCES=("$ONLY_APPEARANCE")

RESULTS="$WORK/results.jsonl"; : > "$RESULTS"
for clip in $CLIPS; do
  for look in $APPEARANCES; do
    run="$WORK/$clip-$look"; rm -rf "$run"; mkdir -p "$run"
    echo "== $clip / $look"
    xcrun simctl terminate "$UDID" com.considus.catchlight 2>/dev/null || true
    (
      export TEST_RUNNER_CLIP_OUT_DIR="$run" TEST_RUNNER_CLIP_APPEARANCE="$look"
      xcodebuild test-without-building -xctestrun "$XCTESTRUN" \
        -destination "platform=iOS Simulator,id=$UDID" \
        -only-testing:"CatchlightSiteClips/SiteClipFlows/${TESTS[$clip]}" >"$run/test.log" 2>&1
    ) &
    TEST_PID=$!
    # Wait for the app to be up and still, then start the screen recording, then say go.
    for _ in {1..600}; do [[ -f "$run/ready" ]] && break; kill -0 $TEST_PID 2>/dev/null || break; sleep 0.2; done
    [[ -f "$run/ready" ]] || { tail -30 "$run/test.log"; echo "flow never got ready" >&2; exit 1; }
    xcrun simctl io "$UDID" recordVideo --codec h264 --force "$run/raw.mov" >"$run/rec.log" 2>&1 &
    RECORDER_PID=$!
    sleep 1.5
    touch "$run/go"
    wait $TEST_PID || { tail -40 "$run/test.log"; echo "flow failed: $clip / $look" >&2; exit 1; }
    kill -INT $RECORDER_PID; wait $RECORDER_PID 2>/dev/null || true; RECORDER_PID=""
    grep -E "Executed [0-9]+ test" "$run/test.log" | tail -1
    "$ROOT/scripts/site-clips/encode.py" "$run/raw.mov" "$run/$(echo $clip).taps.json" "$OUT" "$clip" "$look" \
      $([[ $DRAFT == 1 ]] && echo --draft) | tee -a "$RESULTS"
  done
done

# --- the note beside the files -----------------------------------------------------------
{
  echo "Catchlight-iOS commit: $(git rev-parse HEAD)$([[ -n "$(git status --porcelain -- Catchlight Tests project.yml)" ]] && echo ' (+ uncommitted changes)')"
  echo "Recorded: $(date '+%F %T')  Device: $DEVICE_NAME, $(xcrun simctl list devices | grep -F "$UDID" | head -1 | sed 's/ (.*//' | xargs), iOS $(xcrun simctl list runtimes | grep -E '^iOS' | tail -1 | sed -E 's/iOS ([0-9.]+).*/\1/')"
  echo "Scene: Cobalt. $([[ $DRAFT == 1 ]] && echo 'DRAFT: recorded before the card outline and Important shade changes landed.')"
  echo; cat "$RESULTS"
} > "$OUT/RECORDED.txt"
echo "done: $OUT"

#!/bin/bash
# Home Screen web app test on one simulated iPhone; video + screenshots land in out/.
# Usage: ./run.sh "iPhone 15 Pro" https://opengym.runs-on.dev   (APP_USER / APP_PASS optional)
set -uo pipefail
DEVICE="$1"; URL="$2"; OUT="$PWD/out"; mkdir -p "$OUT"

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c "import json,sys;r=[x for x in json.load(sys.stdin)['runtimes'] if x['name'].startswith('iOS') and x['isAvailable']];print(max(r,key=lambda x:[int(v) for v in x['version'].split('.')])['identifier'])")
TYPE=$(xcrun simctl list devicetypes -j | python3 -c "import json,sys;print(next(d['identifier'] for d in json.load(sys.stdin)['devicetypes'] if d['name']==sys.argv[1]))" "$DEVICE")
UDID=$(xcrun simctl create test "$TYPE" "$RUNTIME")
xcrun simctl bootstatus "$UDID" -b

(cd harness && xcodegen generate)
xcodebuild build-for-testing -project harness/Harness.xcodeproj -scheme Harness -destination "id=$UDID" -derivedDataPath build -quiet || exit 1

xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/video.mp4" & REC=$!
sleep 2
xcrun simctl openurl "$UDID" "$URL"
TEST_RUNNER_OUT="$OUT" TEST_RUNNER_APP_USER="${APP_USER:-}" TEST_RUNNER_APP_PASS="${APP_PASS:-}" \
  xcodebuild test-without-building -project harness/Harness.xcodeproj -scheme Harness -destination "id=$UDID" -derivedDataPath build > "$OUT/test-log.txt" 2>&1
STATUS=$?
grep -E "error:|failed|passed|Assertion" "$OUT/test-log.txt" | head -20
kill -INT $REC; wait $REC
exit $STATUS

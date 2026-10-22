#!/bin/bash
# Home Screen web app test on one simulated iPhone; video + screenshots land in out/.
# Usage: ./run.sh "iPhone 15 Pro" [url]   (default: the demo build in app/, served on this Mac)
set -uo pipefail
DEVICE="$1"; URL="${2:-http://localhost:8000/}"; OUT="$PWD/out"; mkdir -p "$OUT"
python3 -m http.server 8000 --directory app > /dev/null 2>&1 &

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c "import json,sys;r=[x for x in json.load(sys.stdin)['runtimes'] if x['name'].startswith('iOS') and x['isAvailable']];print(max(r,key=lambda x:[int(v) for v in x['version'].split('.')])['identifier'])")
TYPE=$(xcrun simctl list devicetypes -j | python3 -c "import json,sys;print(next(d['identifier'] for d in json.load(sys.stdin)['devicetypes'] if d['name']==sys.argv[1]))" "$DEVICE")
UDID=$(xcrun simctl create test "$TYPE" "$RUNTIME")
# Boot (minutes on a cold CI Mac) while the test harness builds.
xcrun simctl bootstatus "$UDID" -b > /dev/null & BOOT=$!

# build/ is restored from the GitHub cache when harness/ hasn't changed.
if ! ls build/Build/Products/*.xctestrun > /dev/null 2>&1; then
  (cd harness && xcodegen generate)
  xcodebuild build-for-testing -project harness/Harness.xcodeproj -scheme Harness -destination "generic/platform=iOS Simulator" -derivedDataPath build -quiet || exit 1
fi
wait $BOOT

xcrun simctl io "$UDID" recordVideo --codec=h264 --mask=black --force "$OUT/video.mp4" & REC=$!
sleep 2
xcrun simctl openurl "$UDID" "$URL"
TEST_RUNNER_OUT="$OUT" xcodebuild test-without-building -xctestrun build/Build/Products/*.xctestrun -destination "id=$UDID" \
  -retry-tests-on-failure -test-iterations 2 > "$OUT/test-log.txt" 2>&1 # CI Macs sometimes time out launching Safari
STATUS=$?
grep -E "error:|failed|passed|Assertion" "$OUT/test-log.txt" | head -20
kill -INT $REC; wait $REC
exit $STATUS

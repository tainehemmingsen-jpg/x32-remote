#!/bin/bash
# Builds the app for the iOS Simulator. Tries the App Playground package directly, then an XcodeGen project.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/ci-out}"
mkdir -p "$OUT"
DERIVED="$ROOT/build/DerivedData"
rm -rf "$DERIVED"
cd "$ROOT/X32Remote.swiftpm"
echo "== Schemes"
xcodebuild -list 2>&1 | tee "$OUT/schemes.log" || true
echo "== Building App Playground package"
set +e
xcodebuild -scheme "X32 Remote" -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$OUT/build-swiftpm.log" | grep -E "error:|warning: .*(deprecated|unused)|BUILD (SUCCEEDED|FAILED)" | head -200
STATUS=${PIPESTATUS[0]}
set -e
APP=$(find "$DERIVED" -path "*Debug-iphonesimulator*" -name "*.app" -maxdepth 6 2>/dev/null | head -1)
if [ "$STATUS" -eq 0 ] && [ -n "$APP" ]; then
  echo "APP=$APP" | tee "$OUT/app-path.txt"
  echo "swiftpm" > "$OUT/build-method.txt"
  exit 0
fi
echo "== Package build failed or produced no app (status $STATUS); trying XcodeGen project"
grep -E "error:" "$OUT/build-swiftpm.log" | sort -u | head -100 > "$OUT/errors-swiftpm.txt" || true
cd "$ROOT/ci"
if ! command -v xcodegen >/dev/null; then brew install xcodegen >/dev/null 2>&1; fi
xcodegen generate --spec project.yml --project "$ROOT/build" 2>&1 | tail -3
cd "$ROOT/build"
set +e
xcodebuild -project X32Remote.xcodeproj -scheme X32Remote -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$OUT/build-xcodeproj.log" | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -200
STATUS=${PIPESTATUS[0]}
set -e
grep -E "error:" "$OUT/build-xcodeproj.log" | sort -u | head -100 > "$OUT/errors-xcodeproj.txt" || true
APP=$(find "$DERIVED" -path "*Debug-iphonesimulator*" -name "*.app" -maxdepth 6 2>/dev/null | head -1)
if [ "$STATUS" -eq 0 ] && [ -n "$APP" ]; then
  echo "APP=$APP" | tee "$OUT/app-path.txt"
  echo "xcodegen" > "$OUT/build-method.txt"
  exit 0
fi
echo "BUILD FAILED"
exit 1

#!/bin/bash
# Builds Mixline and uploads it to TestFlight. Run on the Mac:
#     ci/testflight.sh
# Bumps the build number in Package.swift, archives with the paid team, and uploads.
# New builds go to the "Me" tester group automatically once Apple has processed them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/X32Remote.swiftpm/Package.swift"
OUT="${TMPDIR:-/tmp}/x32-testflight"
TEAM=82M7WP2BBY

# Next build number (App Store Connect refuses a number it has seen before).
CURRENT=$(sed -n 's/.*bundleVersion: "\([0-9]*\)".*/\1/p' "$PKG")
NEXT=$((CURRENT + 1))
sed -i '' "s/bundleVersion: \"$CURRENT\"/bundleVersion: \"$NEXT\"/" "$PKG"
echo "Build $NEXT"

# The current iOS SDK, so the app is stamped with it. (App Playground packages link with the
# deployment target as the SDK version, which App Store Connect rejects.)
SDK=$(xcrun --sdk iphoneos --show-sdk-version)

rm -rf "$OUT" && mkdir -p "$OUT"
cd "$ROOT/X32Remote.swiftpm"
xcodebuild -scheme "Mixline" -destination 'generic/platform=iOS' \
  -archivePath "$OUT/X32Remote.xcarchive" -derivedDataPath "$OUT/dd" \
  -skipPackagePluginValidation -allowProvisioningUpdates DEVELOPMENT_TEAM=$TEAM \
  OTHER_LDFLAGS="\$(inherited) -Xlinker -platform_version -Xlinker ios -Xlinker 17.0 -Xlinker $SDK" \
  archive | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$OUT/X32Remote.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates 2>&1 | grep -E "error|Upload succeeded|EXPORT (SUCCEEDED|FAILED)|SDK version"
echo "Uploaded build $NEXT. It shows up in TestFlight once Apple has processed it (usually 5–30 minutes)."

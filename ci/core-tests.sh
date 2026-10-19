#!/bin/bash
# Compiles the app's Core folder into a throwaway SwiftPM package and runs its unit tests on the host.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/ci-out}"
mkdir -p "$OUT"
PKG="$ROOT/build/CoreTestPackage"
rm -rf "$PKG"
mkdir -p "$PKG/Sources/X32Core" "$PKG/Tests/X32CoreTests"
cp "$ROOT"/X32Remote.swiftpm/Core/*.swift "$PKG/Sources/X32Core/"
cp "$ROOT"/Tests/CoreTests/*.swift "$PKG/Tests/X32CoreTests/"
cat > "$PKG/Package.swift" <<'PKGEOF'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "X32Core",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "X32Core", targets: ["X32Core"])],
    targets: [
        .target(name: "X32Core", path: "Sources/X32Core"),
        .testTarget(name: "X32CoreTests", dependencies: ["X32Core"], path: "Tests/X32CoreTests")
    ]
)
PKGEOF
cd "$PKG"
swift test 2>&1 | tee "$OUT/core-tests.log"

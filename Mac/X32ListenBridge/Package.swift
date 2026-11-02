// swift-tools-version: 5.9

// X32 Listen Bridge: streams the X32's solo bus from its USB card to X32 Remote on an iPad, over Wi-Fi.
// Run it on the Mac plugged into the desk's USB port:
//     cd Mac/X32ListenBridge && swift run -c release
// (ListenProtocol.swift is shared with the iPad app.)

import PackageDescription

let package = Package(
    name: "X32ListenBridge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "X32ListenBridge", path: "Sources/X32ListenBridge")
    ]
)

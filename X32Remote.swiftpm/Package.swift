// swift-tools-version: 5.9

// X32 Remote — an iPad/iPhone remote for Behringer X32 and Midas M32 consoles.
// Open this folder in Xcode (File > Open… > X32Remote.swiftpm) or in Swift Playgrounds on iPad.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "X32 Remote",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "X32 Remote",
            targets: ["AppModule"],
            bundleIdentifier: "nz.taine.x32remote",
            teamIdentifier: "82M7WP2BBY",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .localNetwork(purposeString: "X32 Remote talks to your X32 mixer over the local network.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)

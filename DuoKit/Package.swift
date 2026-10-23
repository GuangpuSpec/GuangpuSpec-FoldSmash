// swift-tools-version: 6.0
import PackageDescription

// DuoKit: the shared hinge layer for all three iPhone Duo toys.
// Requires Xcode 27.1 (iOS 27.1 SDK) for the live hinge API.
let package = Package(
    name: "DuoKit",
    // macOS only so `swift test` runs the pure logic on a Mac.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DuoKit", targets: ["DuoKit"])
    ],
    targets: [
        .target(name: "DuoKit"),
        .testTarget(name: "DuoKitTests", dependencies: ["DuoKit"])
    ]
)

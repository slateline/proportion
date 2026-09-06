// swift-tools-version: 5.9
import PackageDescription

// ProportionCore is the platform-independent heart of the app: exact rational
// quantities, the unit system, the scaling engine, and the cook-friendly
// formatter. It depends on Foundation only, so it builds and tests anywhere
// Swift runs. The iOS app is a thin SwiftUI/SwiftData shell over it.
let package = Package(
    name: "ProportionCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ProportionCore", targets: ["ProportionCore"]),
    ],
    targets: [
        .target(name: "ProportionCore"),
        .testTarget(name: "ProportionCoreTests", dependencies: ["ProportionCore"]),
    ]
)

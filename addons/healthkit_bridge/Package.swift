// swift-tools-version: 5.9
import PackageDescription

// Requires SwiftGodot version compatible with Godot 4.6.
// If the build fails with GDExtension API mismatches, check
// https://github.com/migueldeicaza/SwiftGodot/releases for the matching tag.
let package = Package(
    name: "HealthKitBridge",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "HealthKitBridge", type: .dynamic, targets: ["HealthKitBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftGodot", from: "0.7.0")
    ],
    targets: [
        .target(
            name: "HealthKitBridge",
            dependencies: [
                .product(name: "SwiftGodot", package: "SwiftGodot")
            ],
            path: "Sources/HealthKitBridge",
            linkerSettings: [
                .linkedFramework("HealthKit")
            ]
        )
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macbar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MacBarCore", targets: ["MacBarCore"]),
        .library(name: "MacBarSystem", targets: ["MacBarSystem"]),
        .library(name: "MacBarUI", targets: ["MacBarUI"]),
        .executable(name: "MacBar", targets: ["MacBar"]),
    ],
    targets: [
        .target(
            name: "MacBarCore",
            path: "Sources/MacBarCore"
        ),
        .target(
            name: "MacBarSystem",
            dependencies: ["MacBarCore"],
            path: "Sources/MacBarSystem",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .target(
            name: "MacBarUI",
            dependencies: ["MacBarCore"],
            path: "Sources/MacBarUI"
        ),
        .executableTarget(
            name: "MacBar",
            dependencies: ["MacBarCore", "MacBarSystem", "MacBarUI"],
            path: "Sources/MacBar"
        ),
        .testTarget(
            name: "MacBarCoreTests",
            dependencies: ["MacBarCore"],
            path: "Tests/MacBarCoreTests"
        ),
    ]
)

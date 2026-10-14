// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Emma",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "0.14.1"),
    ],
    targets: [
        .executableTarget(
            name: "Emma",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            path: "Sources/Emma",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "EmmaTests",
            dependencies: ["Emma"],
            path: "Tests/EmmaTests",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)

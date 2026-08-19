// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WorktreeCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "WorktreeCore", targets: ["WorktreeCore"]),
    ],
    targets: [
        .target(name: "WorktreeCore"),
        .testTarget(
            name: "WorktreeCoreTests",
            dependencies: ["WorktreeCore"]
        ),
    ]
)

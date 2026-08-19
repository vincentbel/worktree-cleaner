// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "WorktreeCore",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "WorktreeCore", targets: ["WorktreeCore"])
  ],
  targets: [
    .target(
      name: "WorktreeCore",
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "WorktreeCoreTests",
      dependencies: ["WorktreeCore"]
    ),
  ]
)

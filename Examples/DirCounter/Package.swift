// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "DirCounter",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "DirCounterCore", targets: ["DirCounterCore"]),
    .executable(name: "dir-counter", targets: ["DirCounter"]),
  ],
  dependencies: [
    .package(name: "swift-composable-architecture", path: "../..")
  ],
  targets: [
    .target(
      name: "DirCounterCore",
      dependencies: [
        .product(
          name: "ComposableArchitecture",
          package: "swift-composable-architecture"
        )
      ]
    ),
    .executableTarget(
      name: "DirCounter",
      dependencies: ["DirCounterCore"]
    ),
    .testTarget(
      name: "DirCounterTests",
      dependencies: ["DirCounterCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)

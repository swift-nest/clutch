// swift-tools-version: 5.5
// tested only against 5.7

import PackageDescription

let name = "clutch"
let package = Package(
  name: name,
  platforms: [
    .macOS(.v12) // Tracking Shwift
  ],
  products: [
    .executable(name: name, targets: [name])
  ],
  dependencies: [
    .package(
      url: "https://github.com/GeorgeLyon/Shwift.git",
      from: Version(stringLiteral: "2.0.1")
    ),
    .package(
      url: "https://github.com/apple/swift-atomics.git",
      from: Version(stringLiteral: "1.1.0")
    )
  ],
  targets: [
    .target(
      name: "\(name)Lib",
      dependencies: [
        .product(name: "Shwift", package: "Shwift"),
        .product(name: "Script", package: "Shwift"),
      ],
      path: "Sources/clutch"
    ),
    .executableTarget( // RU N:clutch
      name: name,
      dependencies: [
        .product(name: "Shwift", package: "Shwift"),
        .product(name: "Script", package: "Shwift"),
        .target(name: "\(name)Lib")
      ],
      path: "Sources/clutch-tool"
    ),
    .executableTarget( // RUN:ClutchAP
      name: "ClutchAP",
      dependencies: [
        .product(name: "Shwift", package: "Shwift"),
        .product(name: "Script", package: "Shwift"),
        .target(name: "clutch"),
      ]
    ),
    .testTarget(
      name: "\(name)Tests",
      dependencies: [
        .target(name: "\(name)Lib"),
        .target(name: "\(name)"),
        .product(name: "Atomics", package: "swift-atomics")
      ]
    )
  ]
)

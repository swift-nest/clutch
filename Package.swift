// swift-tools-version: 5.5
// tested only against 5.7

import PackageDescription

let name = "clutch"
let clatch = "clatch"
let package = Package(
  name: name,
  platforms: [ .macOS(.v12) ],
  products: [
    .executable(name: name, targets: [name]),
    .executable(name: clatch, targets: [clatch]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/GeorgeLyon/Shwift.git",
      from: Version(stringLiteral: "2.0.1")
    ),
  ],
  targets: [
    .target(
      name: "\(name)Lib",
      dependencies: [ .product(name: "Script", package: "Shwift") ],
      path: "Sources/\(name)"
    ),
    .executableTarget( // RUN:clutch
      name: name,
      dependencies: [ .target(name: "\(name)Lib") ],
      path: "Sources/\(name)-tool"
    ),
    .executableTarget(
      name: "ClutchAP",
      dependencies: [ .target(name: "\(name)Lib") ]
    ),
    .executableTarget(
      name: clatch,
      dependencies: [ .product(name: "Script", package: "Shwift") ]
    ),
    .testTarget(
      name: "\(name)Tests",
      dependencies: [ .target(name: "\(name)Lib") ]
    )
  ]
)


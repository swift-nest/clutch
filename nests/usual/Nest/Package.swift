// swift-tools-version: 5.6

import PackageDescription

let package = Package(
  name: "Nest",
  platforms: [
    .macOS(.v12) // Tracking Shwift
  ],
  products: [
    .executable(name: "minime", targets: [ "minime" ]),
    .library(name: "Nest", targets: ["Nest"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/GeorgeLyon/Shwift.git",
      from: Version(stringLiteral: "2.0.1")
    )
  ],
  targets: [
    .executableTarget(name: "minime", dependencies: ["Nest"]),
    .target(
      name: "Nest",
      dependencies: [
        .product(name: "Shwift", package: "Shwift"),
        .product(name: "Script", package: "Shwift"),
      ]
    )
  ]
)

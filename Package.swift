// swift-tools-version: 6.0

import PackageDescription

let name = "clutch"
let clatch = "clatch"
let clutchArgParser = "ClutchAP"

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("FullTypedThrows"),  // SE-0413
  .enableUpcomingFeature("SameElementRequirements"),  // SE-0393
  // .enableExperimentalFeature("AccessLevelOnImport"),  // SE-0409
  // .enableUpcomingFeature("InternalImportsByDefault")  // SE-0408
]
let package = Package(
  name: name,
  platforms: [.macOS(.v12)],
  products: [
    .executable(name: name, targets: [name]),
    .executable(name: clatch, targets: [clatch]),
    .executable(name: clutchArgParser, targets: [clutchArgParser]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/GeorgeLyon/Shwift.git",
      from: Version(stringLiteral: "3.1.1")
    ),
    .package(
      url: "https://github.com/apple/swift-atomics.git",
      from: Version(stringLiteral: "1.2.0")
    ),
  ],
  targets: [
    .target(
      name: "\(name)Lib",
      dependencies: [.product(name: "Script", package: "Shwift")],
      path: "Sources/\(name)"
    ),
    .executableTarget(  // RUN:clutch
      name: name,
      dependencies: [.target(name: "\(name)Lib")],
      path: "Sources/\(name)-tool"
    ),
    .executableTarget(
      name: clutchArgParser,
      dependencies: [.target(name: "\(name)Lib")]
    ),
    .executableTarget(
      name: clatch,
      dependencies: [.product(name: "Script", package: "Shwift")]
    ),
    .testTarget(
      name: "\(name)Tests",
      dependencies: [
        .target(name: "\(name)Lib"),
        .product(name: "Atomics", package: "swift-atomics")
      ]
    ),
  ],
  swiftLanguageVersions: [.v6] // 7/13/24
  //swiftLanguageModes: [.v6] // 7/31/24
)

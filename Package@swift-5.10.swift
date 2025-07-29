// swift-tools-version: 5.10

import PackageDescription

let name = "clutch"
let clatch = "clatch"
let clutchArgParser = "ClutchAP"
func apple(
  _ package: String,
  _ version: String
) -> PackageDescription.Package.Dependency {
  .package(
    url: "https://github.com/apple/\(package)",
    from: Version(stringLiteral: version)
  )
}

let package = Package(
  name: name,
  platforms: [ .macOS(.v13) ],
  products: [
    .executable(name: name, targets: [name]),
    .executable(name: clatch, targets: [clatch]),
    .executable(name: clutchArgParser, targets: [clutchArgParser]),
  ],
  dependencies: [
    apple("swift-atomics", "1.2.0"),
    apple("swift-system", "1.4.0"),
    apple("swift-argument-parser", "1.5.0"),
  ],
  targets: [
    .target(
      name: "MinSys",
      dependencies: [
        .product(name: "SystemPackage", package: "swift-system"),
      ],
      swiftSettings: [
        .enableExperimentalFeature("AccessLevelOnImport")
        ]),
    .executableTarget(
      name: clatch,
      dependencies: [ .target(name: "MinSys") ]
    ),
    .target(
      name: "\(name)Lib",
      dependencies: [ .target(name: "MinSys") ],
      path: "Sources/\(name)"
    ),
    .executableTarget( // RUN:clutch
      name: name,
      dependencies: [ .target(name: "\(name)Lib") ],
      path: "Sources/\(name)-tool"
    ),
    .executableTarget(
      name: clutchArgParser,
      dependencies: [
        .target(name: "\(name)Lib"),
        .product(
          name: "ArgumentParser",
          package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "\(name)Tests",
      dependencies: [
      .target(name: "\(name)Lib"),
      .product(name: "Atomics", package: "swift-atomics")
      ],
      // Avoid duplicate main's (in clutch-tool/ and clutchTests/Main/)
      // We drive ClutchTestMain from ClutchMainTest in test harness.
      swiftSettings: [.unsafeFlags([
        "-Xfrontend", "-entry-point-function-name",
        "-Xfrontend", "ignoreMain",
      ])]
    ),
  ]
)

// swift-tools-version: 5.6

import PackageDescription

let package = Package(
  name: "Nest",
  products: [
    .executable(name: "demo", targets: [ "demo" ]),
    .library(name: "Nest", targets: ["Nest"]),
  ],
  targets: [
    .executableTarget(name: "demo", dependencies: ["Nest"]),
    .target(name: "Nest"),
  ]
)

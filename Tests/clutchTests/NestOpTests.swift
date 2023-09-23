import XCTest

@testable import clutchLib

final class NestOpTests: XCTestCase {
  func testListProducts() throws {
    let code1 = """
      import PackageDescription
        targets: [
          .executableTarget(name: "demo1", dependencies: ["Nest"]),
          .executableTarget(name: "demo2", dependencies: ["Nest"]),
          .target(name: "Nest"),
        ]
      )
      """
    typealias Test = (loc: SrcLoc, code: String, exp: [String])
    let tests: [Test] = [
      (.sl(), code1, ["demo1", "demo2"])  // in file order
    ]
    let peerOp = PeerOp(KnownSystemCalls())
    for (i, test) in tests.enumerated() {
      let products = peerOp.listExecutableProductsBeforeRegex(test.code)
      test.loc.ea(test.exp, products, "[\(i)]")

      #if canImport(Regex) && swift(>=5.8)
        if #available(macOS 13.0, *) {
          let products13 = try peerOp.listExecutableProductsWithRegex(test.code)
          test.loc.ea(test.exp, products13, "[\(i)](Regex)")
        }
      #endif
    }
  }

  func testAddPeerToPackage() throws {
    let code1 = """
      import PackageDescription

      let package = Package(
        name: "Nest",
        products: [
          .executable(name: "demo", targets: ["demo"]),
          .library(name: "Nest", targets: ["Nest"]),
        ],
        targets: [
          .executableTarget(name: "demo", dependencies: ["Nest"]),
          .target(name: "Nest"),
        ]
      )
      """
    let code2 = """
      import PackageDescription

      let package = Package(
        name: "Nest",
        products:
        [ // \(PeerNest.EnvName.TAG_PRODUCT)
          .executable(name: "demo", targets: ["demo"]),
          .library(name: "Nest", targets: ["Nest"]),
        ],
        targets: 
        [ // \(PeerNest.EnvName.TAG_TARGET)
          .executableTarget(name: "demo", dependencies: ["Nest"]),
          .target(name: "Nest"),
        ]
      )
      """
    let nest = "Nest2"
    let name = "demo2"
    let contains = [
      ", targets: [\"\(name)\"",
      "executableTarget(name: \"\(name)\"",
      "dependencies: [\"\(nest)\"",
    ]
    let peerOp = PeerOp(KnownSystemCalls())
    for (i, code) in [code1, code2].enumerated() {
      let result = peerOp.addPeerToPackageCode(
        peerModuleName: name,
        nestModuleName: nest,
        packageCode: code
      )
      if let result = result {
        for exp in contains {
          XCTAssertTrue(result.contains(exp), "\(i) missing \(exp)")
        }
      } else {
        XCTFail("\(i) failed")
      }
    }
  }

}

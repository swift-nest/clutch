import XCTest

@testable import clutchLib

final class NestOpTests: XCTestCase {
  func testEolAfterQueryIfEmpty() {
    typealias TC = (code: String, query: String, start: Int, result: Int?)
    let tests: [TC] = [
      ("bar \nnext", "bar", 0, 5),
      ("foo\nnext", "foo", 0, 4),
      ("foo // comment\nnext", "foo", 0, 15),
      ("foo\n", "foo", 0, nil), // no text after newline
      ("targ: [\n8", "targ: [", 0, 8),
      ("targ: [  \n10", "targ: [", 0, 10), // ok: whitespace
      ("targ: [//\n10", "targ: [", 0, 10), // ok: comment
      ("targ: [//ab\n12", "targ: [", 0, 12), // ok: comment with text
      ("targ: [\"\" \nnil", "targ: [", 0, nil), // not comment or whitespace
      ("targ: [\"\" \nniltarg: [\nok", "targ: [", 0, 22), // ok, second value
    ]
    for (i, (code, query, start, expected)) in tests.enumerated() {
      let startIndex = code.index(code.startIndex, offsetBy: start)
      let actual = PeerOp.eolAfterQueryIfEmpty(code, query: query, startIndex)
      let label = "[\(i)] {\(query)} in \"\(code)\""
      if let expect = expected {
        let expIndex = code.index(code.startIndex, offsetBy: expect)
        XCTAssertEqual(expIndex, actual, label)
      } else {
        XCTAssertNil(actual, "nil \(label)")
      }
    }
  }
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

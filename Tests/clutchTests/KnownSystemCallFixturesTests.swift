import XCTest

@testable import clutchLib

final class KnownSystemCallFixturesTests: XCTestCase {

  let fixtures = KnownSystemCallFixtures()

  public func testFindPaths() async throws {
    typealias Key = PeerNest.ResourceKey
    let sc =  fixtures.newScenario(.script(.uptodate))
    let plurals: [Key] = [.swift, .nestBinDir]
    for key in Key.allCases {
      guard !key.filenames.isEmpty else {
        continue
      }
      let paths = sc.calls.findPaths(key)
      if !plurals.contains(key) {
        XCTAssertEqual(1, paths.count, "\(key) paths: \(paths)")
      } else {
        XCTAssertTrue(1 < paths.count, "\(key) paths: \(paths)")
      }
    }
  }
}

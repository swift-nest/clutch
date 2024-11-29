import XCTest
import clutchLib

import struct SystemPackage.FilePath

@testable import clutchLib


final class ClutchMainTest: XCTestCase {
  static let quiet = "" == "" && !TestHelper.inCI
  static let prefix = "" == ""
  func verbose(_ s: String) {
    if !Self.quiet {
      print(Self.prefix ? "# CMT \(s)" : s)
    }
  }

  /// Run (nobuild, rebuild, newitem) scenarios manually using main-like driver
  /// to debug or to analyze happy-path coverage (i.e., seek unused code).
  ///
  /// Test is skipped in CI or when samples out-of-tree samples are not available.
  ///
  /// Ensure the build state is configured before running:
  /// - Needs a Nest with 3 `HOME/Nest/Samples/{name}.swift`: nobuild, rebuild, and newitem
  /// - manually build nobuild and rebuild
  /// - delete rebuild binary
  /// - if you ran before, delete  any Source/newitem or Package.swift newitem target/product
  func testClutchMain() throws {  // not async to get Script wrapper
    guard !TestHelper.inCI else {
      throw XCTSkip("test is not run in CI")
    }
    // let home = FileManager.default.homeDirectoryForCurrentUser.absoluteString
    guard let home = FS.environment("HOME"), !home.isEmpty else {
      throw XCTSkip("no HOME available")
    }
    let samplesDir = "\(home)/git/Nest/Samples"
    let isDir = true
    let isFile = !isDir
    guard isDir == FoundationScript.fileStatus(samplesDir) else {
      throw XCTSkip("no sample available: \(samplesDir)")
    }
    let list = "peers-Nest"
    let commands = [list]
    let names = ["nobuild", "rebuild", "updatebuild", "newbuild"]
    for name in names {  // [list] ["rebuild"]
      let scriptArgs: [String]
      if commands.contains(name) {
        scriptArgs = [name]
      } else {
        let path = "\(samplesDir)/\(name).swift"
        guard isFile == FoundationScript.fileStatus(path) else {
          verbose("sample \"\(name)\" not found at: \(path)")
          continue
        }
        scriptArgs = [path]
      }
      let suffix = "clutch \(name): \(scriptArgs)"

      verbose("Running \(suffix)")
      // parse to avoid fatal error trying to run directly
      try ClutchTestMain.mainPeek(args: scriptArgs)
      verbose("Done with \(suffix)")
    }
  }
}

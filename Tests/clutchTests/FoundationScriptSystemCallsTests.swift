import Script
import XCTest
import clutchLib

import struct SystemPackage.FilePath

@testable import clutchLib

/// Run actual SystemCalls delegate (without really checking)
///
/// This doesn't respect TestHelper.quiet b/c the output is the point.  Reconsider?
final class FoundationScriptTests: XCTestCase {
  public func testEnvironment() {
    let (home, path) = ("HOME", "PATH")
    let calls = FoundationScriptSystemCalls()
    let kv = calls.environment([home, path])
    let srcLoc = SrcLoc(#function)

    srcLoc.ok(nil != kv[home], home)
    srcLoc.ok(nil != kv[path], path)
  }
  public func testBlindly() {
    guard var command = try? Blind.parseAsRoot([]) else {
      XCTFail("no command")
      return
    }
    do {
      try command.run()  // Script sync wrapper for async
    } catch {
      print("erro: \(error)")
      XCTFail("\(error)")
    }
  }
  struct Blind: Script {
    func run() async throws {
      try await FoundationScriptTests.checkBlindly()
    }
  }

  static func checkBlindly() async throws {
    let srcLoc = SrcLoc(#function)
    let basename = "FSSystemCallsTests.tmp"
    let dirname = "\(basename).dir"
    let filename = "\(basename).file"
    let prefix = "# FoundationScriptTests.\(#function) "
    let calls = FoundationScriptSystemCalls()

    try calls.createDir("\(dirname)")

    srcLoc.ea(.dir, calls.seekFileStatus("."), "CWD - status (true==dir)")

    let bash = try? await calls.findExecutable(named: "bash")
    srcLoc.ok(nil != bash, "bash")

    srcLoc.ok(nil != calls.lastModified("."), "CWD - last modified")

    srcLoc.ok(0.0 != calls.now().value, "now")

    calls.printErr("\(prefix) printErr\n")  // sigh

    calls.printOut("\(prefix) printOut")

    if let bash = bash {
      try await calls.runProcess(bash, args: ["-c", "echo \"\(prefix) bash\""])
    }

    let path = FilePath(dirname).appending(filename).string
    let content = filename

    var err: (any Error)? = nil
    do {
      try await calls.writeFile(path: path, content: content)

      let result = try await calls.readFile(path)

      srcLoc.ea(content, result, "write+read file")
      print("wrote \(path)")
    } catch {
      err = error
    }
    if let bash = bash, !dirname.isEmpty, !dirname.hasPrefix(".") {
      try await calls.runProcess(bash, args: ["-c", "rm -rf \"\(dirname)\""])
    }
    if let err = err {
      throw err
    }
  }
}

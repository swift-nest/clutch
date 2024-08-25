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
  public func testBlindly() async {
    do {
      try await Blind().run()  // Script sync wrapper for async
    } catch {
      print("erro: \(error)")
      XCTFail("\(error)")
    }
  }
  struct Blind {
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

    try calls.createDir(dirname)

    if true != calls.fileStatus(dirname) {
      calls.printErr("\(prefix) Unable to create dir \(dirname) - exiting")
	  return
    }

    srcLoc.ea(.dir, calls.seekFileStatus("."), "CWD - status (true==dir)")

    srcLoc.ok(nil != calls.lastModified("."), "CWD - last modified")

    srcLoc.ok(0.0 != calls.now().value, "now")

    calls.printErr("\(prefix) printErr\n")  // sigh

    calls.printOut("\(prefix) printOut")

    let path = FilePath(dirname).appending(filename).string
    let content = filename

    var err: (any Error)? = nil
    do {
      calls.printOut("Writing \(path) with \(content.count) characters")
      try await calls.writeFile(path: path, content: content)
      calls.printOut("Wrote \(path) - trying to read")

      let result = try await calls.readFile(path)
      calls.printOut("Read \(path)")

      srcLoc.ea(content, result, "write+read file")
    } catch {
      err = error
    }
 
    // ------------- bash-dependent code
    let bash = try? await calls.findExecutable(named: "bash")
    srcLoc.ok(nil != bash, "bash")
    guard let bash else {
    	calls.printOut("\(prefix): no bash, exiting")
    	if let err = err {
    	  throw err
    	}
    	return
    }
 

    calls.printOut("\(prefix) Running bash")
    try await calls.runProcess(bash, args: ["-c", "echo \"\(prefix) bash\""])

    if nil == err, !dirname.isEmpty, !dirname.hasPrefix(".") {
      calls.printOut("\(prefix): using bash to delete temp dir \(dirname)")
      try await calls.runProcess(bash, args: ["-c", "rm -rf \"\(dirname)\""])
    } else {
      calls.printOut("\(prefix): leaving temp dir \(dirname)")
    }

    if let err = err {
      throw err
    }
  }
}

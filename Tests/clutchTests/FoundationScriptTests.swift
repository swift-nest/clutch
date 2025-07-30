@testable import clutchLib
import struct MinSys.FilePath
import XCTest

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
    let prefix = "# \(#file):\(#function) "
    let calls = FoundationScriptSystemCalls()

    srcLoc.ea(.dir, calls.seekFileStatus("."), "CWD - status (true==dir)")

    srcLoc.ok(nil != calls.lastModified("."), "CWD - last modified")

    srcLoc.ok(0.0 != calls.now().value, "now")

    calls.printErr("\(prefix) printErr\n")  // sigh: newline required

    calls.printOut("\(prefix) printOut")

    // create dir and file
    try calls.createDir(dirname)

    let dirPath = "./\(dirname)"
    if true != calls.fileStatus(dirPath) {
      calls.printErr("\(prefix) Unable to create dir \(dirPath) - exiting")
      return
    }

    let path = FilePath(dirPath).appending(filename).string
    let content = filename

    var err: (any Error)?
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

    // ------------- shell-dependent code
    let shell = try? await calls.findExecutable(named: "sh")
    srcLoc.ok(nil != shell, "sh")
    guard let shell else {
      calls.printOut("\(prefix): no sh, exiting")
      if let err {
        throw err
      }
      return
    }

    calls.printOut("\(prefix) Running sh")
    try await calls.runProcess(shell, args: ["-c", "echo \"\(prefix) sh\""])

    if nil == err, !dirname.isEmpty, !dirname.hasPrefix(".") {
      calls.printOut("\(prefix): using sh to delete temp dir \(dirname)")
      try await calls.runProcess(shell, args: ["-c", "rm -rf \"\(dirname)\""])
    } else if let err {
      calls.printOut("\(prefix): leaving dir \(dirname) to eval error\n\(err)")
    } else {
      calls.printOut("\(prefix): leaving temp dir \(dirname) as invalid name")
    }

    if let err {
#if os(Linux) && swift(<6.0)
        let m = "ignoring filesystem race in Linux with Swift < 6.0"
        calls.printErr("\(prefix): \(m)\n\(err)")
#else
        throw err
#endif
    }
  }
}

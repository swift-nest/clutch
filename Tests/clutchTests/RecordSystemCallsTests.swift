import Script
import XCTest

@testable import clutchLib

final class RecordSystemCallsTests: XCTestCase {
  func testNormalizeHomeDate() {
    typealias Test = (sl: SrcLoc, s: String, exp: String)
    typealias RSC = RecordSystemCalls.CallRecord
    let HOME = "/Users/me"
    let tests: [Test] = [
      (.sl(), "\(HOME)", "HOME"),
      (.sl(), "Date(23456)", "Date(DATE)"),
      (.sl(), "\(HOME)/f Date(23456)", "HOME/f Date(DATE)"),
      (.sl(), "Date( invalid", "Date( invalid"),
    ]
    for test in tests {
      let act = RSC.normalize(test.s, home: HOME, date: true)
      test.sl.ea(test.exp, act, "\(test.sl.index)")
    }
  }

  func testSystemCallsRecorder() async throws {
    typealias H = TestHelper

    // Injected values
    let homeKeyStr = "HOME"
    let unknownKey = "unknown key"
    let errMessage = "Not too bad"
    let homeDir = "/Users/wes"
    let newDir = "\(homeDir)/temp-scrTest"

    // Manually configure real calls during test development as needed
    let delegate: SystemCalls
    if "" == "real" {
      delegate = FoundationScriptSystemCalls()
    } else {
      let mock = KnownSystemCalls()
      mock.setEnv([.HOME: homeDir])
      mock.setDirs([homeDir])
      delegate = mock
    }

    // recorder forwards calls to delegate and records results
    let recorder = RecordSystemCalls(delegate: delegate)
    let (start0, _) = recorder.indexFirstNext()
    let sysCalls = recorder as SystemCalls

    // Making these expected calls below...
    let expCalls: [(fun: SystemCallsFunc, call: String)] = [
      (.environment, "\(homeKeyStr)"),
      (.environment, unknownKey),
      (.printErr, errMessage),
      (.createDir, newDir),
      (.fileStatus, homeDir),
    ]

    // Make calls, check any (mock) results
    let homePath = sysCalls.environment(Set([homeKeyStr]))  // 1 environ
    H.ea(homeDir, homePath["HOME"], "HOME")

    let unknown = sysCalls.environment(Set([unknownKey]))  // 2 environ
    H.ea(0, unknown.count, "unknown")

    sysCalls.printErr(errMessage)  // 3 printErr

    try sysCalls.createDir(newDir)  // 4 createDir

    let homeStatus = sysCalls.seekFileStatus(homeDir)  // 5 fileStatus
    H.ea(.dir, homeStatus, "HOME status")

    // ------ Assess recordings
    // start/next counts
    let (start1, next1) = recorder.indexFirstNext()
    H.ea(start0, start1, "start stays the same")
    H.ea(start0 + expCalls.count, next1, "next")

    // Assemble recordings as lines, check (after optionally emitting)
    let copy = recorder.records
    let renders = await copy.copy()
    let lines = renders.map { $0.tabbed() }
    if !TestHelper.inCI && !TestHelper.quiet {
      let data = lines.joined(separator: "\n")
      let prefix = "\n## SystemCallsRecorder data"
      print("\(prefix) start\n\(data)\(prefix) end\n")
    }

    // check renderings (weakly)
    H.ea(expCalls.count, lines.count, "count")
    for i in 0..<expCalls.count {
      let (exp, act) = (expCalls[i], lines[i])
      H.ea(true, act.contains(exp.fun.name), "func\ne: \(exp)\na: \(act)")
      H.ea(true, act.contains(exp.call), "call\ne: \(exp)\na: \(act)")
    }
  }
}

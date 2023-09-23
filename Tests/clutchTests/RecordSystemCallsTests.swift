import Script
import XCTest

@testable import clutchLib

final class RecordSystemCallsTests: XCTestCase {
  func testNormalizeHomeDate() {
    typealias Test = (sl: SrcLoc, s: String, exp: String)
    typealias RSC = RecordSystemCalls
    let HOME = "/Users/me"
    let tests: [Test] = [
      (.sl(), "\(HOME)", "HOME"),
      (.sl(), "Date(23456)", "Date(DATE)"),
      (.sl(), "\(HOME)/f Date(23456)", "HOME/f Date(DATE)"),
      (.sl(), "Date( invalid", "Date( invalid"),
    ]
    for test in tests {
      let act = RSC.normalizeHomeDate(test.s, home: HOME, date: true)
      test.sl.ea(test.exp, act, "\(test.sl.index)")
    }
  }

  func testSystemCallsRecorder() throws {
    typealias H = TestHelper

    // Manually configure real or mock
    // let delegate = RealSystemCalls()
    let delegate = KnownSystemCalls()

    let start = 100
    let count = Count(next: start)
    let recorder = RecordSystemCalls(delegate: delegate, counter: count)
    var callsDone = 0

    let unknownKey = "unknown key"
    let errMessage = "Not too bad"
    let homeDir = "/Users/wes"
    let newDir = "\(homeDir)/temp-scrTest"

    // test calls
    let sysCalls = recorder as SystemCalls

    let homePath = sysCalls.environment(Set(["HOME", "PATH"]))  // 1 environ
    let callEnvHome = 0
    let renderHome = callsDone
    callsDone += 1
    _ = renderHome

    let unknown = sysCalls.environment(Set([unknownKey]))  // 2 environ
    let callEnvUnknown = 1
    let renderUnknown = callsDone
    callsDone += 1

    sysCalls.printErr(errMessage)  // 3 printErr
    let callPrintErr = 0
    let renderPrint = callsDone
    callsDone += 1
    (_, _) = (callPrintErr, renderPrint)

    if "" == "fails" {
      try sysCalls.createDir(newDir)  // 4 createDir
      let callDir = 0
      let renderDir = callsDone
      callsDone += 1
      (_, _) = (callDir, renderDir)
    }

    let homeStatus = sysCalls.fileStatus(homeDir)  // 5 fileStatus
    let callStatus = 0
    let renderStatus = callsDone
    callsDone += 1
    _ = renderStatus + callStatus

    // call results for clients
    H.ea([:], unknown, "not found")
    _ = homePath
    H.ea(nil, homeStatus, "HOME isDir")

    let renders = recorder.renders
    H.ea(callsDone, renders.count, "total call/render.count")

    do {  // environment recordings
      // call records with render
      let envCalls = recorder.environmentRecorder.copy()
      H.ea(1 + callEnvUnknown, envCalls.count, "env.calls.count")  // 1 env
      let (index, tagHE0, env) = envCalls[callEnvUnknown]  // 1 environ
      H.ea(start + renderUnknown, index, "unknown.index")
      H.ea([:], env.frame.result, "unknown.result")
      let (_, tagHE1, homeEnv) = envCalls[callEnvHome]  // 2 environ
      let funct = SystemCallsFunc.environment
      H.ea(funct, tagHE0, "env-0")
      H.ea(funct, tagHE1, "env-1")
      H.ea(funct.name, homeEnv.def.name)
      let unknownRender = "environment(keys=[\"\(unknownKey)\"]) -> [:]"
      H.ea(unknownRender, renders[renderUnknown].call, "render")
    }

    do {  // printErr recordings
      let calls = recorder.printErrRecorder.copy()
      H.ea(1, calls.count, "print.calls.count")
      let (_, _, cr) = calls[0]  // 3 printErr
      let (def, frame) = (cr.def, cr.frame)
      let funct = SystemCallsFunc.printErr
      H.ea(funct.name, def.name, "print function")
      H.ea(errMessage, frame.parms, "error message")
    }

    do {  // fileStatus recordings
      let calls = recorder.fileStatusRecorder.copy()
      H.ea(1, calls.count, "status.calls.count")
      let (_, _, cr) = calls[0]  // 4 filestatus
      let (def, frame) = (cr.def, cr.frame)
      let funct = SystemCallsFunc.fileStatus
      H.ea(funct.name, def.name, "fileStatus function")
      H.ea(homeDir, frame.parms, "fileStatus parms")
    }

    // recorder count
    H.ea(start + callsDone, count.nextPeek(), "count")  // reference semantics

    // emit recordings
    let data =
      renders
      .map { (index, funct, str) in "\(index)\t\(funct.name)\t\(str)" }
      .joined(separator: "\n")
    let prefix = "\n## SystemCallsRecorder data"
    if !TestHelper.inCI && !TestHelper.quiet {
      print("\(prefix) start\n\(data)\(prefix) end\n")
    }
  }
}

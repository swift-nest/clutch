import XCTest

import struct SystemPackage.FilePath

@testable import clutchLib

typealias Ask = DriverConfig.UserAsk
typealias Data = AskData
typealias EnvName = PeerNest.EnvName

/// Test ``DriverConfig/UserAsk``  (i.e., command and parameters),
final class AskDataTests: XCTestCase {
  static let quiet = "" == ""

  /// Test ``DriverConfig/UserAsk`` calculation of user "ask" data (i.e., command and parameters),
  /// per ask enumeration (help, error, run/cat/nest peers, or run script)
  func testAskData() throws {
    let name = "name"
    let nest = "Nest"
    //let altNest = "altNest"
    let home = "/user/home"
    let scriptName = "script"
    //let defNestPath = "\(home)/git/\(nest)"
    //let altNestPath = "\(home)/git/\(altNest)"
    let scriptPath = "\(home)/dir/\(scriptName).swift"
    let snPath = "\(home)/s.N.swift"

    let naFile = "na.swift"
    let isDir = true
    let isFile = !isDir
    let isMissing: Bool? = nil
    let sysCalls = KnownSystemCalls()
    sysCalls.fileStatus[scriptPath] = isFile
    sysCalls.fileStatus[snPath] = isFile
    sysCalls.fileStatus[naFile] = isMissing
    //sysCalls.fileStatus[defNestPath] = isDir
    sysCalls.envKeyValue[EnvName.HOME.key] = home
    let cwd = FilePath(".")

    let tests: [TC] = [
      .init(.sl(), .helpSyntax, ""),
      .init(.sl(), .helpDetail, "-help"),
      .init(.sl(), .syntaxErr, err: "odule", "4abc"),
      .init(.sl(), .runPeer, peer: name, name, "1"),
      .init(.sl(), .catPeer, peer: name, "cat-\(name)"),
      .init(.sl(), .nestPeers, nest: nest, "peers-\(nest)"),
      .init(.sl(), .script, peer: scriptName, "\(scriptPath)"),
      .init(.sl(), .script, peer: "s", snPath),
    ]

    var fails = [(AskData, TC)]()
    for test in tests {
      let (result, _) = AskData.read(test.args, cwd: cwd, sysCalls: sysCalls)
      if !test.check(result) {
        fails.append((result, test))
      }
    }
    if !fails.isEmpty && !Self.quiet {
      let s = fails.map { "\($0.1.i)] \($0.1.args)" }
        .joined(separator: "\n")
      print("## \(fails.count) fails:\n\(s)")
    }
  }
}

struct TC {
  let args: [String]
  let ask: Ask
  let err: String?
  let peer: String?
  let nest: String?
  let scriptNest: String?
  let srcLoc: SrcLoc
  var i: Int {
    srcLoc.index
  }
  init(
    _ srcLoc: SrcLoc,
    _ ask: Ask,
    err: String? = nil,
    peer: String? = nil,
    nest: String? = nil,
    scriptNest: String? = nil,
    _ args: String...
  ) {
    self.args = args
    self.ask = ask
    self.err = err
    self.peer = peer
    self.nest = nest
    self.scriptNest = scriptNest
    self.srcLoc = srcLoc
  }
  func and(_ lhs: inout Bool, _ rhs: Bool) {
    if lhs && !rhs {
      lhs = false
    }
  }
  func check(_ data: AskData) -> Bool {
    var result = srcLoc.ea(ask, data.ask, "ask")
    if let expErr = err {
      if let t = data.errorAskNote {
        if !t.note.contains(expErr) {
          srcLoc.okAnd(&result, false, "exp: \(expErr)\ngot: \(t.note)")
        }
      } else {
        srcLoc.okAnd(&result, false, "exp err: \(expErr)\ngot: \(s(data))")
      }
    }
    srcLoc.eaAndIf(&result, peer, data.peer?.name, "peer")
    srcLoc.eaAndIf(&result, nest, data.commandNestAsk?.nest.nest, "nest")
    let actScriptNest = data.scriptAskScriptPeer?.peer.nest
    srcLoc.eaAndIf(&result, scriptNest, actScriptNest, "scriptNest")
    return result
  }
  func s(_ data: AskData) -> String {
    if let err = data.errorAskNote {
      return "err - \(err.ask): \(err.note)"
    }
    if let scriptPeer = data.scriptAskScriptPeer {
      return "script - \(scriptPeer.peer) at \(scriptPeer.script.fullPath)"
    }
    if let com = data.commandNestAsk {
      return "\(com.ask) - nest: \(com.nest)"
    }
    if let com = data.commandPeerAsk {
      return "\(com.ask) - peer: \(com.peer)"
    }
    return "UNKNOWN: \(data)"
  }
}

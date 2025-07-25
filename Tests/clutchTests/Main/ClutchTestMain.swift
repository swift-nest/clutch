@testable import clutchLib
import Foundation
import struct MinSys.FilePath

extension FoundationScriptSystemCalls: SystemCallsSendable {}

/// Replicate Clutch driver `runMain(..)` in test module
/// to target errors thrown before `runAsk()` used in ``DriverTests``
/// and run in the context of the Script/@main wrapper.
///
/// Limitations
/// - `@main` dups test driver symbol, so have to rename in Package.swift
@main
struct ClutchTestMain {
  public static func main() throws {
    let args = ProcessInfo.processInfo.arguments
    try mainPeek(args: args)
  }

  public static func mainPeek(args: [String]) throws {
    Task {
      var me = Self()
      me.args = args
      do {
        try await me.run()
      } catch {
        print("## ClutchTestMain Task error\n\(error)")
      }
    }
  }

  var args: [String] = []
  var wrap: Bool = false

  func run() async throws {
    // Copy/pasta from clutch.swift
    let wrapped: RecordSystemCalls
    let stripDate = true
    let stripHome: String
    do {
      let sysCalls = FoundationScriptSystemCalls()
      wrapped = RecordSystemCalls(delegate: sysCalls)
      stripHome = sysCalls.seekEnv(.HOME) ?? ""
    }
    let cwd: FilePath = "."
    let (ask, mode) = AskData.read(args, cwd: cwd, sysCalls: wrapped)
    var err: Error?
    do {
      try await ClutchDriver.runAsk(
        sysCalls: wrapped,
        mode: mode,
        data: ask,
        cwd: cwd,
        args: args
      )

    } catch {
      err = error
    }
    if !TestHelper.inCI && !TestHelper.quiet {
      let prefix = "\n## clutch \(args) | data"
      let copy = await wrapped.records.copy()
      let data = copy.map { $0.tabbed(home: stripHome, date: stripDate) }
        .joined(separator: "\n")
      print("\(prefix) START\n\(data)\(prefix) END\n")
    }
    if let err {
      throw err
    }
  }
}

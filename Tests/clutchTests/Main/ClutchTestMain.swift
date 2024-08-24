// workaround linux ld error d/t 2 main's in merged test+main module (?)
#if canImport(ObjectiveC)

  @testable import clutchLib
  import Foundation
  import SystemPackage

  extension FoundationScriptSystemCalls: SystemCallsSendable {}

  /// Replicate Main wrapper in test module to avoid putting recording/wrapper code in clutch module.
  ///
  /// - Can't run in tests without Script.run wrapper (builds Shell, creates async context)
  /// - Can't get Script.run wrapper without Main (unless we copy/paste)
  /// - Can't pass recording-wrapper to Main b/c field violates Decodable or ExpressibleByArgument
  ///     - ? even if field is Decodable and ExpressibleByArgument?
  /// - Thus, have to put recorder in the main module and have Main implement the wrapping?
  /// - But we want the recording implementation only in tests
  /// - So we create a separate main wrapper in tests
  /// - Long-term, it's better to have wrapping configuration here anyway
  @main struct ClutchTestMain {
    public static func main() throws {
      let args = ProcessInfo.processInfo.arguments
      try mainPeek(args: args)
    }

    public static func mainPeek(args: [String]) throws {
      Task {
        var me = ClutchTestMain()
        me.args = args
        try await me.run()
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
      var err: Error? = nil
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
#endif

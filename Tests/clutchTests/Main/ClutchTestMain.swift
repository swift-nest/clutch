// workaround linux ld error d/t 2 main's in merged test+main module (?)
#if canImport(ObjectiveC)

  import Script

  @testable import clutchLib

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
  @main struct ClutchTestMain: Script {

    @Argument(help: ArgumentHelp("", visibility: .private))
    var args: [String] = []
    @Flag
    var wrap: Bool = false

    func run() async throws {
      // Copy/pasta from clutch.swift
      let wrapped: RecordSystemCalls
      let stripDate = true
      let stripHome: String
      do {
        let sysCalls = FoundationScriptSystemCalls()
        let start = 100
        let count = Count(next: start)
        wrapped = RecordSystemCalls(delegate: sysCalls, counter: count)
        stripHome = sysCalls.seekEnv(.HOME) ?? ""
      }

      let cwd = workingDirectory
      let (ask, mode) = AskData.read(args, cwd: cwd, sysCalls: wrapped)
      let driver = ClutchDriver(sysCalls: wrapped, mode: mode)
      defer {  // For now, just emit to stdout
        if !TestHelper.inCI && !TestHelper.quiet {
          let prefix = "\n## clutch \(args) | data"
          let data =
            wrapped
            .renderLines(home: stripHome, date: stripDate)
            .joined(separator: "\n")
          print("\(prefix) START\n\(data)\(prefix) END\n")
        }
      }
      try await driver.runAsk(cwd: cwd, args: args, ask: ask)
    }
  }
#endif

import Foundation  // urk - arg parser is balking on --init
import Script
import clutchLib

/// Given script, find or build executable in nest.
@main public struct Main: Script {
  public static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "clutch",  // ?: pull module name to limit error d/t rename?
      usage: "",  // included in help text
      discussion: Help.HELP,
      shouldDisplay: false
    )
  }
  public init() {
  }
  @Argument(help: .init(Help.argAbstract, discussion: Help.argDiscussion))
  var args: [String] = []

  public func run() async throws {
    try await ClutchDriver.runMain(cwd: workingDirectory, args: args)
  }
}

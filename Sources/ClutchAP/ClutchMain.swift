import ArgumentParser
import Foundation  // urk - arg parser is balking on --init
import Script
import clutchLib

typealias ModuleName = DriverConfig.ModuleName

/// Given script, find or build executable in nest.
@main struct ClutchAP: Script, AsyncParsableCommand {
  private typealias Drive = ClutchDriver
  public static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "ClutchAP",
      usage: "clutch [scriptfile | command]",  // included in help text
      discussion:
        """
        Run Swift scripts from a nest package with dependencies.

        Create, update, and build a peer in the nest for each script.
        """,
      version: "0.5.0",
      shouldDisplay: true,
      subcommands: [
        BuildRunScript.self, CatPeer.self, RunPeer.self, EmitNestDir.self,
        ListNestPeers.self,
      ],
      defaultSubcommand: BuildRunScript.self
    )
  }

  //  func run() async throws {
  //    print("\(self)") // huh? should be default
  //  }
}
extension ClutchAP {
  struct PeerModuleName: ExpressibleByArgument {
    let peer: ModuleName
    init?(argument: String) {
      guard let mn = ModuleName.make(argument, into: .forModule) else {
        return nil
      }
      self.peer = mn
    }
  }
  struct NestModuleName: ExpressibleByArgument {
    let nest: ModuleName
    init?(argument: String) {
      guard let mn = ModuleName.make(argument, into: .forNest) else {
        return nil
      }
      self.nest = mn
    }
  }

  struct CatPeer: AsyncParsableCommand {
    public static var configuration = APHelp.config("cat")
    @Argument(help: "peer name")
    var peer: PeerModuleName

    mutating func run() {
      print("\(self)")
    }
  }

  /// Default action to run script after building as needed DRAFT
  ///
  /// DRAFT fails to run regardless of input, with no decent error; requires arguments
  struct BuildRunScript: AsyncParsableCommand {
    typealias AskKind = DriverConfig.UserAskKind
    public static var configuration = APHelp.config(
      "build/run",
      abstract: "Run script, updating and building in the nest if needed",
      usage: "<script> <arg>..."
    )

    @Argument(help: "script")
    var script: String

    // TODO: P1 forces 1+ arguments
    // transform does not help?
    @Argument(help: "script args", transform: { $0 })
    var args: [String]  // if optional, then not Codable

    func trace(_ s: String) {
      print(s)
    }
    func validate() throws {
      trace("BRV \(script) \(args)")
    }
    func run() async throws {
      let args = ["n/a"]
      trace("BRS \(script) \(args)")
      let driver = ClutchDriver.make()

      let scriptItem: NestItem
      let peer: ModuleName
      let ask = AskKind.readScript(
        script: script,
        cwd: workingDirectory,
        sysCalls: driver.sysCalls
      )
      switch ask {
      case .failure(let err):
        throw err
      case .success(let askKind):
        guard let askScriptPeer = askKind.scriptAskScriptPeer else {
          throw Err.err("Program error unwrapping Ask-script-peer")
        }
        (_, scriptItem, peer) = askScriptPeer
      }
      // (copy-pasta from ClutchDriver)
      let resNestPaths = driver.findNest(inputNestName: peer.nest)
      let nestPaths = try APHelp.tryGet(resNestPaths)
      let psResult = driver.makePeerNestStatus(nestPaths: nestPaths, peer: peer)
      let (_, peerStat, nestStat, options)  // TODO: prefer updated peer?
      = try APHelp.tryGet(psResult).asModulePeerNestOptions

      try await driver.runScript(
        script: scriptItem,
        peerName: peer,
        nestStatus: nestStat,
        peerStatus: peerStat,
        options: options,
        args: args
      )
    }
  }

  struct RunPeer: AsyncParsableCommand {
    public static var configuration = APHelp.config("run")
    @Argument(help: "peer name")
    var peer: PeerModuleName
    @Argument(help: "args")
    var args: [String]

    mutating func run() async throws {
      let driver = ClutchDriver.make()
      let peerMod = peer.peer
      let resNestPaths = driver.findNest(inputNestName: peerMod.nest)
      let nestPaths = try APHelp.tryGet(resNestPaths)
      let psResult = driver.makePeerNestStatus(
        nestPaths: nestPaths,
        peer: peerMod
      )
      let (_, peerStat, nestStat, options)  // TODO: prefer updated peer?
      = try APHelp.tryGet(psResult).asModulePeerNestOptions
      try await driver.buildRunPeer(
        peerMod: peerMod,
        peerSrc: peerStat[.peer],
        nest: nestStat[.nest],
        binary: peerStat[.executable],
        options: options,
        args: args
      )
    }
  }

  struct EmitNestDir: AsyncParsableCommand {
    public static var configuration = APHelp.config(
      "dir",
      abstract: "Emits path of nest directory to stdout",
      usage: "dir <Nest>"
    )
    @Argument(help: "nest name")
    var nest: NestModuleName

    mutating func run() throws {
      let driver = ClutchDriver.make()
      let resNestPaths = driver.findNest(inputNestName: nest.nest.nest)
      let nestPaths = try APHelp.tryGet(resNestPaths)
      let nestStat = nestPaths.nestStatus(using: driver.sysCalls)
      let status = nestStat[.nest]
      let suffix = status.status.isDir ? "" : " (missing)"
      driver.sysCalls.printOut("\(status.fullPath)\(suffix)")
    }
  }

  struct ListNestPeers: AsyncParsableCommand {
    public static var configuration = APHelp.config(
      "peers",
      abstract: "Emit nest peers to stdout",
      usage: "peers <Nest>"
    )
    @Argument(help: "nest name")
    var nest: NestModuleName

    mutating func run() {
      print("\(self)")
    }
  }
}

enum APHelp {
  static func config(
    _ name: String,
    abstract: String? = nil,
    usage: String? = nil
  ) -> CommandConfiguration {
    CommandConfiguration(
      commandName: name,
      abstract: abstract ?? "\(name)",
      usage: usage,
      shouldDisplay: true
    )
  }
  static func tryGet<T>(_ result: Result<T, Err>) throws -> T {
    switch result {
    case .success(let item): return item
    case .failure(let err): throw err
    }
  }
}

import ArgumentParser
import Foundation  // urk - arg parser is balking on --init
import Script
import clutchLib

typealias ModuleName = DriverConfig.ModuleName

/// Entry point for clutch with CLI in the argument-parser style.
///
/// Blocking bugs
/// - fixed? P1 hang on `Shell` integration
///     - `: Script` - hang
///     - `: Script, AsyncParsableCommand` - Script.swift:241: force-unwrap err
///     -  solution: avoid `mutating` for run
///
/// DRAFT:
/// - commands and help unfinished
/// - copy/pasta code from ClutchDriver
/// - untested interface
/// - unclear motivation - superior interface?
///     - not defaulting to run-peer on non-file arg
@main struct ClutchAP: Script, AsyncParsableCommand {
  private typealias Drive = ClutchDriver
  public static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "ClutchAP",
      usage:
        "ClutchAP [[<scriptfile> | run <peer>] {arg}... | [cat|path] <peer> | [peers|dir] <nest>]",
      discussion:
        """
        Run Swift scripts from a nest package with dependencies.

        Create, update, and build a peer in the nest for each script.

        ALPHA: ClutchAP is untested.  Use clutch instead.
        """,
      version: "\(Help.VERSION)",
      shouldDisplay: true,
      subcommands: [
        BuildRunScript.self,  //
        PeerRun.self, PeerCat.self, PeerPath.self,  //
        NestDir.self, NestPeers.self,
      ],
      defaultSubcommand: BuildRunScript.self
    )
  }
  public init() {}

  public func run() async throws {
    let builder = ClutchDriver.Errors.ErrBuilder()
    throw builder.err(.programError("Running root, not default command"))
  }
}

// MARK: Nest commands
extension ClutchAP {
  struct NestDir: Script {
    public static let configuration = APHelp.config(
      "dir",
      abstract: "Emits path of nest directory to stdout",
      usage: "dir <Nest>"
    )
    @Argument(help: "nest name")
    var nest: NestModuleName

    func run() throws {
      let driver = ClutchDriver.make()
      let nestPaths = try driver.findNest(inputNestName: nest.nest.nest)
      let nestStat = nestPaths.nestStatus(using: driver.sysCalls)
      let status = nestStat[.nest]
      let suffix = status.status.isDir ? "" : " (missing)"
      driver.sysCalls.printOut("\(status.fullPath)\(suffix)")
    }
  }

  struct NestPeers: Script {
    public static let configuration = APHelp.config(
      "peers",
      abstract: "Emit nest peers to stdout",
      usage: "peers <Nest>"
    )
    @Argument(help: "nest name")
    var nest: NestModuleName

    func run() async throws {
      let driver = ClutchDriver.make()
      let nestPaths = try driver.findNest(inputNestName: nest.nest.nest)
      let nestStat = nestPaths.nestStatus(using: driver.sysCalls)
      // TODO: P1 hang on Shell integration
      // `: Script` - hang
      // `: Script, AsyncParsableCommand` - Script.swift:241: force-unwrap err
      let nameItems = try await driver.listPeersInNest(nestStat)
      let list =
        nameItems
        .map { $0.name }
        .sorted()
        .joined(separator: " ")
      driver.sysCalls.printOut("\(list)")
    }
  }
}

// MARK: build/run script
extension ClutchAP {

  /// Default action to run script after building as needed
  ///
  struct BuildRunScript: Script {  // Shell works here
    typealias AskKind = DriverConfig.UserAskKind
    public static let configuration = APHelp.config(
      "build/run",
      abstract: "Run script with args (create, update, and build as needed)",
      usage: "<script> {arg}..."
    )

    @Argument(help: "Script path")
    var script: String

    @Argument(parsing: .captureForPassthrough, help: "script path")
    var args: [String] = []

    func trace(_ s: String) {
      print("TRACE: \(s)")
    }
    func validate() throws {
      trace("BRV \(script) \(args)")
    }
    func run() async throws {
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
      let nestPaths = try driver.findNest(inputNestName: peer.nest)
      let peerNestStatus = try driver.makePeerNestStatus(
        nestPaths: nestPaths,
        peer: peer
      )
      let peerStatus = peerNestStatus.peerStatus
      let nestStatus = peerNestStatus.nestStatus
      let options = peerNestStatus.options

      try await driver.runScript(
        script: scriptItem,
        peerName: peer,
        nestStatus: nestStatus,
        peerStatus: peerStatus,
        options: options,
        args: args
      )
    }
  }
}

// MARK: Peer commands
extension ClutchAP {
  struct PeerModuleName: ExpressibleByArgument {
    let peer: ModuleName
    init?(argument: String) {
      let mn = ModuleName.make(argument, into: [.nameOnly, .nameNest])
      guard let mn = mn else {
        return nil
      }
      self.peer = mn
    }
  }
  struct NestModuleName: ExpressibleByArgument {
    let nest: ModuleName
    init?(argument: String) {
      guard let mn = ModuleName.make(argument, into: [.nestOnly]) else {
        return nil
      }
      self.nest = mn
    }
  }

  struct PeerCat: Script {
    public static let configuration = APHelp.config(
      "cat",
      abstract: "Emit peer source to stdout",
      usage: "cat <peer>{.<nest>}"
    )

    @Argument(help: "peer name")
    var peer: PeerModuleName

    func run() async throws {
      let driver = ClutchDriver.make()
      let peerModule = peer.peer
      let nestPaths = try driver.findNest(inputNestName: peerModule.nest)
      let peerNestStatus = try driver.makePeerNestStatus(
        nestPaths: nestPaths,
        peer: peerModule
      )
      typealias Builder = ClutchDriver.Errors.ErrBuilder
      let makeErr = Builder.local.setting(ask: .catPeer, args: [])
      let stat = peerNestStatus.peerStatus[.peer]
      guard stat.status.isFile else {
        let m = "No peer script for \(peerModule): \(stat)"
        throw makeErr.noFile(.peer, path: stat.fullPath, msg: m)
      }
      let content = try await driver.sysCalls.readFile(stat.fullPath)
      if content.count > 2 {
        let start = content.index(content.startIndex, offsetBy: 2)
        driver.sysCalls.printOut(String(content[start...]))
      } else {
        let m = "Empty peer script for \(peerModule): \(stat)"
        throw makeErr.errq(.invalidFile(m), .resource(.peer, stat.fullPath))
      }
    }
  }

  struct PeerPath: Script {
    public static let configuration = APHelp.config(
      "path",
      abstract: "Emit path of peer source to stdout",
      usage: "path <peer>{.<nest>}"
    )

    @Argument(help: "peer name")
    var peer: PeerModuleName

    func run() async throws {
      let driver = ClutchDriver.make()
      let peerMod = peer.peer
      let nestPaths = try driver.findNest(inputNestName: peerMod.nest)
      let peerNestStatus = try driver.makePeerNestStatus(
        nestPaths: nestPaths,
        peer: peerMod
      )
      let status = peerNestStatus.peerStatus[.peer]
      let suffix = status.status.isFile ? "" : " (missing)"
      driver.sysCalls.printOut("\(status.fullPath)\(suffix)")
    }
  }

  struct PeerRun: Script {
    public static let configuration = APHelp.config(
      "run",
      abstract: "Run peer with optional args",
      usage: "run <peer>{.<nest>} {arg}..."
    )

    @Argument(help: "peer name")
    var peer: PeerModuleName

    @Argument(parsing: .captureForPassthrough, help: "args")
    var args: [String] = []

    func run() async throws {
      let driver = ClutchDriver.make()
      let peerMod = peer.peer
      let nestPaths = try driver.findNest(inputNestName: peerMod.nest)
      let peerNestStatus = try driver.makePeerNestStatus(
        nestPaths: nestPaths,
        peer: peerMod
      )
      let peerStatus = peerNestStatus.peerStatus
      let nestStatus = peerNestStatus.nestStatus
      let options = peerNestStatus.options
      try await driver.buildRunPeer(
        peerMod: peerMod,
        peerSrc: peerStatus[.peer],
        nest: nestStatus[.nest],
        nestManifest: nestStatus[.manifest],
        binary: peerStatus[.executable],
        options: options,
        args: args
      )
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

// s6/SE-0364 permits fully-qualified-names to work for retroactive
extension ArgumentParser.CommandConfiguration: @unchecked Swift.Sendable {}

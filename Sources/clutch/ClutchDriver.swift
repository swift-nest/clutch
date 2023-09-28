import struct SystemPackage.FilePath

public typealias NestPathsStatus = DriverConfig.NestPathsStatus
public typealias NestPaths = DriverConfig.NestPaths
public typealias AskData = DriverConfig.UserAskKind
public typealias AskMode = DriverConfig.AskMode

public struct ClutchDriver {

  public static func make(
    logging: Bool? = false
  ) -> ClutchDriver {
    let sysCalls = FoundationScriptSystemCalls()
    var mode = logging ?? false ? AskMode.LOG : AskMode.QUIET
    mode = mode.with(logConfig: sysCalls.seekEnv(.NEST_LOG))
    return ClutchDriver(sysCalls: sysCalls, mode: mode)
  }
  /// Run clutch nest/script operations implied by input arguments.
  ///
  /// - Parameters:
  ///   - cwd: Current directory (for resolving relative paths)
  ///   - args: args per user docs
  public static func runMain(cwd: FilePath, args: [String]) async throws {
    let sysCalls = FoundationScriptSystemCalls()
    var (ask, mode) = AskData.read(args, cwd: cwd, sysCalls: sysCalls)
    mode = mode.with(logConfig: sysCalls.seekEnv(.NEST_LOG))
    let driver = ClutchDriver(sysCalls: sysCalls, mode: mode)
    try await driver.runAsk(cwd: cwd, args: args, ask: ask)
  }

  public let sysCalls: SystemCalls
  public let peerOp: PeerOp
  public let mode: AskMode

  init(sysCalls: SystemCalls, mode: AskMode) {
    self.sysCalls = sysCalls
    self.mode = mode
    self.peerOp = PeerOp(sysCalls)
  }

  typealias MakeErr = Problem.ErrBuilder
  typealias ClutchErr = Problem.ErrParts
  /// Run the user's ask using a builder.
  /// - Parameters:
  ///   - cwd: Current directory (for resolving relative paths)
  ///   - args: args per user docs (including first value)
  ///   - builder: Builder delegate
  ///   - ask: AskData
  public func runAsk(
    cwd: FilePath,
    args: [String],
    ask: AskData
  ) async throws {
    let makeErr = MakeErr.local
    makeErr.set(ask: ask.ask, args: args)
    let fileSeeker = FileItemSeeker(systemCalls: sysCalls)

    // emissions from runAsk(..)
    func programErr(_ err: String) -> ClutchErr {
      makeErr.err(reason: .programError(err))
    }
    func stdout(_ s: String) {
      sysCalls.printOut(s)
    }

    // FYI, each successful if-group exits the function

    // ---------- report errors
    if let askNote = ask.errorAskNote {
      switch askNote.ask {
      case .helpDetail: 
        stdout(Help.HELP)
        return
      case .helpSyntax: 
        stdout(Help.SYNTAX)
        return
      case .syntaxErr:
        throw makeErr.errq(.badSyntax(askNote.note))
      case .programErr:
        throw makeErr.errq(.programError(askNote.note))
      default:
        throw programErr("unknown error: \(askNote.note))")
      }
    }

    // All other operations require the nest
    let nestPaths = try findNest(inputNestName: ask.nestNameInput)

    // ---------- nest-only commands (don't require peer or build options)
    if let nestAsk = ask.commandNestAsk {
      let nestStat = nestPaths.nestStatus(using: sysCalls)  // no build options
      switch nestAsk.ask {
      case .nestDir:
        let status = nestStat[.nest]
        let suffix = status.status.isDir ? "" : " (missing)"
        stdout("\(status.fullPath)\(suffix)")
        return
      case .nestPeers:
        let nameItems = try await listPeersInNest(nestStat, fileSeeker)
        let list =
          nameItems
          .map { $0.name }
          .sorted()
          .joined(separator: " ")
        stdout("\(list)")
        return
      default:
        throw programErr("unknown nest command: \(nestAsk)")
      }
    }

    // Remaining script and peer commands require peer name and status
    guard let peerName = ask.peer else {
      throw programErr("not error or nest-only, but no peer name")
    }
    let psResult = try makePeerNestStatus(nestPaths: nestPaths, peer: peerName)
    let (peerModule, peerStat, nestStat, options)
      = psResult.asModulePeerNestOptions
    let peerArgs = Array(args[1...])

    // ---------- build/run script
    if let askScriptPeer = ask.scriptAskScriptPeer {
      try await runScript(
        script: askScriptPeer.script,
        peerName: peerModule,
        nestStatus: nestStat,
        peerStatus: peerStat,
        options: options,
        args: peerArgs
      )
      return
    }
    // ---------- only peer commands left
    guard let peerAsk = ask.commandPeerAsk else {
      throw programErr("Not error, script, or nest/script command: \(ask)")
    }
    switch peerAsk.ask {
    case .runPeer:
      try await buildRunPeer(
        peerMod: peerModule,
        peerSrc: peerStat[.peer],
        nest: nestStat[.nest],
        nestManifest: nestStat[.manifest],
        binary: peerStat[.executable],
        options: options,
        args: peerArgs
      )
      return
    case .catPeer:
      let stat = peerStat[.peer]
      guard stat.status.isFile else {
        let m = "No peer script for \(peerModule): \(stat)"
        throw makeErr.errq(.fileNotFound(m))
      }
      let content = try await sysCalls.readFile(stat.fullPath)
      if content.count > 2 {
        let start = content.index(content.startIndex, offsetBy: 2)
        stdout(String(content[start...]))
      }
      return
    case .pathPeer:
      let stat = peerStat[.peer]
      if stat.status.isFile {
        stdout(stat.fullPath)
      } // else return negative error code?
      return
    default:
      throw programErr("Unknown ask: \(ask)")
    }
    // preconditionFailure("Unreachable code")
  }

  /// Extract executables in the nest, in package declaration order.
  ///
  /// Not included are unexpected package declarations or declarations without source directories.
  /// - Parameters:
  ///   - nestStatus: NestPathsStatus
  ///   - fileSeeker: FileItemSeeker
  /// - Returns: Result of Array of (name, NestItem) tuple for name, peer source dir
  func listPeersInNest(
    _ nestStatus: NestPathsStatus,
    _ fileSeeker: FileItemSeeker
  ) async throws -> [(name: String, item: NestItem)] {
    let manifest = nestStatus[.manifest]
    if !manifest.status.isFile {
      let m = "\(manifest.fullPath)"
      throw MakeErr.local.errq(.fileNotFound(m), .resource(.manifest))
    }
    guard
      let namePeers = try await peerOp.listPeers(
        manifest,
        nestStatus[.nestSourcesDir]
      )
    else {
      let m = "Reading peers in \(manifest.fullPath)"
      throw MakeErr.local.errq(.operationFailed(m), .resource(.manifest))
    }
    return namePeers
  }

  /// create or update peer and build as needed, then run
  public func runScript(
    script: NestItem,
    peerName: ModuleName,
    nestStatus: NestPathsStatus,
    peerStatus: NestPathsStatus,
    options: PeerNest.BuildOptions,
    args: [String]
  ) async throws {
    let fileSeeker = FileItemSeeker(systemCalls: sysCalls)
    // skip script check as done already
    let peer = peerStatus[.peer]
    let updatedPeer: NestItem
    if peer.status.isFile {  // source existed
      if peer.lastModOr0 >= script.lastModOr0 {
        updatedPeer = peer
      } else {
        try await peerOp.updatePeerSource(script: script, peer: peer)
        updatedPeer = fileSeeker.seekFile(.peer, peer.fullPath)
      }
    } else {  // create source and package
      // run checks and throwing preparation before mutating operations
      let manifest = nestStatus[.manifest]
      if !manifest.status.isFile {
        let m = "No manifest in nest: \(nestStatus[.nest])"
        throw MakeErr.local.errq(.fileNotFound(m), .resource(.manifest))
      }
      let peerDir = peerStatus[.peerSourceDir]
      if peerDir.status.isDir {
        let m = "No peer source, but have peer dir: \(peerDir)"
        throw MakeErr.local.errq(.fileNotFound(m), .resource(.peer))
      }
      try sysCalls.createDir(peerDir.fullPath)

      // update manifest
      let maniPath = manifest.filePath
      async let didManifest = peerOp.addPeerToManifestFile(
        peerName,
        manifest: maniPath
      )

      // create peer
      async let newPeer = peerOp.newPeerSource(
        script: script.filePath,
        peerDir: peerDir.filePath,
        fileSeeker: fileSeeker
      )
      let okManifest = try await didManifest
      updatedPeer = try await newPeer
      if !okManifest {
        let m = "Unable to update manifest for \(peerName)"
        throw MakeErr.local.errq(.operationFailed(m), .resource(.manifest))
      }
      if !updatedPeer.status.isFile {
        let m = "Unable to create peer source for \(peerName)"
        throw MakeErr.local.errq(.operationFailed(m), .resource(.peer))
      }
    }

    try await buildRunPeer(
      peerMod: peerName,
      peerSrc: updatedPeer,
      nest: nestStatus[.nest],
      nestManifest: nestStatus[.manifest],
      binary: peerStatus[.executable],
      options: options,
      args: args
    )
  }

  public func findNest(inputNestName input: String?) throws -> NestPaths {
    let nest = DriverConfig.findNest(input, using: sysCalls)

    guard let nest = nest, nest.nest.status.isDir else {
      throw MakeErr.local.err(
        reason: .dirNotFound(input ?? ""),
        subject: .resource(.nest))
    }
    guard let nestModule = ModuleName.make(nest.name, into: .forNest) else {
      let err = "Invalid nest name: \(nest.name)"
      throw MakeErr.local.err(reason: .bad(err), subject: .resource(.nest))
    }
    if let error = nest.error {
      throw MakeErr.local.err(reason: .bad(error), subject: .resource(.nest))
    }
    return NestPaths(nestModule, nest.nest.filePath)
  }

  public func buildRunPeer(
    peerMod: ModuleName,
    peerSrc: NestItem,
    nest: NestItem,
    nestManifest: NestItem,
    binary: NestItem,
    options: PeerNest.BuildOptions,
    args: [String]
  ) async throws {
    var bin = binary
    if !binary.status.isFile || peerSrc.lastModOr0 > binary.lastModOr0 {
      let makeErr = MakeErr.local
      if !peerSrc.status.isFile {
        let m = "peer module (\(peerMod)) not in nest (\(nest))"
        throw makeErr.err(reason: .fileNotFound(m), subject: .resource(.peer))
      }
      if !nestManifest.status.isFile {
        let m = "manifest (\(nestManifest.fullPath)) not in nest (\(nest))"
        throw makeErr.err(reason: .fileNotFound(m), subject: .resource(.manifest))
      }
      let fileSeeker = FileItemSeeker(systemCalls: sysCalls)
      // urk: silly system calls: executable -> string -> executable
      let swift = try await sysCalls.findExecutable(named: "swift")
      let swiftItem = fileSeeker.seekFile(.swift, swift)
      if !swiftItem.status.isFile {
        throw makeErr.err(reason: .fileNotFound("swift"))
      }
      try await build(
        nestDir: nest.filePath,
        product: peerMod.name,
        options: options,
        swift: swiftItem
      )
      bin = fileSeeker.seekFile(.executable, bin.fullPath)
      guard bin.status.isFile else {
        throw makeErr.err(
          reason: .fileNotFound("\(bin)"),
          subject: .resource(.executable))
      }
    }

    try await runPeerBinary(bin, args: args)
  }

  public func runPeerBinary(
    _ bin: NestItem,
    args: [String]
  ) async throws {
    let makeErr = MakeErr.local
    makeErr.set(subject: .resource(.executable), part: .peerRun)
    guard bin.status.isFile else {
      throw makeErr.err(reason: .fileNotFound("\(bin)"))
    }
    try await sysCalls.runProcess(bin.fullPath, args: args)
  }

  func build(
    nestDir: FilePath,
    product: String,
    options: PeerNest.BuildOptions,
    swift: NestItem
  ) async throws {
    //makeErr.set(input: .resource(.peer), part: .swiftBuild)
    let d = nestDir
    var args = ["build", "--package-path", d.string, "--product", "\(product)"]
    args += options.args
    trace("build: swift \(args)")
    try await sysCalls.runProcess(swift.fullPath, args: args)
  }

  func trace(_ m: @autoclosure () -> String) {
    if mode.logProgressForUser {
      sysCalls.printErr("TRACE clutch: \(m())\n")
    }
  }

  public func makePeerNestStatus(
    nestPaths: NestPaths,
    peer: ModuleName
  ) throws -> PeerNestStatus {
    let nest = nestPaths.nestOnly
    guard let peerModule = peer.nameNest(nest) else {
      let err = "Need peer/nest, have \(peer)/\(nest.name)"
      throw MakeErr.local.err(reason: .bad(err), subject: .resource(.peer))
    }
    let options = PeerNest.BuildOptions.make(sysCalls.seekEnv(.NEST_BUILD))
    guard
      let peerStat = nestPaths.peerStatus(
        using: sysCalls,
        debug: options.debug,
        peer: peerModule
      )
    else {
      let err = "Program error: newly-invalid name \(peerModule)"
      throw MakeErr.local.err(reason: .programError(err))
    }
    let nestStat = nestPaths.nestStatus(using: sysCalls, debug: options.debug)
    return
      PeerNestStatus(
        peerModule: peerModule,
        peerStatus: peerStat,
        nestStatus: nestStat,
        options: options
      )
  }

  public struct PeerNestStatus {
    public typealias Options = PeerNest.BuildOptions
    public typealias Status = NestPathsStatus
    public typealias ModulePeerNestOptions = (
      name: ModuleName, peer: Status, nest: Status, options: Options
    )
    public let peerModule: ModuleName
    public let peerStatus: Status
    public let nestStatus: Status
    public let options: Options
    public var asModulePeerNestOptions: ModulePeerNestOptions {
      (peerModule, peerStatus, nestStatus, options)
    }
  }
}

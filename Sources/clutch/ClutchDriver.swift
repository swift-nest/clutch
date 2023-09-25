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
    let fileSeeker = FileItemSeeker(systemCalls: sysCalls)

    // emissions from runAsk(..)
    func programErr(_ err: String) -> Error {
      let cie = "Clutch internal error:"
      return Err.err("\(cie) \(err) processing args: \(args)")
    }
    func userErr(_ err: String) -> Error {
      Err.err("\(err)")
    }
    func userErr(_ err: Err) -> Error {  // fyi: passing through...
      err
    }
    func tryGet<T>(_ result: Result<T, Err>) throws -> T {
      switch result {
      case .success(let item): return item
      case .failure(let err): throw userErr(err)
      }
    }
    func stdout(_ s: String) {
      sysCalls.printOut(s)
    }

    // FYI, each successful if-group exits the function

    // ---------- report errors
    if let askNote = ask.errorAskNote {
      switch askNote.ask {
      case .helpDetail: throw userErr(Help.HELP)
      case .helpSyntax: throw userErr("\(Help.SYNTAX)")
      case .syntaxErr: throw userErr("\(askNote.note)\n\(Help.SYNTAX)")
      case .programErr: throw programErr(askNote.note)
      default:
        throw programErr("unknown error: \(askNote)")
      }
    }

    // All other operations require the nest
    let nestPaths = try tryGet(findNest(inputNestName: ask.nestNameInput))

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
        let nameItems = try await tryGet(listPeersInNest(nestStat, fileSeeker))
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
    let psResult = makePeerNestStatus(nestPaths: nestPaths, peer: peerName)
    let (peerModule, peerStat, nestStat, options) = try tryGet(psResult)
      .asModulePeerNestOptions
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
        binary: peerStat[.executable],
        options: options,
        args: peerArgs
      )
      return
    case .catPeer:
      let stat = peerStat[.peer]
      guard stat.status.isFile else {
        throw userErr("No peer script for \(peerModule): \(stat)")
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
  ) async throws -> Result<[(name: String, item: NestItem)], Err> {
    let manifest = nestStatus[.manifest]
    if !manifest.status.isFile {
      let err = "No manifest to read peers: \(manifest.fullPath)"
      return .failure(Err.err(err))
    }
    guard
      let namePeers = try await peerOp.listPeers(
        manifest,
        nestStatus[.nestSourcesDir]
      )
    else {
      let err = "Unable to read peers in \(manifest.fullPath)"
      return .failure(Err.err(err))
    }
    return .success(namePeers)
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
        throw Err.err("No manifest to update in nest: \(nestStatus[.nest])")
      }
      let peerDir = peerStatus[.peerSourceDir]
      if peerDir.status.isDir {
        throw Err.err("No peer source, but have peer dir: \(peerDir)")
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
        throw Err.err("Unable to update manifest for \(peerName)")
      }
      if !updatedPeer.status.isFile {
        throw Err.err("Unable to create peer source for \(peerName)")
      }
    }

    try await buildRunPeer(
      peerMod: peerName,
      peerSrc: updatedPeer,
      nest: nestStatus[.nest],
      binary: peerStatus[.executable],
      options: options,
      args: args
    )
  }

  public func findNest(inputNestName input: String?) -> Result<NestPaths, Err> {
    let nest = DriverConfig.findNest(input, using: sysCalls)
    guard let nest = nest, nest.nest.status.isDir else {
      let err = "No nest \(input ?? "").\nUse --help for guidance."
      return .failure(.err(err))
    }
    guard let nestModule = ModuleName.make(nest.name, into: .forNest) else {
      let err = "Invalid nest name: \(nest.name)"
      return .failure(.err(err))
    }
    let nestPaths = NestPaths(nestModule, nest.nest.filePath)
    return .success(nestPaths)
  }

  public func buildRunPeer(
    peerMod: ModuleName,
    peerSrc: NestItem,
    nest: NestItem,
    binary: NestItem,
    options: PeerNest.BuildOptions,
    args: [String]
  ) async throws {
    if !peerSrc.status.isFile {
      throw Err.err("peer module (\(peerMod)) not found in nest (\(nest))")
    }
    let fileSeeker = FileItemSeeker(systemCalls: sysCalls)
    var bin = binary
    if !binary.status.isFile || peerSrc.lastModOr0 > binary.lastModOr0 {
      // urk: silly system calls: executable -> string -> executable
      let swift = try await sysCalls.findExecutable(named: "swift")
      let swiftItem = fileSeeker.seekFile(.swift, swift)
      if !swiftItem.status.isFile {
        throw Err.err("Unable to find swift")
      }
      try await build(
        nestDir: nest.filePath,
        product: peerMod.name,
        options: options,
        swift: swiftItem
      )
      bin = try fileSeeker.findFile(.executable, bin.fullPath)
    }
    guard bin.status.isFile else {
      throw Err.err("Unable to build \(bin)")
    }

    try await runPeerBinary(bin, args: args)
  }

  public func runPeerBinary(
    _ bin: NestItem,
    args: [String]
  ) async throws {
    try await sysCalls.runProcess(bin.fullPath, args: args)
  }

  func build(
    nestDir: FilePath,
    product: String,
    options: PeerNest.BuildOptions,
    swift: NestItem
  ) async throws {
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
  ) -> Result<PeerNestStatus, Err> {
    let nest = nestPaths.nestOnly
    guard let peerModule = peer.nameNest(nest) else {
      return .failure(.err("Need peer/nest, have \(peer)/\(nest.name)"))
    }
    let options = PeerNest.BuildOptions.make(sysCalls.seekEnv(.NEST_BUILD))
    guard
      let peerStat = nestPaths.peerStatus(
        using: sysCalls,
        debug: options.debug,
        peer: peerModule
      )
    else {
      return .failure(.err("Program error: newly-invalid name \(peerModule)"))
    }
    let nestStat = nestPaths.nestStatus(using: sysCalls, debug: options.debug)
    return .success(
      PeerNestStatus(
        peerModule: peerModule,
        peerStatus: peerStat,
        nestStatus: nestStat,
        options: options
      )
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

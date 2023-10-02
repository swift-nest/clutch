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
    mode = mode.with(logConfig: sysCalls.seekEnv(.CLUTCH_LOG))
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
    mode = mode.with(logConfig: sysCalls.seekEnv(.CLUTCH_LOG))
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

  typealias MakeErr = Errors.ErrBuilder
  typealias ClutchErr = Errors.ErrParts
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

    // emissions from runAsk(..)
    func programErr(_ err: String) -> ClutchErr {
      makeErr.err(.programError(err))
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
        let nameItems = try await listPeersInNest(nestStat)
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
    let (peerModule, peerStat, nestStat, options) = psResult
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
        throw makeErr.noFile(.peer, path: stat.fullPath, msg: m)
      }
      let content = try await sysCalls.readFile(stat.fullPath)
      if content.count > 2 {
        let start = content.index(content.startIndex, offsetBy: 2)
        stdout(String(content[start...]))
      } else {
        let m = "Empty peer script for \(peerModule): \(stat)"
        throw makeErr.errq(.invalidFile(m), .resource(.peer, stat.fullPath))
      }
      return
    case .pathPeer:
      let stat = peerStat[.peer]
      if stat.status.isFile {
        stdout(stat.fullPath)
      }  // else return negative error code?
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
  public func listPeersInNest(
    _ nestStatus: NestPathsStatus
  ) async throws -> [(name: String, item: NestItem)] {
    let manifest = nestStatus[.manifest]
    let path = manifest.fullPath
    if !manifest.status.isFile {
      throw MakeErr.local.noFile(.manifest, path: path)
    }
    guard
      let namePeers = try await peerOp.listPeers(
        manifest,
        nestStatus[.nestSourcesDir]
      )
    else {
      let mg = "Reading peers in \(path)"
      throw MakeErr.local.fail(.manifest, path: path, msg: mg)
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
      let path = manifest.fullPath
      if !manifest.status.isFile {
        let m = "No manifest in nest: \(nestStatus[.nest])"
        throw MakeErr.local.noFile(.manifest, path: path, msg: m)
      }
      let peerDir = peerStatus[.peerSourceDir]
      if peerDir.status.isDir {
        let m = "No peer source, but have peer dir: \(peerDir)"
        throw MakeErr.local.noFile(.peer, path: peer.fullPath, msg: m)
      }
      let dirPath = peerDir.fullPath
      let makeErr = MakeErr.local
      let createDirErr = makeErr.setting(
        subject: .resource(.peerSourceDir, dirPath),
        agent: .system
      )
      try createDirErr.runAsTaskLocal {
        try sysCalls.createDir(dirPath)
      }

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
      if !okManifest {
        let m = "Unable to update manifest for \(peerName)"
        throw makeErr.fail(.manifest, path: maniPath.string, msg: m)
      }
      updatedPeer = try await newPeer
      if !updatedPeer.status.isFile {
        let m = "Unable to create peer source for \(peerName)"
        throw makeErr.fail(.peer, path: peerDir.filePath.string, msg: m)
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
        .dirNotFound(input ?? ""),
        subject: .resource(.nest, input ?? "")
      )
    }
    let nestStr = nest.nest.fullPath
    guard let nestModule = ModuleName.make(nest.name, into: [.nestOnly]) else {
      let err = "Invalid nest name: \(nest.name)"
      throw MakeErr.local.fail(.nest, path: nestStr, msg: err)
    }
    if let error = nest.error {
      throw MakeErr.local.fail(.nest, path: nestStr, msg: error)
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
        throw makeErr.noFile(.executable, path: binary.fullPath, msg: m)
      }
      if !nestManifest.status.isFile {
        let m = "manifest not found in nest (\(nest))"
        throw makeErr.noFile(.manifest, path: nestManifest.fullPath, msg: m)
      }
      let fileSeeker = FileItemSeeker(systemCalls: sysCalls)
      // urk: silly system calls: executable -> string -> executable
      let swift = try await sysCalls.findExecutable(named: "swift")
      let swiftItem = fileSeeker.seekFile(.swift, swift)
      if !swiftItem.status.isFile {
        throw makeErr.noFile(.swift, path: "", msg: "not on PATH?")
      }
      try await build(
        nestDir: nest.filePath,
        product: peerMod.name,
        options: options,
        swift: swiftItem
      )
      bin = fileSeeker.seekFile(.executable, bin.fullPath)
      guard bin.status.isFile else {
        let m = "No binary found after build completed normally?"
        throw makeErr.noFile(.executable, path: bin.fullPath, msg: m)
      }
    }

    try await runPeerBinary(bin, args: args)
  }

  public func runPeerBinary(
    _ bin: NestItem,
    args: [String]
  ) async throws {
    let makeErr = MakeErr.local
    let path = bin.fullPath
    makeErr.set(subject: .resource(.executable, path), agent: .peerRun)
    guard bin.status.isFile else {
      throw makeErr.noFile(.executable, path: path)
    }
    trace("run: \(path) \(args)")
    let next = MakeErr.local.setting(agent: .peerRun, args: args)
    try await next.runAsyncTaskLocal {
      try await sysCalls.runProcess(path, args: args)
    }
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
    let next = MakeErr.local.setting(
      subject: .resource(.peer, "\(product) in nest \(nestDir.string)"),
      agent: .swiftBuild,
      args: args)
    trace("build: \(swift.fullPath) \(args)")
    try await next.runAsyncTaskLocal {
      try await sysCalls.runProcess(swift.fullPath, args: args)
    }
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
      throw MakeErr.local.fail(.nest, path: "", msg: err)
    }
    let options = PeerNest.BuildOptions.make(sysCalls.seekEnv(.CLUTCH_BUILD))
    guard
      let peerStat = nestPaths.peerStatus(
        using: sysCalls,
        debug: options.debug,
        peer: peerModule
      )
    else {
      let err = "Program error: newly-invalid name \(peerModule)"
      throw MakeErr.local.err(.programError(err))
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

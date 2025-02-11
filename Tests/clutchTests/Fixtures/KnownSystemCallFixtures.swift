import clutchLib

/// Configure ``KnownSystemCalls`` for ``ClutchCommandScenario``.
class KnownSystemCallFixtures {
  typealias Content = EnvSystemCallFixtureContent
  typealias Ask = DriverConfig.UserAsk
  let isDir = true
  let isFile = false
  let HOME = "/ESCF_HOME"
  let dirSep = "/"  // urk

  class ScenarioCase {
    static func sc(
      _ scenario: ClutchCommandScenario,
      _ calls: KnownSystemCalls,
      _ args: ScenarioArgs,
      _ checks: [Check]
    ) -> Self {
      Self(
        scenario: scenario,
        calls: calls,
        args: args,
        checks: checks
      )
    }
    let scenario: ClutchCommandScenario
    let calls: KnownSystemCalls
    var args: ScenarioArgs
    var checks: [Check]
    var pass = true
    required init(
      scenario: ClutchCommandScenario,
      calls: KnownSystemCalls,
      args: ScenarioArgs,
      checks: [Check]
    ) {
      self.scenario = scenario
      self.calls = calls
      self.args = args
      self.checks = checks
    }
    public func with(
      args: [String]? = nil,
      checks: [Check]? = nil
    ) {
      if let args {
        self.args = self.args.with(args: args)
      }
      if let checks {
        self.checks = checks
      }
    }
  }
  /// Configure ``KnownSystemCalls`` for ``ClutchCommandScenario``.
  ///
  /// Errors are reported in ``KnownSystemCalls/internalErrors``
  public func newScenario(
    _ scenario: ClutchCommandScenario,
    name: String? = nil
  ) -> ScenarioCase {
    let nest = "Nest"
    let module = "script"
    let env = KnownSystemCalls()
    env.scenarioName = name ?? scenario.name
    homeEnv(env)
    nestBase(env, nest: nest)
    let (scriptPath, scriptFilename, scriptMod, code) =
      scriptPathFilenameLastModCode(env, filename: module, lastMod: .t3)
    let (_, _, _, _) = (scriptPath, scriptFilename, scriptMod, code)

    let args: [String]  // every branch must set
    var checks = [Check]()

    func makeArgs() -> ScenarioArgs {
      ScenarioArgs(
        module: module,
        nest: nest,
        scriptPath: scriptPath,
        args: args
      )
    }
    func commandArgs(_ ask: Ask, _ suffix: String) -> [String] {
      if let prefix = ask.prefix {
        return ["\(prefix)\(suffix)"]
      }
      env.internalError("Expected prefix in ask: \(ask)/\(suffix)")
      return ["seeError-\(suffix)"]
    }

    switch scenario {
    case .script(let script):
      args = [scriptPath]
      if script != .uptodate {
        checks.append(.sysCall(.runProcess, "\"--product\", \"\(module)\""))
      }
      switch script {
      case .uptodate:
        let peerMod = scriptMod.next()
        let binMod = peerMod.next()
        nestPeers(env, nest: nest, peerMod: peerMod, peers: module)
        executables(env, nest: nest, binLastMod: binMod, peers: module)
      case .binaryGone:
        nestPeers(env, nest: nest, peerMod: scriptMod.next(), peers: module)
      case .binaryStale:
        nestPeers(env, nest: nest, peerMod: scriptMod.next(), peers: module)
        executables(env, nest: nest, binLastMod: scriptMod, peers: module)
      case .peerStale:
        nestPeers(env, nest: nest, peerMod: scriptMod.prior(), peers: module)
        checks.append(.sysCall(.writeFile, module))  // TODO: more precisely
      case .new:
        nestPeers(env, nest: nest)  // with no peers, initializes Package.swift
        checks.append(.sysCall(.writeFile, module))  // TODO: more precisely
        checks.append(.sysCall(.createDir, module))
        checks.append(.sysCall(.writeFile, "Package.swift"))
      }
    case .nest(let nestCommand):
      switch nestCommand {
      case .dir:
        args = commandArgs(.nestDir, nest)
        checks.append(.sysCall(.printOut, "Nest"))  // TODO: more precisely...
      case .peers:
        args = commandArgs(.nestPeers, nest)
        nestPeers(env, nest: nest, peerMod: scriptMod.next(), peers: "p1", "p2")
        checks.append(.sysCall(.printOut, "p1 p2"))
      }
    case .peer(let peerCommand):
      switch peerCommand {
      case .cat:
        args = commandArgs(.catPeer, module)
        let sc = newScenario(.script(.peerStale), name: scenario.name)
        checks.append(.sysCall(.printOut, Content.minCodeBody))
        return .sc(sc.scenario, sc.calls, makeArgs(), checks)
      case .run:
        args = commandArgs(.runPeer, module)
        let sc = newScenario(.script(.uptodate), name: scenario.name)
        checks.append(.sysCall(.runProcess, module))  // TODO: more precisely...
        return .sc(sc.scenario, sc.calls, makeArgs(), checks)
      case .path:
        args = commandArgs(.pathPeer, module)
        let sc = newScenario(.script(.uptodate), name: scenario.name)
        checks.append(.sysCall(.printOut, ".swift"))  // TODO: more precisely...
        return .sc(sc.scenario, sc.calls, makeArgs(), checks)
      }
    }
    return .sc(scenario, env, makeArgs(), checks)
  }

  func scriptPathFilenameLastModCode(
    _ env: KnownSystemCalls,
    filename: String = "script",
    content: String = Content.minScript,
    lastMod: LastModified = .ZERO
  ) -> (path: String, filename: String, lastMod: LastModified, code: String) {
    let key = home(["scripts", filename])
    env.fileStatus[key] = isFile
    env.fileLastModified[key] = lastMod.value
    env.fileContent[key] = content
    return (key, filename, lastMod, content)
  }

  func executables(
    _ env: KnownSystemCalls,
    nest: String,
    binLastMod: LastModified,
    isDebug: Bool = true,
    peers: String...
  ) {
    let dirKey = home([nest, ".build", isDebug ? "debug" : "release"])
    for peer in peers {
      let binKey = dirKey + dirSep + peer
      env.fileStatus[binKey] = isFile
      env.fileLastModified[binKey] = binLastMod.value
    }
  }

  /// Initialize the environment outside the nest: home, swift, git dir.
  func homeEnv(_ env: KnownSystemCalls) {
    env.envKeyValue["HOME"] = "\(HOME)"
    let swiftPath = home(["bin", "swift"])
    env.executableNamePath["swift"] = swiftPath
    env.fileStatus["\(HOME)"] = isDir
    env.fileStatus[swiftPath] = isFile
    env.fileStatus[home(["git"])] = isDir
  }

  /// Initialize a nest directory
  func nestBase(
    _ env: KnownSystemCalls,
    rpath: [String] = ["git"],
    nest: String
  ) {
    let toNest = rpath + [nest]
    let toBuild = toNest + [".build"]
    let toSources = toNest + ["Sources"]
    env.fileStatus[home(toNest)] = isDir
    env.fileStatus[home(toSources)] = isDir
    env.fileStatus[home(toBuild)] = isDir
    env.fileStatus[home(toBuild + ["debug"])] = isDir
    env.fileStatus[home(toBuild + ["release"])] = isDir
  }

  /// Add peer source files, creating or updating `Package.swift`.
  ///
  /// This reads the initial package from the environment (unless `clearPackage`).
  /// When called with no peers, this initializes the minimal package or re-installs the existing package.
  func nestPeers(
    _ env: KnownSystemCalls,
    nest: String,
    peerMod: LastModified? = nil,
    clearPackage: Bool = false,
    peers: String...
  ) {
    let addPeerToPackage = PeerOp.addPeerToPackageBeforeRegex
    let src = ["git", nest, "Sources"]
    let packageKey = home(["git", nest, "Package.swift"])
    var package =
      clearPackage
      ? Content.minPackage
      : env.fileContent[packageKey] ?? Content.minPackage
    for peer in peers {
      env.fileStatus[home(src + [peer])] = isDir
      let srcKey = home(src + [peer, "main.swift"])
      env.fileStatus[srcKey] = isFile
      if let date = peerMod {
        env.fileLastModified[srcKey] = date.value
        env.fileContent[srcKey] = Content.minCode
      }
      let nextPackage = addPeerToPackage(peer, nest, package)
      if let next = nextPackage {
        package = next
      } else {
        reportError(env, "Unable to add \(peer).\(nest) to package\n\(package)")
      }
    }
    env.fileContent[packageKey] = package
    env.fileStatus[packageKey] = isFile
  }

  func home(_ path: [String]) -> String {
    "\(HOME)\(dirSep)\(path.joined(separator: dirSep))"
  }

  func reportError(
    _ env: KnownSystemCalls,
    _ message: String = "unknown",
    file: StaticString = #file,
    line: UInt = #line
  ) {
    env.internalError(message, file: file, line: line)
  }
  enum Check: Equatable, CustomStringConvertible {
    case sysCall(SystemCallsFunc, String)
    case errPart(ErrPartCheck)
    case error(String)

    var isError: Bool {
      0 > index
    }

    // ------- CustomStringConvertible
    var description: String {
      "\(name)(\(match))"
    }

    var match: String {
      switch self {
      case let .sysCall(call, match): return "\(call)(\"\(match))"
      case let .errPart(check): return "\(check)"
      case let .error(match): return "\"\(match)\""
      }
    }
    var name: String {
      Self.NAMES[index + Self.ERR_COUNT]
    }
    var index: Int {
      switch self {
      case .sysCall: return 0
      case .errPart: return -1
      case .error: return -2
      }
    }

    static let NAMES = ["error", "errPart", "sysCall"]
    static let ERR_COUNT = 2
  }
  struct ScenarioCheck: CustomStringConvertible {
    static func ck(_ call: SystemCallsFunc, _ match: String) -> Self {
      Self(call: call, match: match)
    }
    let call: SystemCallsFunc
    let match: String
    var description: String {
      "\(call) expecting \(match)"
    }
  }
  struct ScenarioArgs {
    let module: String
    let nest: String
    let scriptPath: String
    let args: [String]
    func with(
      module: String? = nil,
      nest: String? = nil,
      scriptPath: String? = nil,
      args: [String]? = nil
    ) -> Self {
      ScenarioArgs(
        module: module ?? self.module,
        nest: nest ?? self.nest,
        scriptPath: scriptPath ?? self.scriptPath,
        args: args ?? self.args
      )
    }
  }
}

extension [KnownSystemCallFixtures.Check] {
  var errParts: [ErrPartCheck] {
    compactMap {
      if case let .errPart(err) = $0 {
        return err
      }
      return nil
    }
  }
  var errors: [(label: String, match: String)] {
    compactMap { next in
      if case let .error(match) = next {
        return ("\(next)", match)
      }
      return nil
    }
  }
  var scenarios: [KnownSystemCallFixtures.ScenarioCheck] {
    compactMap { next in
      if case let .sysCall(funct, match) = next {
        return .init(call: funct, match: match)
      }
      return nil
    }
  }
}
extension LastModified {
  fileprivate static let t0: LastModified = 0.0
  fileprivate static let t1: LastModified = 1.0
  fileprivate static let t2: LastModified = 2.0
  fileprivate static let t3: LastModified = 3.0
  fileprivate static let t4: LastModified = 4.0

  fileprivate func next() -> LastModified {
    LastModified(floatLiteral: value + 1.0)
  }
  fileprivate func prior() -> LastModified {
    LastModified(floatLiteral: value - 1.0)
  }
}

enum EnvSystemCallFixtureContent {
  static let minScript =
    """
    \(hashBang)
    \(minCodeBody)
    """

  static let minCode =
    """
    //\(hashBang)
    \(minCodeBody)
    """
  static let minCodeBody = "print(\"hello\")"
  private static let hashBang = "#!/usr/bin/env swift"

  static let minPackage =
    """
    // swift-tools-version: 5.6

    import PackageDescription

    let package = Package(
      name: "Nest",
      platforms: [.macOS(.v12)],
      products: [
        .library(name: "Nest", targets: ["Nest"]),
      ],
      targets: [
        .target(name: "Nest"),
      ]
    )

    """
}

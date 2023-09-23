import clutchLib

/// Configure ``KnownSystemCalls`` for ``ClutchCommandScenario``.
class KnownSystemCallFixtures {
  typealias Content = EnvSystemCallFixtureContent
  typealias Ask = DriverConfig.UserAsk
  let isDir = true
  let isFile = false
  let HOME = "/ESCF_HOME"
  let dirSep = "/"  // urk

  /// Configure ``KnownSystemCalls`` for ``ClutchCommandScenario``.
  ///
  /// Errors are reported in ``KnownSystemCalls/internalErrors``
  public func newScenario(
    _ scenario: ClutchCommandScenario,
    name: String? = nil
  ) -> (calls: KnownSystemCalls, args: ScenarioArgs, checks: [ScenarioCheck]) {
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
    var checks = [ScenarioCheck]()

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
        checks.append(.ck(.runProcess, "\"--product\", \"\(module)\""))
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
        checks.append(.ck(.writeFile, module))  // TODO: more precisely
      case .new:
        nestPeers(env, nest: nest)  // with no peers, initializes Package.swift
        checks.append(.ck(.writeFile, module))  // TODO: more precisely
        checks.append(.ck(.createDir, module))
        checks.append(.ck(.writeFile, "Package.swift"))
      }
    case .nest(let nestCommand):
      switch nestCommand {
      case .dir:
        args = commandArgs(.nestDir, nest)
        checks.append(.ck(.printOut, "Nest"))  // TODO: more precisely...
      case .peers:
        args = commandArgs(.nestPeers, nest)
        nestPeers(env, nest: nest, peerMod: scriptMod.next(), peers: "p1", "p2")
        checks.append(.ck(.printOut, "p1 p2"))
      }
    case .peer(let peerCommand):
      switch peerCommand {
      case .cat:
        args = commandArgs(.catPeer, module)
        let (env2, _, _) = newScenario(.script(.peerStale), name: scenario.name)
        checks.append(.ck(.printOut, Content.minCodeBody))
        return (env2, makeArgs(), checks)
      case .run:
        args = commandArgs(.runPeer, module)
        let (env2, _, _) = newScenario(.script(.uptodate), name: scenario.name)
        checks.append(.ck(.runProcess, module))  // TODO: more precisely...
        return (env2, makeArgs(), checks)
      case .path:
        args = commandArgs(.pathPeer, module)
        let (env2, _, _) = newScenario(.script(.uptodate), name: scenario.name)
        checks.append(.ck(.printOut, ".swift"))  // TODO: more precisely...
        return (env2, makeArgs(), checks)
      }
    }
    return (env, makeArgs(), checks)
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

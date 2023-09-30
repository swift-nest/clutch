import SystemPackage

private typealias ScriptParts = ScriptFilenameParts

extension DriverConfig.UserAskKind {
  public typealias AskData = Self
  public typealias AskMode = DriverConfig.AskMode
  public typealias UserAsk = DriverConfig.UserAsk
  public enum AskErr: Error {
    case scriptNotFile
    case scriptEmptyFilename
    case scriptNotModuleName
    var text: String {
      switch self {
      case .scriptNotFile: return "File not found"
      case .scriptEmptyFilename: return "Empty path or dir"
      case .scriptNotModuleName: return "No valid module name"
      }
    }
  }
  public static func readScript(
    script: String,
    cwd: FilePath,
    sysCalls: SystemCalls
  ) -> Result<Self, AskErr> {
    // -------- scripts are paths, possibly relative
    let (path, status) = sysCalls.resolve(script, cwd: cwd)
    guard status.isFile else {
      return .failure(.scriptNotFile)
    }
    let filePath = FilePath(path)
    guard let fileParts = filePath.lastComponent, !fileParts.stem.isEmpty else {
      return .failure(.scriptEmptyFilename)
    }
    let parts = ScriptParts.make(fileParts.string)
    guard let name = ModuleName.nameNest(parts.module, nest: parts.nest) else {
      return .failure(.scriptNotModuleName)
    }
    let lastMod = sysCalls.lastModified(path)
    let scriptItem = NestItem(
      key: .script,
      filePath: filePath,
      status: status,
      lastModified: lastMod
    )
    return .success(.script(.script, scriptItem, name))
  }
  public static func read(
    _ args: [String],
    cwd: FilePath,
    sysCalls: SystemCalls
  ) -> (Self, AskMode) {
    var askMode = AskMode.QUIET
    func withMode(_ result: Self) -> (Self, AskMode) {
      if result.ask.isProgramError && !askMode.logProgressForUser {
        askMode = askMode.with(logProgressForUser: true)
      }
      return (result, askMode)
    }
    guard let first = args.first, !first.isEmpty else {
      return withMode(.error(.helpSyntax, "No argument"))
    }
    if first.hasPrefix("--h") || first.hasPrefix("-h") {
      return withMode(.error(.helpDetail, "Help requested"))  // handled by arg parser
    }

    func syntaxErr(_ ask: UserAsk, _ err: String) -> Self {
      .error(.syntaxErr, "\(ask) \(err) in \(first)")
    }
    // -------- scripts are paths, possibly relative
    switch Self.readScript(script: first, cwd: cwd, sysCalls: sysCalls) {
    case .success(let result):
      return withMode(result)
    case .failure(let askErr):
      switch askErr {
      case .scriptEmptyFilename:
        return withMode(syntaxErr(.script, askErr.text))
      case .scriptNotModuleName:
        return withMode(syntaxErr(.script, askErr.text))
      case .scriptNotFile:
        // when it looks like a file, but is not found
        if first.hasSuffix(".swift") || first.contains("/")
          || 1 < FilePath(first).components.count
        {
          return withMode(syntaxErr(.script, askErr.text))
        }
        break  // otw continue to check for commands
      }
    }

    // -------- run-peer without - (i.e., not a command)
    if !first.contains("-") {
      let ask = UserAsk.runPeer
      if let mn = ModuleName.make(first, into: [.nameOnly, .nameNest]) {
        return withMode(.commandPeer(ask, mn))
      }
      return withMode(syntaxErr(ask, "Invalid module name"))
    }
    // -------- commands: cat-n, n-from-n.M, peers-N, config-N, etc

    let forNest = true
    let forMod = !forNest

    /// Handle `<prefix>-name{.Nest}`
    /// Non-nil result when have prefix (error or valid result)
    /// - Parameters:
    ///   - userAsk: UserAsk to construct command for nest or peer
    ///   - forNest: Bool if true, require unqualified names; else permit name.Nest
    ///   - prefx: String prefix of first to check
    /// - Returns: nil if unmatched, syntax error if invalid or result otherwise
    func prefixAsk(
      _ userAsk: UserAsk,
      _ forNest: Bool,
      _ prefx: String
    ) -> AskData? {
      guard first.hasPrefix(prefx) else {
        return nil
      }
      let start = first.index(first.startIndex, offsetBy: prefx.count)
      let suffix = first[start...]
      if forNest {
        if let mn = ModuleName.make(suffix, into: [.nestOnly]) {
          return .commandNest(userAsk, mn)
        }
        return syntaxErr(userAsk, "expected nest, got \(suffix)")
      }
      if let mn = ModuleName.make(suffix, into: [.nameOnly, .nameNest]) {
        return .commandPeer(userAsk, mn)
      }
      return syntaxErr(userAsk, "expected module, got \(suffix)")
    }
    for ask in UserAsk.nestCommands {
      if let result = prefixAsk(ask, forNest, ask.prefix ?? "Bug!") {
        return withMode(result)
      }
    }
    for ask in UserAsk.peerCommands {
      if let result = prefixAsk(ask, forMod, ask.prefix ?? "Bug!") {
        return withMode(result)
      }
    }
    return withMode(syntaxErr(.helpSyntax, "Unknown `-` form"))
  }
}

/// Split script filename into parts for module/nest extraction
struct ScriptFilenameParts: Equatable, CustomStringConvertible {
  /// full name
  public let filename: String
  /// prefix to separator
  public let module: String
  /// suffix from separator (ignoring .swift)
  public let nest: String?
  /// Filename has "swift" extension (ignoring case)
  public let hasSwiftExtension: Bool
  /// nil or "swift" (even if filename ends with ".SWIFT")
  public var ext: String? {
    hasSwiftExtension ? "swift" : nil
  }
  init(
    _ filename: String,
    swift hasSwiftExtension: Bool,
    module: String,
    nest: String? = nil
  ) {
    self.filename = filename
    self.hasSwiftExtension = hasSwiftExtension
    self.module = module.isEmpty ? filename : module
    self.nest = (nest ?? "").isEmpty ? nil : nest
  }
  public var description: String {
    "f: \(filename) m: \(module) n: \(nest ?? "") e: \(ext ?? "")"
  }

  static func make(_ filename: String) -> Self {
    let parts = filename.components(separatedBy: ["."])
    if 1 == parts.count {
      return Self(filename, swift: false, module: filename)
    }
    let module = parts[0]
    let last = parts[parts.count - 1]
    let have3 = parts.count > 2
    let hasSwift = "swift".caseInsensitiveCompare(last) == .orderedSame
    let nest = !hasSwift ? last : (have3 ? parts[parts.count - 2] : "")
    return Self(filename, swift: hasSwift, module: module, nest: nest)
  }
}

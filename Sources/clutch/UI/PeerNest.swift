public typealias NestKey = PeerNest.ResourceKey

public struct PeerNest {

  /// Summary of resource accessed
  public enum ResourceKey:
    String, FileKey, CaseIterable, CustomStringConvertible
  {
    /// Script source file
    case script

    /// Base directory of nest
    case nest
    case manifest, nestSourcesDir, nestBinDir

    /// Peer source file
    case peer
    case peerSourceDir, executable

    /// User home
    case HOME
    case swift

    public var status: FileStatus {
      switch self {
      case .script: return .file
      case .nest: return .dir
      case .manifest: return .file
      case .nestSourcesDir: return .dir
      case .nestBinDir: return .dir
      case .peer: return .file
      case .peerSourceDir: return .dir
      case .executable: return .file
      case .HOME: return .dir
      case .swift: return .file
      }
    }
    public var description: String {
      str
    }

    public var str: String { rawValue }

    public var filenames: [String] {
      switch self {
      case .manifest: return ["Package.swift"]
      case .nestSourcesDir: return ["Sources"]
      case .nestBinDir: return ["debug", "release"]
      case .peer: return ["main.swift"]
      case .swift: return ["swift"]
      default: return []
      }
    }
  }

  public struct BuildOptions {
    static let DEFAULT = BuildOptions(
      config: "",
      debug: true,
      args: ["-c", "debug", "--quiet"]
    )
    static func make(_ config: String?) -> Self {
      guard let config = config, !config.isEmpty else {
        return Self.DEFAULT
      }
      let (debug, args) = parse(config)
      return Self(config: config, debug: debug, args: args)
    }
    public let config: String
    public let debug: Bool
    public let args: [String]

    /// Two modes of configuration to avoid defaults (debug, quiet)
    /// - leading `@`: split on `@` and include all
    /// - `release` to escape debug, and/or `loud` or `verbose` to escape quiet
    public static func parse(
      _ config: String
    ) -> (debug: Bool, args: [String]) {
      if config.isEmpty {
        return (true, Self.DEFAULT.args)
      }
      let first = config.first!
      if first == "@" {
        let args = config.split(separator: "@").map { String($0) }
        if !args.isEmpty {
          let debug = !args.contains("release")
          return (debug, args)
        }
      }
      let debug = !config.contains("release")
      let verbose = config.contains("verbose")
      let quiet = !verbose && !config.contains("loud")
      if !debug || !quiet {
        var args = ["-c", debug ? "debug" : "release"]
        if quiet {
          args.append("--quiet")
        } else if verbose {
          args.append("--verbose")
        }
        return (debug, args)
      }
      // default for empty or failed other tests
      return (Self.DEFAULT.debug, Self.DEFAULT.args)
    }
  }

  public enum EnvName: String, CaseIterable {
    typealias Source = (PeerNest.EnvName) -> String?
    /// path overrides all others
    case NEST_PATH
    /// Base directory for nest sub-directory projects
    case NEST_BASE
    /// Nest name from the environment
    case NEST_NAME
    /// HOME directory from the environment (if no path or base)
    case HOME
    /// Relative path from HOME for nest base directory (containing nest directories)
    case NEST_HOME_RPATH
    /// Nest logging instructions from the environment
    case NEST_LOG
    /// Nest build instructions (as parsed by ``BuildOptions``)
    case NEST_BUILD

    /// Product declaration in Package.swift goes in next line after this tag
    static let TAG_PRODUCT = "CLUTCH_PRODUCT"
    /// Target declaration in Package.swift goes in next line after this tag
    static let TAG_TARGET = "CLUTCH_TARGET"

    var key: String { rawValue }

    static func makeErrorContext(
      withValues: Bool = false,
      prefix: String = "Env[",
      lead: String = "\n  ",
      infix: String = " = ",
      nilValue: String = "nil",
      delimiter: String = "",
      suffix: String = "\n  ]",
      _ source: Source
    ) -> String {
      var result = prefix
      allCases.forEach {
        let value = withValues ? "\(infix)\(source($0) ?? nilValue)" : ""
        result += "\(lead)\($0.key)\(value)\(delimiter)"
      }
      result += suffix
      return result
    }
  }

  struct EnvValues: CustomStringConvertible {
    static func readAll(from source: EnvName.Source) -> EnvValues {
      .init(Set(EnvName.allCases), from: source)
    }

    let nameValue: [EnvName: String]

    init(_ names: Set<EnvName>, from source: EnvName.Source) {
      nameValue = Dict.from(names, source)
    }
    /// Returns value only if not empty
    subscript(key: EnvName) -> String? {
      Str.emptyToNil(nameValue[key])
    }

    var description: String {
      errInfo()
    }
    func errInfo(withValues: Bool = false) -> String {
      EnvName.makeErrorContext(withValues: withValues) { self[$0] }
    }
    func asSource() -> EnvName.Source {
      { self[$0] }
    }
  }
}
extension SystemCalls {
  func seekEnv(_ key: PeerNest.EnvName) -> String? {
    environment(Set([key.key])).first?.value
  }
}

extension DriverConfig {
  /// Clutch operations as requested/provoked by user
  public enum UserAsk: Equatable, CaseIterable {
    /// Build/run script with peer in nest
    case script  // filepath, ModuleName.forModule

    // ------------------- peer commands
    // commands - must have ModuleName, and get Nest
    /// Run existing peer in nest by name
    case runPeer  // name, {Nest}
    /// Emit existing peer source to stdout (to initialize another script)
    case catPeer  // ModuleName
    /// Emit path to source source file
    case pathPeer  // ModuleName

    // ------------------- nest-only commands
    /// List peers available in nest
    case nestPeers
    /// Emit resolved path to Nest
    case nestDir

    // --------- help and errors
    case helpDetail  // requested
    case helpSyntax  // requested
    case syntaxErr  // help needed, with message
    case programErr  // programming error

    static let allScript: [Self] = [.script]
    static let allHelp: [Self] = [.helpDetail, .helpSyntax]
    static let allErrors: [Self] = [.syntaxErr, .programErr]
    static let nestCommands: [Self] = [.nestPeers, .nestDir]
    static let peerCommands: [Self] = [.runPeer, .catPeer, .pathPeer]
    static let allCommands: [Self] = nestCommands + peerCommands

    public var prefix: String? {
      switch self {
      case .catPeer: return "cat-"
      case .runPeer: return "run-"  // but unqualified name is run
      case .pathPeer: return "path-"
      case .nestDir: return "dir-"
      case .nestPeers: return "peers-"
      default: return nil
      }
    }
    var isScript: Bool {
      Self.allErrors.contains(self)
    }
    var isError: Bool {
      Self.allErrors.contains(self)
    }
    var isProgramError: Bool {
      self == .programErr
    }
    var isHelp: Bool {
      Self.allHelp.contains(self)
    }
    var isFeedback: Bool {
      isHelp || isError
    }
    var isNestOnly: Bool {
      Self.nestCommands.contains(self)
    }
  }
}

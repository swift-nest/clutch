@testable import clutchLib

/// Use pre-defined results to conform to ``SystemCalls``, do effects, and capture calls and errors.
///
/// Errors encountered while initializing the known calls are reported in ``internalErrors``.
/// Tests should check and not proceed when there are internal errors.
///
/// Effects:
/// - on writeFile: file is created
/// - on createDir: directory is created
/// - on runProcess (if swift build): peer binary is created
///
/// Errors thrown (by `injectErr()`)
/// - on findExecutable, if not found
/// - on readFile, if not found
///
/// Warnings are reported:
/// - on writeFile, if the file existed before
/// -
/// Limitations
/// - on readFile, this doesn't support throwing injected errors
/// - on writeFile if prior, last-mod-time is incremented by 1.  Is that predictable/usable enough?
/// - Single-threaded only; marked as Sendable, but NOT
class KnownSystemCalls {
  // hmm: not Encodable d/t StaticString in SrcLoc

  typealias EnvName = PeerNest.EnvName

  // SystemCalls API results (user sets directly)
  public var envKeyValue = [String: String]()
  public var fileStatus = [String: Bool]()
  public var fileLastModified = [String: Double]()
  public var fileContent = [String: String]()
  public var executableNamePath = [String: String]()

  // SystemCalls with input to capture
  typealias RanProcess = (path: String, args: [String])
  public private(set) var dirsCreated = [String]()
  public private(set) var fileWrites = [String: String]()
  public private(set) var runProcesses = [RanProcess]()
  public private(set) var out = [String]()
  public private(set) var err = [String]()

  // Our internal status and configuration
  public private(set) var messages = [String]()
  public private(set) var internalErrors = [(String, SrcLoc)]()
  public private(set) var internalWarnings = [String]()
  public var internalErrorPrefix = ""
  public var scenarioName = ""
  public let printMessages: Bool
  public let passBuild: Bool

  init(printMessages: Bool = false, passBuild: Bool = true) {
    self.printMessages = printMessages
    self.passBuild = passBuild
  }

  func injectErr(message: String) -> Err {
    Err.err(message)
  }
  func copyInit() -> KnownSystemCalls {
    let result = KnownSystemCalls(
      printMessages: self.printMessages,
      passBuild: self.passBuild
    )
    result.envKeyValue = self.envKeyValue
    result.fileStatus = self.fileStatus
    result.fileLastModified = self.fileLastModified
    result.fileContent = self.fileContent
    result.executableNamePath = self.executableNamePath
    return result
  }
}

// MARK: internal error reporting
extension KnownSystemCalls {
  func internalError(
    _ message: String = "unknown",
    file: StaticString = #file,
    line: UInt = #line
  ) {
    let i = internalErrors.count
    let srcLoc = SrcLoc(index: i, prefix: internalErrorPrefix, file, line)
    internalErrors.append((message, srcLoc))
  }
}

// MARK: set and clear state
extension KnownSystemCalls {
  static let IS_DIR = FileStatus.dir.asBool
  static let IS_FILE = FileStatus.file.asBool
  func setEnv(_ kv: [EnvName: String], clear: Bool = false) {
    if clear {
      envKeyValue.removeAll()
    }
    kv.forEach { (key, value) in envKeyValue[key.key] = value }
  }

  func setDirs(_ kv: [String], clear: Bool = false) {
    if clear {
      fileStatus.removeAll()
    }
    kv.forEach { fileStatus[$0] = Self.IS_DIR }
  }

  func clearKnownCalls() {
    envKeyValue.removeAll(keepingCapacity: true)
    fileStatus.removeAll(keepingCapacity: true)
    fileLastModified.removeAll(keepingCapacity: true)
    fileContent.removeAll(keepingCapacity: true)
    executableNamePath.removeAll(keepingCapacity: true)
  }

  func clearCapturedState() {
    dirsCreated.removeAll(keepingCapacity: true)
    fileWrites.removeAll(keepingCapacity: true)
    runProcesses.removeAll(keepingCapacity: true)
    out.removeAll(keepingCapacity: true)
    err.removeAll(keepingCapacity: true)
  }

  func clearInternalState() {
    messages.removeAll(keepingCapacity: true)
    internalErrors.removeAll(keepingCapacity: true)
    internalWarnings.removeAll(keepingCapacity: true)
  }
}

// MARK: SystemCalls conformance
// NOT actually sendable, but not sent?
extension KnownSystemCalls: @unchecked Sendable {}  // generally single-threaded?
extension KnownSystemCalls: SystemCallsSendable {}

extension KnownSystemCalls: SystemCalls {
  func createDir(_ path: String) throws {
    fileStatus[path] = Self.IS_DIR
    dirsCreated.append(path)
  }

  func environment(_ keys: Set<String>) -> [String: String] {
    Dict.from(keys) { envKeyValue[$0] }
  }

  func fileStatus(_ path: String) -> Bool? {
    fileStatus[path]
  }

  func findExecutable(named name: String) async throws -> String {
    guard let result = executableNamePath[name] else {
      throw injectErr(message: "Executable not found: \(name)")
    }
    return result
  }

  func lastModified(_ path: String) -> LastModified? {
    if let value = fileLastModified[path] {
      return LastModified(floatLiteral: value)
    }
    return nil
  }

  func now() -> LastModified {
    FS.now()
  }

  func printErr(_ message: String) {
    err.append(message)
  }

  func printOut(_ message: String) {
    out.append(message)
  }

  func readFile(_ path: String) async throws -> String {
    guard let result = fileContent[path] else {
      throw injectErr(message: "File not found: \(path)")
    }
    return result
  }

  /// If ``KnownSystemCalls/passBuild``, create binary on `swift build ...`
  func runProcess(_ path: String, args: [String]) async throws {
    runProcesses.append((path, args))
    // runProcess(path: ".../swift",
    // args: ["build", "--package-path", "/ESCF_HOME/git/Nest",
    // "--product", "rebuild", "-c", "debug", "--quiet"])
    let isBuild = path.hasSuffix("swift") && args.count > 6
    if passBuild && isBuild {
      let nestDir = args[2]
      let peerName = args[4]
      let buildDir = args[6]
      let path = "\(nestDir)/.build/\(buildDir)/\(peerName)"
      fileStatus[path] = Self.IS_FILE
      fileLastModified[path] = now().value
    }
  }

  func writeFile(path: String, content: String) async throws {
    if let prior = fileWrites[path] {
      let warning = "Overwriting write[\(prior.count)] of \(path)"
      internalWarnings.append(warning)
    }
    fileWrites[path] = content
    if let prior = fileContent[path] {
      let prefix = "Overwriting content [\(prior.count) - \(content.count)]"
      internalWarnings.append("\(prefix): \(path)")
    }
    fileContent[path] = content
    fileStatus[path] = Self.IS_FILE
    if let lastMod = fileLastModified[path] {
      fileLastModified[path] = lastMod + 1.0  // TODO: last-mod increment size
    }
  }
}
// MARK: injecting behavior by modifying state
extension KnownSystemCalls {
  @discardableResult
  func configEnv(_ state: EnvName, _ value: String?) -> String? {
    let result = envKeyValue[state.key]
    envKeyValue[state.key] = value
    return result
  }
}
// MARK: injecting errors by modifying state
extension KnownSystemCalls {
  func findPaths(_ matching: PeerNest.ResourceKey) -> [String] {
    var result = [String]()
    func matches(_ path: String, filename: String) -> Bool {
      path.hasSuffix(filename) && fileStatus[path] == matching.status.asBool
    }
    for filename in matching.filenames {
      result += fileStatus.keys.filter { matches($0, filename: filename) }
    }
    if matching == .script && result.isEmpty {
      for name in ["script.swift", "script"] {  // urk: scenario defaults
        // error: picks out binary, too
        result += fileStatus.keys.filter { matches($0, filename: name) }
        if !result.isEmpty {
          break
        }
      }
    }
    return result
  }

  @discardableResult
  func remove(
    _ resource: PeerNest.ResourceKey,
    deleteMany: Bool = false
  ) -> Bool {
    let paths = findPaths(resource)
    if paths.isEmpty || (!deleteMany && paths.count > 1) {
      return false
    }
    for path in paths {
      if !removeFileOrDir(path: path) {
        return false
      }
    }
    return true
  }
  @discardableResult
  func setFileDetails(
    _ resource: PeerNest.ResourceKey,
    clearAll: Bool = false,
    content: String? = nil,
    lastMod: Double? = nil
  ) -> Bool {
    let paths = findPaths(resource)
    if 1 != paths.count {
      return false
    }
    return setFileDetails(
      path: paths[0],
      clearAll: clearAll,
      content: content,
      lastMod: lastMod
    )
  }

  @discardableResult
  func setFileDetails(
    path: String,
    clearAll: Bool = false,
    content: String? = nil,
    lastMod: Double? = nil,
    status: FileStatus? = nil
  ) -> Bool {
    if clearAll {
      fileContent[path] = nil
      fileLastModified[path] = nil
    }
    if let content = content {
      fileContent[path] = content
    }
    if let lastMod = lastMod {
      fileLastModified[path] = lastMod
    }
    if let status = status {
      fileStatus[path] = status.asBool
    }
    return true
  }

  @discardableResult
  func removeFileOrDir(path: String) -> Bool {
    let result =
      nil != fileStatus[path]
      || nil != fileLastModified[path]
      || nil != fileContent[path]
    fileStatus[path] = nil
    fileLastModified[path] = nil
    fileContent[path] = nil
    return result
  }
}

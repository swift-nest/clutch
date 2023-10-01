import Foundation // Date, FileManager, ProcessInfo, URL; contains, fputs, range 
import Script

/// Given script, run executable from nest
/// after creating, updating, and/or building as needed.
///
/// This captures steps and emits to stderr on failure.
///
/// Script name must be one or two segments (ignoring `swift` suffix).
/// If two, then the second suffix is the name of the nest (e.g., `MyNest`).
/// The nest package is in `HOME/git/Nest` or `HOME/git/MyNest`.
/// Script and nest name should be valid module names (identifiers).
@main public struct Clatch: Script {
  private static let name = "clatch"
  public init() {}

  @Argument(
    parsing: .captureForPassthrough,
    help: "Script full path and any run arguments")
  var args: [String] = []

  public func run() async throws {

    // Exit with error
    func errExit(_ err: String) -> Never {
      fputs("\(err)\n", stderr)
      enum Err: Error {
        case err(String)
      }
      Self.exit(withError: Err.err(err))
    }
    guard !args.isEmpty, let first = args.first,
      let peer = Peer.make(from: first)
    else {
      errExit("\(Self.name) {scriptFile}")
    }

    // capture stage traces and dump on error
    var completedNormally = false
    var traces = [String]() // or `@escaping () -> String` with terminal map...
    func trace(_ s: String) {
      traces.append(s)
    }
    defer {
      if !completedNormally {
        fputs(traces.joined(separator: "\n"), stderr)
      }
    }
    trace("peer: \(peer)")
    switch peer.stage {
    case .noScript:
      errExit("No script")
    case .create:
      trace("create manifest in: \(peer.nestPath.string)")
      guard try await Manifest.update(peer: peer) else {
        errExit("Unable to update manifest")
      } // hmm: do manifest and new-source at same time?
      let peerSourceDir = peer.sourcePath.removingLastComponent().string
      trace("create dir in: \(peerSourceDir)")
      try FileManager.default.createDirectory(
        atPath: peerSourceDir,
        withIntermediateDirectories: true
      )
      fallthrough
    case .update:
      trace("read script in: \(peer.scriptPath.string)")
      let script = try await contents(of: peer.scriptPath)
      var path = peer.sourcePath
      if script.contains("@main") {
        path = peer.sourcePath.removingLastComponent().appending(
          "\(peer.name).swift"
        )
      }
      trace("Write peer to: \(path.string)")
      try await write("//\(script)", to: path)
      fallthrough
    case .build:
      var args = [
        "build", "--product", peer.name,
        "--package-path", peer.nestPath.string,
      ]
      // Assuming the build-time compiler is the run-time SPM
      // --quiet added to spm in #5988 12/21/22, released in 5.8
      #if compiler(>=5.8)
      	args += [ "--quiet", "-c", "debug" ]
      #else
      	args += [ "-c", "debug" ]
      #endif
      trace("swift \(args)")
      try await execute("swift", arguments: args)
      fallthrough
    case .run:
      let toolArgs = args[1...].map { String($0) }
      trace("\(peer.name) \(toolArgs)")
      let tool = Executable(path: peer.binaryPath)
      try await tool(arguments: toolArgs)
    }
    completedNormally = true
  }
}

enum Manifest {
  static func update(peer: Peer) async throws -> Bool {
    guard let nest = peer.nestPath.lastComponent?.string, !nest.isEmpty else {
      return false
    }
    let manifest = peer.nestPath.appending("Package.swift")
    let code = try await contents(of: manifest)
    guard let newCode = seekAdd(peer: peer.name, nest: nest, code: code) else {
      return false
    }
    try await write(newCode, to: manifest)
    return true
  }

  private static func seekAdd(
    peer: String,
    nest: String,
    code: String
  ) -> String? {
    let end = code.endIndex
    func eolAfter(_ query: String, _ from: String.Index) -> String.Index? {
      if let range = code.range(of: query, range: from..<end) {
        return code.range(of: "\n", range: range.upperBound..<end)?.upperBound
      }
      return nil
    }
    guard let prod = eolAfter(#"products: ["#, code.startIndex),
      let pack = eolAfter(#"  targets: ["#, prod)
    else {
      return nil
    }
    return add(code, peer: peer, nest: nest, product: prod, package: pack)
  }
  private static func add(
    _ code: String,
    peer: String,
    nest: String,
    product: String.Index,
    package: String.Index
  ) -> String {
    precondition(code.startIndex < product)
    precondition(product < package)
    precondition(package < code.endIndex)
    let lead = "    .executable"
    var out = String(code[code.startIndex..<product])
    out += "\(lead)(name: \"\(peer)\", targets: [\"\(peer)\"]),\n"
    out += String(code[product..<package])
    out += "\(lead)Target(name: \"\(peer)\", dependencies: [\"\(nest)\"]),\n"
    out += String(code[package...])
    return out
  }
}
/// Peer nest paths and dates, identifying ``Peer/Stage-swift.enum`` of operation
struct Peer {
  enum Stage {
    case run, build, update, create, noScript
  }
  let name: String
  let scriptPath: FilePath
  let nestPath: FilePath
  let sourcePath: FilePath
  let binaryPath: FilePath
  let scriptModified: Date
  let sourceModified: Date
  let binaryModified: Date
  let stage: Stage

  static func make(from script: String) -> Peer? {
    guard let home = ProcessInfo.processInfo.environment["HOME"] else {
      return nil
    }
    let path = FilePath(script)
    guard let filename = path.lastComponent, !filename.string.isEmpty else {
      return nil
    }
    var name: String
    var nest = "Nest"
    if "swift" == filename.extension {
      name = filename.stem
    } else {
      name = filename.string
    }
    if let dotLoc = name.firstIndex(where: { "." == $0 }) {
      nest = String(name[name.index(after: dotLoc)...])
      name = String(name[name.startIndex..<dotLoc])
    }
    let nestPath = FilePath(home).appending("git").appending(nest)
    let sourceDir = nestPath.appending("Sources").appending(name)
    let binaryPath = nestPath.appending(".build").appending("debug").appending(
      name
    )
    let scriptDate = lastModified(script)
    let binaryDate = lastModified(binaryPath.string)
    // main.swift  or name.swift if n/a (b/c `@main` in code)
    var sourcePath = sourceDir.appending("main.swift")
    var sourceDate = lastModified(sourcePath.string)
    if .zero == sourceDate.timeIntervalSinceReferenceDate {
      sourcePath = sourceDir.appending("\(name).swift")
      sourceDate = lastModified(sourcePath.string)
    }
    return Peer(
      name: name,
      scriptPath: path,
      nestPath: nestPath,
      sourcePath: sourcePath,
      binaryPath: binaryPath,
      scriptModified: scriptDate,
      sourceModified: sourceDate,
      binaryModified: binaryDate,
      stage: stage(script: scriptDate, source: sourceDate, binary: binaryDate)
    )
  }

  private static func lastModified(_ path: String) -> Date {
    let url = URL(fileURLWithPath: path)
    let keys: Set<URLResourceKey> = [.contentModificationDateKey]
    guard let value = try? url.resourceValues(forKeys: keys),
          let date = value.contentModificationDate
    else {
      return Date(timeIntervalSinceReferenceDate: .zero)
    }
    return date
  }

  private static func stage(
    script: Date,
    source: Date,
    binary: Date
  ) -> Stage {
    if .zero == script.timeIntervalSinceReferenceDate {
      return .noScript
    }
    if .zero == source.timeIntervalSinceReferenceDate {
      return .create
    }
    if script > source {
      return .update
    }
    if .zero == binary.timeIntervalSinceReferenceDate || source > binary {
      return .build
    }
    return .run
  }
}

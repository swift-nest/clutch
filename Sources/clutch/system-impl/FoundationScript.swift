// @preconcurrency: on Linux, stderr flagged as mutable static
#if os(Linux)
@preconcurrency import Foundation
#else
// Date FileManager fputs LocalizedError ObjcBool ProcessInfo  URLResourceKey
import Foundation
#endif

typealias FS = FoundationScript

/// Delegate for ``SystemCalls`` depending on Foundation and Script.
///
/// TODO: printOut add a newline, but printErr does not
enum FoundationScript {
  static func now() -> LastModified {
    Date().asLastModified
  }

  static func printErr(_ message: String) {
    //    if let data = message.data(using: .utf8) {
    //      FileHandle.standardError.write(data) // Foundation
    //    }
    fputs(message, stderr)  // Darwin
  }

  static func printOut(_ message: String) {
    print(message)
  }

  static func createDir(_ path: String) throws {
    try FileManager.default.createDirectory(
      atPath: path,
      withIntermediateDirectories: true
    )
  }

  static func lastMod(_ path: String) -> LastModified? {
    let url = URL(fileURLWithPath: path)
    let keys: Set<URLResourceKey> = [.contentModificationDateKey]
    guard let value = try? url.resourceValues(forKeys: keys),
      let date = value.contentModificationDate
    else {
      return nil
    }
    return date.asLastModified
  }

  static func environment(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key]
  }

  static func environment(_ keys: Set<String>) -> [String: String] {
    let env = ProcessInfo.processInfo.environment
    return Dict.from(keys) { env[$0] }
  }

  static func runProcess(_ path: String, args: [String]) async throws {
    guard let url = fileUrl(path, checkExists: true) else {
      throw Err.noPath(path)
    }
    let result = Foundation.Process()
    result.executableURL = url
    result.arguments = args
    try result.run()
    result.waitUntilExit()
  }

  static func readFile(_ path: String) async throws -> String {
    guard let url = fileUrl(path) else {
      throw Err.noUrl(path)
    }
    return try String(contentsOf: url, encoding: .utf8)
  }

  static func writeFile(path: String, content: String) async throws {
    try content.write(toFile: path, atomically: true, encoding: .utf8)
  }

  static func findExecutable(named name: String) async throws -> String {
    func byUrl(_ path: String) -> String? {
      guard let url = fileUrl(path, checkExists: true) else {
        return nil
      }
      return urlString(url)
    }
    if let result = byUrl(name) {
      return result
    }
    guard let path = ProcessInfo.processInfo.environment["PATH"] else {
      throw Err.noPath(name)
    }
    let roots = path.split(whereSeparator: {
      //":" == $0
      58 == $0.asciiValue
    }).map({ ss in String(ss) })
    for root in roots {
      if let result = byUrl("\(root)/\(name)") {
        return result
      }
    }
    throw Err.notOnPath(name)
  }

  static func fileStatus(_ path: String) -> Bool? {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
      return isDir.boolValue
    }
    return nil
  }

  private static func urlString(_ url: URL) -> String {
#if os(Linux)
      return url.path
#else
    if #available(macOS 13.0, *) {
      return url.path(percentEncoded: false)
    } else {
      return url.path
    }
#endif
  }

  private static func newFileUrl(_ path: String) -> URL? {
    #if os(Linux)
      return URL(string: "file://\(path)")
    #else
      if #unavailable(macOS 13.0) {
        return NSURL(fileURLWithPath: path).absoluteURL
      } else {
        return URL(filePath: path)
      }
    #endif
  }

  static func fileUrl(
    _ path: String,
    checkExists: Bool = false
  ) -> URL? {
    guard !checkExists || false == fileStatus(path) else {
      return nil
    }
    return newFileUrl(path)
  }

  enum Err: Error {
    case noUrl(_ path: String)
    case noPath(_ tool: String)
    case notOnPath(_ tool: String)
  }
}

extension Date {
  var asLastModified: LastModified {
    .from(timeIntervalSinceReferenceDate)
  }
}

extension Err: LocalizedError {
  public var errorDescription: String? {
    if case let .err(s) = self {
      return s
    }
    return nil
  }
}

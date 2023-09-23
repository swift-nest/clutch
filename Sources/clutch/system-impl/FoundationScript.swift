// Date FileManager fputs LocalizedError ObjcBool ProcessInfo  URLResourceKey
import Foundation
import Script

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
    let command = Executable(path: FilePath(path))
    try await command(arguments: args)
  }

  static func readFile(_ path: String) async throws -> String {
    try await contents(of: FilePath(path))
  }

  static func writeFile(path: String, content: String) async throws {
    try await write(content, to: FilePath(path))
  }

  static func findExecutable(named name: String) async throws -> String {
    try await executable(named: name).path.string
  }

  static func fileStatus(_ path: String) -> Bool? {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
      return isDir.boolValue
    }
    return nil
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

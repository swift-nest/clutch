
/// Abstract system calls for testability
public protocol SystemCalls {
  func createDir(_ path: String) throws
  func environment(_ keys: Set<String>) -> [String: String]
  func fileStatus(_ path: String) -> Bool?
  func findExecutable(named: String) async throws -> String
  func lastModified(_ path: String) -> LastModified?
  func now() -> LastModified
  func printErr(_ message: String)
  func printOut(_ message: String)
  func readFile(_ path: String) async throws -> String
  func runProcess(_ path: String, args: [String]) async throws
  func writeFile(path: String, content: String) async throws
}
extension SystemCalls {
  func seekFileStatus(_ path: String) -> FileStatus {
    let status = fileStatus(path)
    return nil == status ? .NA : (status! ? .dir : .file)
  }
}

/// Like iOS, time in seconds since some consistent reference date
public struct LastModified: ExpressibleByFloatLiteral, Comparable, Sendable {
  public static let ZERO = LastModified(floatLiteral: .zero)

  public static func from(_ value: FloatLiteralType) -> LastModified {
    Self(floatLiteral: value)
  }

  public typealias FloatLiteralType = Double

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.value < rhs.value
  }

  public let value: FloatLiteralType

  public init(floatLiteral value: FloatLiteralType) {
    self.value = value
  }
}

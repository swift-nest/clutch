#if swift(>=6)
  import struct SystemPackage.FilePath
#else
  @preconcurrency import struct SystemPackage.FilePath
#endif

// s6/SE-0364 permits fully-qualified-names to work for retroactive
extension SystemPackage.FilePath: @unchecked Swift.Sendable {}

public protocol FileKey: Hashable, Sendable {
  var str: String { get }  // TODO: rename
}
public struct FileItem<Key: FileKey>: CustomStringConvertible, Sendable {

  public let key: Key
  public let filePath: FilePath
  public let status: FileStatus
  public let lastModified: LastModified?
  public var lastModOr0: LastModified {
    lastModified ?? .ZERO
  }
  public var fullPath: String { filePath.string }
  public func update(status: FileStatus, lastMod: LastModified?) -> FileItem {
    FileItem(
      key: key,
      filePath: filePath,
      status: status,
      lastModified: lastMod ?? self.lastModified
    )
  }
  public var description: String {
    "\(key)[\(status)] \(filePath.string)"
  }
}

public enum FileStatus: CustomStringConvertible, Sendable {
  case file, dir, NA
  public var asBool: Bool? {
    isDir ? true : (isFile ? false : nil)
  }
  public var isFile: Bool { .file == self }
  public var isDir: Bool { .dir == self }
  public var isNA: Bool { .NA == self }
  public var exists: Bool { .NA != self }
  public var description: String { isFile ? "file" : (isDir ? "dir" : "NA") }
}

struct FileItemSeeker {
  let systemCalls: SystemCalls

  public func seek<Key: FileKey>(
    kind: FileStatus = .file,
    NestKey: Key,
    _ path: String,
    status: FileStatus? = nil
  ) -> FileItem<Key> {
    seekImpl(kind, NestKey, path, false, status: status)
  }

  func seekImpl<Key: FileKey>(
    _ kind: FileStatus = .file,
    _ NestKey: Key,
    _ input: String,
    _ required: Bool,
    status: FileStatus? = nil
  ) -> FileItem<Key> {
    let status = status ?? systemCalls.seekFileStatus(input)
    let filePath = FilePath(input)
    let lastModified = !status.exists ? nil : systemCalls.lastModified(input)
    return FileItem(
      key: NestKey,
      filePath: filePath,
      status: status,
      lastModified: lastModified
    )
  }
}

extension FilePath {
  static let DOT_DIR = FilePath(".")
}

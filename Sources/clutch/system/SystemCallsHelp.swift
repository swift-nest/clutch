import SystemPackage

extension SystemCalls {
  /// Resolve path as absolute or relative to the working directory.
  func resolve(
    _ path: String,
    cwd: FilePath
  ) -> (String, FileStatus) {
    guard !path.isEmpty else {
      return (path, .NA)
    }
    let result = seekFileStatus(path)
    if result.exists {
      return (path, result)
    }
    let rel = cwd.pushing(FilePath(path))
    let relPath = rel.string
    return (relPath, seekFileStatus(relPath))
  }
}

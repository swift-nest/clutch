import struct MinSys.FilePath

extension DriverConfig {
  /// Nest directories and files (excluding peer)
  public struct NestPaths {
    public let nestOnly: ModuleName
    public let nestDir: FilePath
    init(_ nestOnly: ModuleName, _ nestDir: FilePath) {
      self.nestOnly = nestOnly
      self.nestDir = nestDir
      precondition(nestOnly.kind == .nestOnly, "Nest only")
      // ? also require dirname be nest name?
    }
    public var manifest: FilePath {
      nestDir.appending("Package.swift")
    }
    public var sourcesDir: FilePath {
      nestDir.appending("Sources")
    }
    public func binaryDir(debug: Bool) -> FilePath {
      nestDir.appending(".build").appending(debug ? "debug" : "release")
    }
  }
}

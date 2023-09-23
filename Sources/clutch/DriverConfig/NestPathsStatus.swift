import struct SystemPackage.FilePath

public typealias NestItem = FileItem<PeerNest.ResourceKey>

extension DriverConfig {

  /// Status of nest directories and files, accessed via ``NestKey``
  public struct NestPathsStatus {
    let NestKeyItem: [NestKey: NestItem]
    init(_ items: [NestItem]) {
      let kv = items.map { ($0.key, $0) }
      self.NestKeyItem = Dictionary(kv, uniquingKeysWith: { f, l in f })
    }
    private init(_ NestKeyItem: [NestKey: NestItem]) {
      self.NestKeyItem = NestKeyItem
    }

    /// Return actual or default .NA (with `.` nominal path)
    public subscript(_ NestKey: NestKey) -> NestItem {
      NestKeyItem[NestKey] ?? NestKey.NA
    }

    public func adding(items: [NestItem]) -> NestPathsStatus {
      if items.isEmpty {
        return self
      }
      var next = NestKeyItem
      items.forEach { next[$0.key] = $0 }
      return .init(next)
    }
  }
}

extension NestKey {
  fileprivate var NA: NestItem {
    NestItem(
      key: self,
      filePath: .DOT_DIR,
      status: .NA,
      lastModified: nil
    )
  }
}

extension DriverConfig.NestPaths {
  public typealias NestPathsStatus = DriverConfig.NestPathsStatus
  /// Evaluate current status of expected nest manifest and directories.
  ///
  /// The binary directory is created as needed by swift build,
  /// so its status is particularly transitory.
  /// - Parameters:
  ///   - sysCalls: SystemCalls for checking paths
  ///   - debug: Bool to evaluate the binary directory (debug or release)
  /// - Returns: ``NestPathsStatus
  public func nestStatus(
    using sysCalls: SystemCalls,
    debug: Bool? = nil
  ) -> NestPathsStatus {
    let seeker = FileItemSeeker(systemCalls: sysCalls)
    let nest = seeker.seekDir(.nest, nestDir.string)
    if !nest.status.isDir {
      return .init([nest])
    }
    let nestManifestSources = [
      nest,
      seeker.seekFile(.manifest, manifest.string),
      seeker.seekDir(.nestSourcesDir, sourcesDir.string),
    ]
    guard let debug = debug else {
      return .init(nestManifestSources)
    }
    let binDir = seeker.seekDir(.nestBinDir, binaryDir(debug: debug).string)
    return .init(nestManifestSources + [binDir])
  }
  /// Evaluate status of expected peer directory, source, and executable in a nest.
  /// - Parameters:
  ///   - sysCalls: SystemCalls for checking paths
  ///   - debug: Bool to get directory to evaluate the executable
  ///   - peer: ModuleName for the peer (return nil if not ``ModuleName/Kind/nameNest``)
  /// - Returns: ``NestPathsStatus``, after checking for source and executable, if peer valid
  public func peerStatus(
    using sysCalls: SystemCalls,
    debug: Bool? = nil,
    peer: ModuleName
  ) -> NestPathsStatus? {
    guard peer.kind == .nameNest else {
      return nil
    }
    let seeker = FileItemSeeker(systemCalls: sysCalls)
    let srcDir = sourcesDir.appending(peer.name)
    let srcStat = seeker.seekDir(.peerSourceDir, srcDir.string)
    var result = [srcStat]
    if srcStat.status.isDir {
      for name in ["main", peer.name] {
        let path = srcDir.appending("\(name).swift").string
        let src = seeker.seekFile(.peer, path)
        if src.status.isFile {
          result.append(src)
          break
        }
      }
    }
    if let debug = debug {
      let bin = binaryDir(debug: debug).appending(peer.name)
      result.append(seeker.seekFile(.executable, bin.string))
    }
    return .init(result)
  }
}

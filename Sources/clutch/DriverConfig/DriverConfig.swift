typealias FoundNest = (nest: NestItem, name: String, error: String?)

/// Namespace for configuration
public enum DriverConfig {
  typealias EnvName = PeerNest.EnvName
  /// Find nest path, searching:
  ///
  /// - path: env.path
  /// - base+name, where:
  /// - base: env.base, env.home+env.rpath:-git
  /// - name: script.name, env.name, default:-Nest
  static func findNest(
    _ nestNameFromScript: String?,
    using clutchSystem: SystemCalls
  ) -> FoundNest? {
    var error: String? = nil
    let seeker = FileItemSeeker(systemCalls: clutchSystem)
    func envVar(_ key: PeerNest.EnvName) -> String? {
      clutchSystem.seekEnv(key)
    }
    // NEST_PATH trumps all
    if let path = envVar(.NEST_PATH) {
      let nest = seeker.seekDir(.nest, path)
      if nest.status.isDir,
        let name = nest.filePath.lastComponent?.string,
        !name.isEmpty
      {
        if let scName = nestNameFromScript, !scName.isEmpty {
          error = "Using \(EnvName.NEST_PATH.key) but script nest is \(scName)"
          return (nest, name, error)
        }
        return (nest, name, nil)
      }
    }

    func notEmpty(_ s: [String?]) -> [String] {
      s.compactMap(Str.emptyToNil)
    }
    // Check candidate names under proposed base directories
    let names = notEmpty([nestNameFromScript, envVar(.NEST_NAME), "Nest"])

    func tryBaseDir(_ basePath: String?) -> FoundNest? {
      guard let path = basePath, !path.isEmpty else {
        return nil
      }
      let base = seeker.seekDir(.nest, path)
      if base.status.isDir {
        for (i, name) in names.enumerated() {
          let nestPath = base.filePath.appending(name).string
          let nest = seeker.seekDir(.nest, nestPath)
          if nest.status.isDir {
            if i > 0 {
              error = "Found nest ignoring names \(names[0..<i])"
            }
            return (nest, name, error)
          }
        }
      }
      return nil
    }

    // Base directory candidates are NEST_BASE, HOME + (RPATH | git)
    var baseDirs = [String]()
    if let rpath = envVar(.NEST_BASE) {
      baseDirs.append(rpath)
    }
    if let homePath = envVar(.HOME),
      let home = seeker.seekDirOrNil(.HOME, homePath)
    {
      if let rpath = envVar(.NEST_HOME_RPATH) {
        baseDirs.append(home.filePath.appending(rpath).string)
      }
      baseDirs.append(home.filePath.appending("git").string)
    }
    for (i, baseDir) in baseDirs.enumerated() {
      if let result = tryBaseDir(baseDir) {
        if 0 == i {
          return result
        }
        let dirErr = "Found nest after trying base dirs \(baseDirs[0..<i])"
        guard let prior = result.error else {
          return (result.nest, result.name, dirErr)
        }
        return (result.nest, result.name, "\(prior); \(dirErr)")
      }
    }
    return nil
  }
}

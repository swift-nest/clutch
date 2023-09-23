typealias FoundNest = (nest: NestItem, name: String)

/// Namespace for configuration
public enum DriverConfig {
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
        return (nest, name)
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
        for name in names {
          let nestPath = base.filePath.appending(name).string
          let nest = seeker.seekDir(.nest, nestPath)
          if nest.status.isDir {
            return (nest, name)
          }
        }
      }
      return nil
    }

    // Base directory candidates are NEST_BASE, HOME + (RPATH | git)
    if let result = tryBaseDir(envVar(.NEST_BASE)) {
      return result
    }
    if let homePath = envVar(.HOME),
      let home = seeker.seekDirOrNil(.HOME, homePath)
    {
      for rpath in notEmpty([envVar(.NEST_HOME_RPATH), "git"]) {
        if let result = tryBaseDir(home.filePath.appending(rpath).string) {
          return result
        }
      }
    }
    return nil
  }
}

extension DriverConfig {

  /// Operation-wide run configuration
  public struct AskMode {
    static let LOG = AskMode(logProgressForUser: true)
    static let QUIET = AskMode(logProgressForUser: false)
    public let logProgressForUser: Bool

    func with(
      logProgressForUser: Bool = false
    ) -> AskMode {
      if logProgressForUser == self.logProgressForUser {
        return self
      }
      return .init(logProgressForUser: logProgressForUser)
    }
    func with(logConfig: String?) -> AskMode {
      guard let logConfig = logConfig, !logConfig.isEmpty else {
        return self
      }
      return with(logProgressForUser: true)
    }
  }
}

extension DriverConfig {

  /// Operation-wide run configuration
  public struct AskMode: Sendable {
    static let LOG = Self(logProgressForUser: true)
    static let QUIET = Self(logProgressForUser: false)
    public let logProgressForUser: Bool

    func with(
      logProgressForUser: Bool = false
    ) -> Self {
      if logProgressForUser == self.logProgressForUser {
        return self
      }
      return .init(logProgressForUser: logProgressForUser)
    }
    func with(logConfig: String?) -> Self {
      guard let logConfig, !logConfig.isEmpty else {
        return self
      }
      return with(logProgressForUser: true)
    }
  }
}

@testable import clutchLib

typealias Errors = ClutchDriver.Errors

/// Check parts of ``ClutchDriver.Problem/ErrParts``
enum ErrPartCheck: Equatable {
  case ask(DriverConfig.UserAsk)
  case agent(Errors.Agent)
  case subject(Errors.Subject)
  case problem(Errors.Problem)
  case fixHint(String)
  case message(String)
  case detail(String)
  static let LEAD = "  "
  static let SEP = "\n\(LEAD)"

  func check(_ actual: Errors.ErrParts) -> String? {
    switch self {
    case let .ask(expect):
      return Self.checkEqual("ask", expect, actual.ask)
    case let .agent(expect):
      return Self.checkEqual("agent", expect, actual.agent)
    case .subject(let expect):
      return expect.matchError(actual.subject)
    case .problem(let expect):
      return expect.matchError(actual.problem)
    case .fixHint(let expect):
      return Self.checkMatch("hint", expect, actual.fixHint)
    case .message(let expect):
      return Self.checkMatch("message", expect, actual.message)
    case .detail(let expect):
      return Self.checkMatch("detail", expect, actual.detail)
    }
  }
  static func checkEqual<T: Equatable>(
    _ label: String,
    _ exp: T,
    _ act: T?
  ) -> String? {
    if exp == act {
      return nil
    }
    return Self.expAct(label, exp, act)
  }
  /// Check that match text is in actual result, returning non-empty error otherwise
  ///
  /// - Parameters:
  ///   - label: String prefix used to make error
  ///   - exp: String match to expect in actual (return nil if empty)
  ///   - act: Optional String actual text to search for match (return nil if expected but empty)
  /// - Returns: nil if exp is empty or is found in act, or String describing error otherwise
  static func checkMatch(
    _ label: String,
    _ exp: String,
    _ act: String?
  ) -> String? {
    if exp.isEmpty {
      return nil  // OK? no details in match, just structure
    }
    if let act = act, act.contains(exp) {
      return nil
    }
    return Self.expAct(label, exp, act)
  }
  static func expAct<T>(
    _ label: String,
    _ exp: T,
    _ act: T?
  ) -> String {
    let prefix = "\(label)\(Self.SEP)exp: \(exp)\(Self.SEP)act: "
    if let act = act {
      return "\(prefix)\(act)"
    }
    return "\(prefix)n/a"
  }
}

extension Errors.Subject {
  private typealias EC = ErrPartCheck
  func matchError(_ actual: Self) -> String? {
    let prefix = "input"
    if index != actual.index {
      return EC.expAct(prefix, self, actual)
    }
    switch self {
    case let .CLI(expect):
      guard case let .CLI(act) = actual else {
        preconditionFailure("same index but not CLI")
      }
      return EC.checkMatch("\(prefix).CLI", expect, act)
    case let .environmentVariable(expect):
      guard case let .environmentVariable(act) = actual else {
        preconditionFailure("same index but not environmentVariable")
      }
      return EC.checkEqual("\(prefix).EnvVar", expect, act)
    case .resource(let expect):
      guard case let .resource(act) = actual else {
        preconditionFailure("same index but not resource")
      }
      return EC.checkEqual("\(prefix).resource", expect, act)
    }
  }
  var index: Int {
    switch self {
    case .CLI(_): return 1
    case .environmentVariable(_): return 2
    case .resource(_): return 3
    }
  }
}

extension Errors.Problem {
  private typealias EC = ErrPartCheck
  func matchError(_ actual: Self) -> String? {
    if index != actual.index {
      return EC.expAct("problem", self, actual)
    }
    let prefix = "problem.\(name)"
    switch self {
    case let .bad(expect):
      guard case let .bad(act) = actual else {
        preconditionFailure("same index but not \(prefix): \(actual)")
      }
      return EC.checkMatch(prefix, expect, act)
    case let .badSyntax(expect):
      guard case let .badSyntax(act) = actual else {
        preconditionFailure("same index but not \(prefix): \(actual)")
      }
      return EC.checkMatch(prefix, expect, act)
    case let .dirNotFound(expect):
      guard case let .dirNotFound(act) = actual else {
        preconditionFailure("same index but not \(prefix): \(actual)")
      }
      return EC.checkMatch(prefix, expect, act)
    case let .fileNotFound(expect):
      guard case let .fileNotFound(act) = actual else {
        preconditionFailure("same index but not \(prefix): \(actual)")
      }
      return EC.checkMatch(prefix, expect, act)
    case let .invalidFile(expect):
      guard case let .invalidFile(act) = actual else {
        preconditionFailure("same index but not \(prefix): \(actual)")
      }
      return EC.checkMatch(prefix, expect, act)
    case let .operationFailed(expect):
      guard case let .operationFailed(act) = actual else {
        preconditionFailure("same index but not \(prefix): \(actual)")
      }
      return EC.checkMatch(prefix, expect, act)
    case let .programError(expect):
      guard case let .programError(act) = actual else {
        preconditionFailure("same index but not \(prefix): \(actual)")
      }
      return EC.checkMatch(prefix, expect, act)
    case let .thrown(expect):
      guard case let .thrown(act) = actual else {
        preconditionFailure("same index but not \(prefix): \(actual)")
      }
      guard expect.canMatch else {
        preconditionFailure("Expected error used .make(error) : \(expect)")
      }
      return expect.matchError(act)
    }
  }
  var name: String {
    Self.names[index]
  }
  var index: Int {
    switch self {
    case .bad(_): return 0
    case .badSyntax(_): return 1
    case .dirNotFound(_): return 2
    case .fileNotFound(_): return 3
    case .invalidFile(_): return 4
    case .operationFailed(_): return 5
    case .programError(_): return 6
    case .thrown(_): return 7
    }
  }
  static let names = [
    "bad", "badSyntax", "dirNotFound", "fileNotFound", "invalidFile",  //
    "operationFailed", "programError", "thrown",
  ]
}

typealias EquatableError = ClutchDriver.Errors.EquatableError
extension EquatableError {
  static func match(_ match: String) -> EquatableError {
    EquatableError(error: NominalError.nominal, match: match)
  }
  var canMatch: Bool {
    0 < (match?.count ?? 0) && nil != error as? NominalError
  }

  /// Return nil if non-empty match found in input, or String explaining mismatch.
  /// - Parameter rhs: ``EquatableError`` to match
  /// - Returns: nil if matching, or String error otherwise
  func matchError(_ rhs: EquatableError) -> String? {
    guard let match = match else {
      return "Matching from error"
    }
    guard canMatch else {
      return "Empty match"
    }
    let actual = "\(rhs.error)"
    if actual.contains(match) {
      return nil
    }
    return "\(match) not found in \"\(actual)\""
  }
  private enum NominalError: Error {
    case nominal
  }

}

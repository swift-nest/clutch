@testable import clutchLib

typealias Errors = ClutchDriver.Errors

/// Check parts of ``ClutchDriver.Problem/ErrParts``
enum ErrPartCheck: Equatable {
  case ask(DriverConfig.UserAsk)
  case agent(Errors.Agent)
  case subject(Errors.Subject)
  case problem(Errors.Problem)
  case fixHint(String)
  case label(String)
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
    case .label(let expect):
      return Self.checkMatch("label", expect, actual.label)
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
    if let act, act.contains(exp) {
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
    if let act {
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
    case let .resource(expect, expectStr):
      guard case let .resource(act, actualStr) = actual else {
        preconditionFailure("same index but not resource")
      }
      let pre = "\(prefix).resource"
      return EC.checkEqual(pre, expect, act)
        ?? EC.checkMatch("\(pre).message", expectStr, actualStr)
    }
  }
  var index: Int {
    switch self {
    case .CLI: return 1
    case .environmentVariable: return 2
    case .resource: return 3
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
    case let .opFailed(expect):
      guard case let .opFailed(act) = actual else {
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
    case .badSyntax: return 0
    case .dirNotFound: return 1
    case .fileNotFound: return 2
    case .invalidFile: return 3
    case .opFailed: return 4
    case .thrown: return 5
    case .programError: return 6
    }
  }
  static let names = [
    "badSyntax", "dirNotFound", "fileNotFound", "invalidFile",  //
    "opFailed", "thrown", "programError",
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
    guard let match else {
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

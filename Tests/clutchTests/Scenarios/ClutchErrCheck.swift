@testable import clutchLib

typealias Problem = ClutchDriver.Problem

/// Check parts of ``ClutchDriver.Problem/ErrParts``
enum ErrPartCheck: Equatable {
  case ask(DriverConfig.UserAsk)
  case agent(Problem.Agent)
  case input(Problem.BadInput)
  case reason(Problem.ReasonBad)
  case fixHint(String)
  case message(String)
  case detail(String)
  static let LEAD = "  "
  static let SEP = "\n\(LEAD)"


  func check(_ actual: Problem.ErrParts) -> String? {
    switch self {
    case let .ask(expect):
      return Self.checkEqual("ask", expect, actual.ask)
    case let .agent(expect):
      return Self.checkEqual("agent", expect, actual.agent)
    case .input(let expect):
      return expect.matchError(actual.input)
    case .reason(let expect):
      return expect.matchError(actual.reason)
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
  static func checkMatch(
    _ label: String,
    _ exp: String,
    _ act: String?
  ) -> String? {
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


extension Problem.BadInput {
  private typealias EC = ErrPartCheck
  func matchError(_ actual: Self) -> String? {
    let prefix = "input"
    if index != actual.index {
      return EC.expAct(prefix, self, actual)
    }
    switch self {
    case .notInput: return nil
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
    case .notInput: return 0
    case .CLI(_): return 1
    case .environmentVariable(_): return 2
    case .resource(_): return 3
    }
  }
}

extension Problem.ReasonBad {
  private typealias EC = ErrPartCheck
  func matchError(_ actual: Self) -> String? {
    var prefix = "input"
    if index != actual.index {
      return EC.expAct(prefix, self, actual)
    }
    prefix += ".\(name)"
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
    case .operationFailed(_): return 4
    case .programError(_): return 5
    }
  }
  static let names = [
    "bad", "badSyntax", "dirNotFound", "fileNotFound", //
    "operationFailed", "programError"
  ]
}


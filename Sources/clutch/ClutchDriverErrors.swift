
extension ClutchDriver {
  /// Parameterized errors
  public enum Errors {
    // complicates b/c parts not orthogonal
    // LocalizedError: in Foundation
    public struct ErrParts: Error, CustomStringConvertible {
      public let ask: DriverConfig.UserAsk
      public let agent: Agent
      public let subject: Subject
      public let problem: Problem
      public let fixHint: String?
      public var description: String {
        message
      }
      public var message: String {
        let hintStr = nil == fixHint ? "" : "\n\(fixHint!)"
        return "\(agent)(\(ask)) error \(subject) \(problem)\(hintStr)"
      }
      public var detail: String {
        let lines = [
          "message: \(message)",
          "    ask: \(ask)",
          "  agent: \(agent)",
          "subject: \(subject)",
          "problem: \(problem)",
          "    fix: \(fixHint ?? "")"
        ]
        return lines.joined(separator: "\n")
      }
    }

    public enum Agent: String, Equatable {
      case clutch, system, swiftBuild, peerBuild, peerRun
    }

    public enum Subject: Equatable, CustomStringConvertible {
      case CLI(String)
      case environmentVariable(PeerNest.EnvName)
      case resource(PeerNest.ResourceKey)
      public var description: String {
        switch self {
        case let .CLI(s): return "\(name)(\"\(s)\")"
        case let .environmentVariable(v): return "\(name)(\(v.key))"
        case let .resource(r): return "\(name)(\(r.str))"
        }
      }
      var name: String {
        Self.names[index]
      }
      var index: Int {
        switch self {
        case .CLI(_): return 0
        case .environmentVariable(_): return 1
        case .resource(_): return 2
        }
      }
      static let names = ["CLI", "EnvVar", "resource"]
    }

    public enum Problem: Equatable {
      case badSyntax(String)
      case invalidFile(String)
      case fileNotFound(String)
      case dirNotFound(String)
      case operationFailed(String)
      case programError(String)
      case bad(String)
      case thrown(EquatableError)
      var label: String {
        switch self {
        case .bad(_): return ""
        case .badSyntax(_): return "bad syntax\n\(Help.SYNTAX)"
        case .invalidFile(_): return "file invalid"
        case .fileNotFound(_): return "file n/a"
        case .dirNotFound(_): return "directory n/a"
        case .operationFailed(_): return "failed"
        case .programError(_): return "program error"
        case .thrown(_): return "thrown"
        }
      }
      var message: String {
        "\(label) \(input)"
      }
      var input: String {
        switch self {
        case .bad(let s): return s
        case .badSyntax(let s): return s
        case .invalidFile(let s): return s
        case .fileNotFound(let s): return s
        case .dirNotFound(let s): return s
        case .operationFailed(let s): return s
        case .programError(let s): return s
        case .thrown(let s): return "\(s)"
        }
      }
    }
    
    class ErrBuilder {
      @TaskLocal static var local = ErrBuilder()
      var ask: DriverConfig.UserAsk
      var part: Agent
      var subject: Subject
      var args: [String] // TODO: args unused
      required init(
        ask: DriverConfig.UserAsk = .programErr,
        part: Agent = .clutch,
        subject: Subject = .CLI("init-args"),
        args: [String] = []
      ) {
        self.ask = ask
        self.part = part
        self.subject = subject
        self.args = args
      }
      public func set(
        subject: Subject? = nil,
        part: Agent? = nil,
        ask: DriverConfig.UserAsk? = nil,
        args: [String]? = nil
      ) {
        self.subject = subject ?? self.subject
        self.part = part ?? self.part
        self.ask = ask ?? self.ask
        self.args = args ?? self.args
      }

      public func setting(
        subject: Subject? = nil,
        part: Agent? = nil,
        ask: DriverConfig.UserAsk? = nil,
        args: [String]? = nil
      ) -> Self {
        Self(
          ask: ask ?? self.ask,
          part: part ?? self.part,
          subject: subject ?? self.subject,
          args: args ?? self.args
        )
      }

      public func err(
        _ problem: Problem,
        subject: Subject? = nil,
        part: Agent? = nil,
        ask: DriverConfig.UserAsk? = nil,
        fixHint: String? = nil
      ) -> ErrParts {
        ErrParts(
          ask: ask ?? self.ask,
          agent: part ?? self.part,
          subject: subject ?? self.subject,
          problem: problem,
          fixHint: fixHint)
      }
      public func errq(
        _ problem: Problem,
        _ subject: Subject? = nil,
        _ part: Agent? = nil,
        _ ask: DriverConfig.UserAsk? = nil,
        fixHint: String? = nil
      ) -> ErrParts {
        ErrParts(
          ask: ask ?? self.ask,
          agent: part ?? self.part,
          subject: subject ?? self.subject,
          problem: problem,
          fixHint: fixHint)
      }

      func runAsTaskLocal<T>(_ op: () throws -> T) throws -> T {
        try MakeErr.$local.withValue(self) {
          do {
            return try op()
          } catch {
            throw MakeErr.local.err(.thrown(.make(error)))
          }
        }
      }

      func runAsyncTaskLocal<T>(_ op: () async throws -> T) async throws -> T {
        try await MakeErr.$local.withValue(self) {
          do {
            return try await op()
          } catch {
            throw MakeErr.local.err(.thrown(.make(error)))
          }
        }
      }
    }

    /// Box error for transport (by problem) or matching (in tests)
    public struct EquatableError: Equatable, CustomStringConvertible {
      public static func make(_ error: Error) -> EquatableError {
        EquatableError(error: error)
      }
      public typealias ME = ClutchDriver.Errors.EquatableError
      public static func == (lhs: ME, rhs: ME) -> Bool {
        lhs.description == rhs.description
      }
      public let error: Error
      public let match: String?

      init(error: Error, match: String? = nil) {
        self.error = error
        self.match = match
      }

      public var description: String {
        match ?? "\(error)"
      }
    }
  }
}

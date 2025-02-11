extension ClutchDriver {
  /// Parameterized errors
  public enum Errors {
    // complicates b/c parts not orthogonal
    // LocalizedError: in Foundation
    public struct ErrParts: Error, CustomStringConvertible, Sendable {
      public let ask: DriverConfig.UserAsk
      public let agent: Agent
      public let subject: Subject
      public let problem: Problem
      public let args: [String]?
      public let fixHint: String?
      public var description: String {
        "\(label)\n\(detail)"  // duplicates subject+problem, but clearer
      }
      public var label: String {
        "\(subject) \(problem.message)"
      }
      public var detail: String {
        var lines = [
          "request: \(ask)",
          "  agent: \(agent)",
          "subject: \(subject)",
          "problem: \(problem)",
        ]
        if let hint = fixHint {
          lines += ["    fix: \(hint)"]
        }
        if let args {
          lines += ["   args: \(args)"]
        }
        return lines.joined(separator: "\n")
      }
    }

    public enum Agent: String, Equatable, Sendable {
      case clutch, system, swiftBuild, peerRun
    }

    public enum Subject: Equatable, CustomStringConvertible, Sendable {
      case CLI(String)  // TODO: only used for default?
      case environmentVariable(PeerNest.EnvName)  // TODO: no such errors?
      case resource(PeerNest.ResourceKey, String)
      public var description: String {
        switch self {
        case let .CLI(s): return "args: \"\(s)\""
        case let .environmentVariable(v): return "env[\(v.key)]: "
        case let .resource(r, s): return "\(r.str): \(s)"
        }
      }
      var name: String {
        Self.names[index]
      }
      var index: Int {
        switch self {
        case .CLI: return 0
        case .environmentVariable: return 1
        case .resource: return 2
        }
      }
      static let names = ["CLI", "EnvVar", "resource"]
    }

    public enum Problem: Equatable, Sendable, CustomStringConvertible {
      case badSyntax(String)
      case invalidFile(String)
      case fileNotFound(String)
      case dirNotFound(String)
      case opFailed(String)
      case thrown(EquatableError)
      case programError(String)
      public var description: String {
        message
      }
      var label: String {
        switch self {
        case .badSyntax: return "bad syntax\n\(Help.SYNTAX)"
        case .invalidFile: return "file invalid"
        case .fileNotFound: return "file n/a"
        case .dirNotFound: return "directory n/a"
        case .opFailed: return "failed"
        case .thrown: return "thrown"
        case .programError: return "program error"
        }
      }
      var message: String {
        "\(label): \(input)"
      }
      var input: String {
        switch self {
        case .badSyntax(let s): return s
        case .invalidFile(let s): return s
        case .fileNotFound(let s): return s
        case .dirNotFound(let s): return s
        case .opFailed(let s): return s
        case .thrown(let s):
          if let mine = s.error as? ErrParts {
            return mine.detail
          }
          return "\(s)"
        case .programError(let s): return s
        }
      }
    }

    public final class ErrBuilder: Sendable {
      @TaskLocal public static var local = ErrBuilder()
      let ask: DriverConfig.UserAsk
      let agent: Agent
      let subject: Subject
      let args: [String]  // TODO: args unused
      public required init(
        ask: DriverConfig.UserAsk = .programErr,
        agent: Agent = .clutch,
        subject: Subject = .CLI("init-args"),
        args: [String] = []
      ) {
        self.ask = ask
        self.agent = agent
        self.subject = subject
        self.args = args
      }

      public func setting(
        subject: Subject? = nil,
        agent: Agent? = nil,
        ask: DriverConfig.UserAsk? = nil,
        args: [String]? = nil
      ) -> Self {
        Self(
          ask: ask ?? self.ask,
          agent: agent ?? self.agent,
          subject: subject ?? self.subject,
          args: args ?? self.args
        )
      }

      public func err(
        _ problem: Problem,
        subject: Subject? = nil,
        agent: Agent? = nil,
        ask: DriverConfig.UserAsk? = nil,
        fixHint: String? = nil
      ) -> ErrParts {
        ErrParts(
          ask: ask ?? self.ask,
          agent: agent ?? self.agent,
          subject: subject ?? self.subject,
          problem: problem,
          args: args,
          fixHint: fixHint
        )
      }

      /// Alias for ``err(_:subject:part:ask:fixHint:)`` without labels as experiment
      /// - Parameters:
      ///   - problem: ``Problem``
      ///   - subject: optional ``Subject`` (use current if nil)
      ///   - part: optional ``Agent`` (use current if nil)
      ///   - ask: optional ``DriverConfig/UserAsk`` (nil to use current)
      ///   - fixHint: optional String description of how to fix the problem
      /// - Returns: ``ErrParts`` as specified
      public func errq(
        _ problem: Problem,
        _ subject: Subject? = nil,
        _ agent: Agent? = nil,
        _ ask: DriverConfig.UserAsk? = nil,
        fixHint: String? = nil
      ) -> ErrParts {
        ErrParts(
          ask: ask ?? self.ask,
          agent: agent ?? self.agent,
          subject: subject ?? self.subject,
          problem: problem,
          args: args,
          fixHint: fixHint
        )
      }

      /// Alias to create file-not-found problem on a resource
      /// - Parameters:
      ///   - resource: ``PeerNest/ResourceKey``
      ///   - path: String location of resource, if known
      ///   - msg: String file-not-found message (use path if nil)
      ///   - agent: optional ``Agent`` (nil to use current)
      ///   - ask: optional ``DriverConfig/UserAsk`` (nil to use current)
      ///   - fixHint: optional String description of how to fix the problem
      /// - Returns: ``ErrParts`` as specified
      public func noFile(
        _ resource: PeerNest.ResourceKey,
        path: String,
        msg: String? = nil,
        _ agent: Agent? = nil,
        _ ask: DriverConfig.UserAsk? = nil,
        fixHint: String? = nil
      ) -> ErrParts {
        ErrParts(
          ask: ask ?? self.ask,
          agent: agent ?? self.agent,
          subject: .resource(resource, path),
          problem: .fileNotFound(msg ?? path),
          args: args,
          fixHint: fixHint
        )
      }

      /// Alias to create op-failed problem on a resource
      /// - Parameters:
      ///   - resource: ``PeerNest/ResourceKey``
      ///   - path: String location of resource, if known
      ///   - msg: String op-failed message
      ///   - agent: optional ``Agent`` (nil to use current)
      ///   - ask: optional ``DriverConfig/UserAsk (nil to use current)
      ///   - fixHint: optional String description of how to fix the problem
      /// - Returns: ``ErrParts`` as specified
      public func fail(
        _ resource: PeerNest.ResourceKey,
        path: String,
        msg: String,
        agent: Agent? = nil,
        ask: DriverConfig.UserAsk? = nil,
        fixHint: String? = nil
      ) -> ErrParts {
        ErrParts(
          ask: ask ?? self.ask,
          agent: agent ?? self.agent,
          subject: .resource(resource, path),
          problem: .opFailed(msg),
          args: args,
          fixHint: fixHint
        )
      }

      func runAsTaskLocal<T>(_ op: () throws -> T) throws -> T {
        try MakeErr.$local.withValue(self) {
          do {
            return try op()
          } catch {
            throw err(.thrown(.make(error)))
          }
        }
      }

      func runAsyncTaskLocal<T>(_ op: () async throws -> T) async throws -> T {
        try await MakeErr.$local.withValue(self) {
          do {
            return try await op()
          } catch {
            throw err(.thrown(.make(error)))
          }
        }
      }
    }

    /// Box error for transport (by problem) or matching (in tests)
    public struct EquatableError: Equatable, CustomStringConvertible, Sendable {
      public static func make(_ error: Error) -> Self {
        Self(error: error)
      }
      public static func == (lhs: Self, rhs: Self) -> Bool {
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

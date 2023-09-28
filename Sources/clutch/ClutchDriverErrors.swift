
extension ClutchDriver {
  /// Parameterized errors
  public enum Problem {
    // complicates b/c parts not orthogonal
    // LocalizedError: in Foundation
    public struct ErrParts: Error, CustomStringConvertible {
      public let ask: DriverConfig.UserAsk
      public let agent: Agent
      public let subject: Subject
      public let reason: ReasonBad
      public let fixHint: String?
      public var description: String {
        message
      }
      public var message: String {
        let inputStr = subject.isNotInput ? "" : " \(subject)"
        let hintStr = nil == fixHint ? "" : "\n\(fixHint!)"
        return "\(agent)(\(ask)) error\(inputStr) \(reason)\(hintStr)"
      }
      public var detail: String {
        let lines = [
          "message: \(message)",
          "    ask: \(ask)",
          "  agent: \(agent)",
          "subject: \(subject)",
          " reason: \(reason)",
          "    fix: \(fixHint ?? "")"
        ]
        return lines.joined(separator: "\n")
      }
    }

    public enum Agent: String, Equatable {
      case clutch, system, swiftBuild, peerBuild, peerRun
    }

    public enum Subject: Equatable, CustomStringConvertible {
      case notInput
      case CLI(String)
      case environmentVariable(PeerNest.EnvName)
      //case configFile
      case resource(PeerNest.ResourceKey)
      public var description: String {
        switch self {
        case .notInput: return name
        case let .CLI(s): return "\(name)(\"\(s)\")"
        case let .environmentVariable(v): return "\(name)(\(v.key))"
        case let .resource(r): return "\(name)(\(r.str))"
        }
      }
      var isNotInput: Bool {
        if case .notInput = self {
          return true
        }
        return false
      }
      var name: String {
        Self.names[index]
      }
      var index: Int {
        switch self {
        case .notInput: return 0
        case .CLI(_): return 1
        case .environmentVariable(_): return 2
        case .resource(_): return 3
        }
      }
      static let names = ["noInput", "CLI", "EnvVar", "resource"]
    }
    
    public enum ReasonBad: Equatable {
      case badSyntax(String)
      case fileNotFound(String)
      case dirNotFound(String)
      case operationFailed(String)
      case programError(String)
      case bad(String)
      var label: String {
        switch self {
        case .bad(_): return ""
        case .badSyntax(_): return "bad syntax\n\(Help.SYNTAX)"
        case .fileNotFound(_): return "file n/a"
        case .dirNotFound(_): return "directory n/a"
        case .operationFailed(_): return "failed"
        case .programError(_): return "program error"
        }
      }
      var message: String {
        "\(label) \(input)"
      }
      var input: String {
        switch self {
        case .bad(let s): return s
        case .badSyntax(let s): return s
        case .fileNotFound(let s): return s
        case .dirNotFound(let s): return s
        case .operationFailed(let s): return s
        case .programError(let s): return s
        }
      }
    }
    
    class ErrBuilder {
      @TaskLocal static var local = ErrBuilder()
      var ask: DriverConfig.UserAsk
      var part: Agent
      var subject: Subject
      var args: [String] // TODO: args unused
      init(
        ask: DriverConfig.UserAsk = .programErr,
        part: Agent = .clutch,
        subject: Subject = .notInput,
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

      public func err(
        reason: ReasonBad,
        subject: Subject? = nil,
        part: Agent? = nil,
        ask: DriverConfig.UserAsk? = nil,
        fixHint: String? = nil
      ) -> ErrParts {
        ErrParts(
          ask: ask ?? self.ask,
          agent: part ?? self.part,
          subject: subject ?? self.subject,
          reason: reason,
          fixHint: fixHint)
      }
      public func errq(
        _ reason: ReasonBad,
        _ subject: Subject? = nil,
        _ part: Agent? = nil,
        _ ask: DriverConfig.UserAsk? = nil,
        fixHint: String? = nil
      ) -> ErrParts {
        ErrParts(
          ask: ask ?? self.ask,
          agent: part ?? self.part,
          subject: subject ?? self.subject,
          reason: reason,
          fixHint: fixHint)
      }
    }
  }
}

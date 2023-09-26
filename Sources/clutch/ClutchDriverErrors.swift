
extension ClutchDriver {
  /// Parameterized errors
  public enum Problem { // too complicated?
    public enum ReportingSystem {
      case clutch, system, swiftBuild, peerBuild, peerRun
    }

    public enum BadInput {
      case notInput
      case CLI(String)
      case environmentVariable(PeerNest.EnvName)
      //case configFile
      case resource(PeerNest.ResourceKey)
      var isNotInput: Bool {
        if case .notInput = self {
          return true
        }
        return false
      }
    }
    
    public enum ReasonBad {
      case badSyntax(String)
      case fileNotFound(String)
      case dirNotFound(String)
      case notFound
      case operationFailed(String)
      case programError(String)
      case bad(String)
      var label: String {
        switch self {
        case .bad(_): return ""
        case .badSyntax(_): return "bad syntax\n\(Help.SYNTAX)"
        case .fileNotFound(_): return "file n/a"
        case .dirNotFound(_): return "directory n/a"
        case .notFound: return "n/a"
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
        case .notFound: return ""
        case .operationFailed(let s): return s
        case .programError(let s): return s
        }
      }
    }
    
    public struct ErrParts: Error {
      public let ask: DriverConfig.UserAsk
      public let part: ReportingSystem
      public let input: BadInput
      public let reason: ReasonBad
      public let fixHint: String?
      public var message: String {
        let inputStr = input.isNotInput ? "" : " \(input)"
        let hintStr = nil == fixHint ? "" : "\n\(fixHint!)"
        return "\(part)(\(ask)) error\(inputStr) \(reason)\(hintStr)"
      }
    }

    class ErrBuilder { // as task-local?
      @TaskLocal static var local = ErrBuilder()
      var ask: DriverConfig.UserAsk
      var part: ReportingSystem
      var input: BadInput
      var args: [String]
      init(
        ask: DriverConfig.UserAsk = .programErr,
        part: ReportingSystem = .clutch,
        input: BadInput = .notInput,
        args: [String] = []
      ) {
        self.ask = ask
        self.part = part
        self.input = input
        self.args = args
      }
      public func set(
        input: BadInput? = nil,
        part: ReportingSystem? = nil,
        ask: DriverConfig.UserAsk? = nil,
        args: [String]? = nil
      ) {
        self.input = input ?? self.input
        self.part = part ?? self.part
        self.ask = ask ?? self.ask
        self.args = args ?? self.args
      }

      public func err(
        reason: ReasonBad,
        input: BadInput? = nil,
        part: ReportingSystem? = nil,
        ask: DriverConfig.UserAsk? = nil,
        fixHint: String? = nil
      ) -> ErrParts {
        ErrParts(
          ask: ask ?? self.ask,
          part: part ?? self.part,
          input: input ?? self.input,
          reason: reason,
          fixHint: fixHint)
      }
      public func errq(
        _ reason: ReasonBad,
        _ input: BadInput? = nil,
        _ part: ReportingSystem? = nil,
        _ ask: DriverConfig.UserAsk? = nil,
        fixHint: String? = nil
      ) -> ErrParts {
        ErrParts(
          ask: ask ?? self.ask,
          part: part ?? self.part,
          input: input ?? self.input,
          reason: reason,
          fixHint: fixHint)
      }
    }
  }
}

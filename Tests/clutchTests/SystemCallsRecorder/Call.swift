import clutchLib

enum Call {
  public static let anyResult = ["result"]
  public static let voidResult = ["void"]
  static let void: () = ()
  static let voidNil: Void? = nil
  struct Record<Target, Parms, Result> {
    let def: Def<Target>
    let frame: Frame<Parms, Result>
  }
  struct Def<Target> {
    static func void<T>(
      _ target: T.Type,
      _ name: String,
      parms: [String] = []
    ) -> Def<T> {
      .init(target, name, parms: parms, results: Call.voidResult)
    }
    static func result<T>(
      _ target: T.Type,
      _ name: String,
      parms: [String] = []
    ) -> Def<T> {
      .init(target, name, parms: parms, results: Call.anyResult)
    }
    let target: Target.Type
    let name: String  // ignoring overrides
    let parmNames: [String]  // match by index to parm tuple, including unlabeled
    let resultNames: [String]  // match by index to result tuple
    init(
      _ target: Target.Type,
      _ name: String,
      parms: [String] = [],
      results: [String]
    ) {
      self.target = target
      self.name = name
      self.parmNames = parms
      self.resultNames = results
    }
  }

  /// Parms: tuple types.  Need corresponding names
  struct Frame<Parms, Result> {
    let parms: Parms
    let result: Result?
    let thrown: Thrown
    init(
      parms: Parms,
      result: Result?,
      thrown: Thrown = .notThrowing
    ) {
      self.parms = parms
      self.result = result
      self.thrown = thrown
    }
  }
  enum Thrown: Identifiable {
    case thrown(String)
    case notThrowing
    case notThrown
    var wasThrown: Bool { -1 == id }
    var id: Int {
      switch self {
      case .thrown: return -1
      case .notThrowing: return 0
      case .notThrown: return 1
      }
    }
    var message: String? {
      if case let .thrown(message) = self {
        return message
      }
      return nil
    }
  }
}
extension Call.Frame {
  static func frame<T>(
    _ parms: T,
    throwing thrown: Call.Thrown = .notThrowing
  ) -> Call.Frame<T, ()> {
    let result: ()? = thrown.wasThrown ? Call.voidNil : Call.void
    return Call.Frame(parms: parms, result: result, thrown: thrown)
  }
  static func frame<T, R>(
    _ parms: T,
    returning result: R?,
    throwing thrown: Call.Thrown = .notThrowing
  ) -> Call.Frame<T, R> {
    Call.Frame(parms: parms, result: result, thrown: .notThrowing)
  }
  static func frameThrowing<T, R>(
    _ parms: T,
    err: Error
  ) -> Call.Frame<T, R> {
    Call.Frame(parms: parms, result: nil as R?, thrown: .thrown("\(err)"))
  }
}

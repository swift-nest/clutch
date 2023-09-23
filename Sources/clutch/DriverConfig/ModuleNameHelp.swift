public typealias ModuleName = DriverConfig.ModuleName
extension [ModuleName.Kind] {
  public static let forModule: [ModuleName.Kind] = [.nameOnly, .nameNest]
  public static let forNest: [ModuleName.Kind] = [.nestOnly]
}

extension ModuleName {
  typealias Config = DriverConfig

  /// Make ``ModuleName`` with name and optional nest,
  /// if ``DriverConfig/checkIdentifier(_:)-3hbwu``
  /// - Parameters:
  ///   - name: module identifer
  ///   - nest: nest identifier (ignored if empty, returning valid name-only ModuleName)
  /// - Returns: ``ModuleName`` if name is not empty and inputs are valid identifiers
  static func nameNest(_ name: String, nest: String?) -> Self? {
    guard Config.checkIdentifier(name) else {
      return nil
    }
    if let nest = nest, !nest.isEmpty {
      if Config.checkIdentifier(nest) {
        return valid(.nameNest, name, nest: nest)
      }
      return nil
    }
    return valid(.nameOnly, name, nest: "")
  }

  public static func make(
    _ input: String,
    into permitted: [Kind] = Kind.allCases
  ) -> Self? {
    make(input[input.startIndex..<input.endIndex], into: permitted)
  }

  /// Make ``ModuleName`` from possibly-qualified input, constrained by ``Config/Kind``.
  ///
  ///  Identifiers are qualifed by ``DriverConfig/checkIdentifier(_:)-3hbwu``
  /// - Parameters:
  ///   - input: Identifier, possibly internally delimited by dot (`.`)
  ///   - into: permitted Array of ``Config/Kind`` for result
  /// - Returns: ``ModuleName`` if input valid per constraints
  static func make(
    _ input: String.SubSequence,
    into permitted: [Kind] = Kind.allCases
  ) -> Self? {
    guard let dot = input.firstIndex(of: ".") else {
      if Config.checkIdentifier(input) {
        if permitted.contains(.nameOnly) {
          return valid(.nameOnly, input, nest: "")
        }
        if permitted.contains(.nestOnly) {
          return valid(.nestOnly, "", nest: input)
        }
      }
      return nil
    }
    guard permitted.contains(.nameNest) else {
      return nil
    }
    let afterDot = input.index(after: dot)
    let name = input[input.startIndex..<dot]
    if name.isEmpty || afterDot == input.endIndex
      || !Config.checkIdentifier(name)
    {
      return nil  // empty or invalid name or empty nest
    }
    let nest = input[afterDot...]
    if !Config.checkIdentifier(nest) {
      return nil  // invalid nest
    }
    return valid(.nameNest, name, nest: nest)
  }
}

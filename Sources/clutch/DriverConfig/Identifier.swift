extension DriverConfig {
  typealias EnvSource = PeerNest.EnvName.Source

  static func checkIdentifier(_ name: String) -> Bool {
    checkIdentifier(name[name.startIndex..<name.endIndex])
  }
  static func checkIdentifier(_ name: String.SubSequence) -> Bool {
    // TODO: extend beyond ASCII to (valid-filenames and valid-identifiers)
    func notIdChar(_ e: (offset: Int, element: Character)) -> Bool {
      let (i, c) = e
      return !c.isASCII || !(c == "_" || c.isLetter || (c.isNumber && 0 != i))
    }
    return !name.isEmpty && nil == name.enumerated().first(where: notIdChar)
  }
}

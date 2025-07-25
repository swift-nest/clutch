import struct MinSys.FilePath

extension DriverConfig {
  /// Validated (by client) as non-empty identifiers for peer module, nest, or both
  public struct ModuleName: CustomStringConvertible, Sendable {
    public enum Kind: CaseIterable, Sendable {
      case nameOnly, nameNest, nestOnly
    }

    public let kind: Kind
    /// empty when ``Kind/nestOnly``
    public let name: String
    /// empty when ``Kind/nameOnly``
    public let nest: String

    public var description: String {
      "\(kind): \(label)"
    }

    public var label: String {
      switch kind {
      case .nameOnly: return name
      case .nestOnly: return nest
      case .nameNest: return "\(name).\(nest)"
      }
    }
    private init(_ kind: Kind, _ name: String, nest: String) {
      self.kind = kind
      self.name = name
      self.nest = nest
    }

    /// Convert to ``Kind/nameNest`` if not already by injecting nest
    /// - Parameter nest: Optional ``ModuleName`` (ignored if not ``Kind/nestOnly``)
    /// - Returns: ``ModuleName`` with ``Kind/nameNest``, if available
    func nameNest(_ nest: Self?) -> Self? {
      if kind == .nameNest {
        return self
      }
      guard let nest, nest.kind == .nestOnly else {
        return nil
      }
      return .init(.nameNest, name, nest: nest.nest)
    }

    static func valid(_ kind: Kind, _ name: String, nest: String) -> Self {
      .init(kind, name, nest: nest)
    }
    typealias SubSeq = String.SubSequence
    static func valid(_ kind: Kind, _ name: SubSeq, nest: SubSeq) -> Self {
      .init(kind, String(name), nest: String(nest))
    }
  }
}

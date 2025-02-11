enum ClutchCommandScenario: Equatable, CustomStringConvertible {
  case script(Script)
  case nest(Nest)
  case peer(Peer)
  enum Peer: String, CaseIterable {
    case cat
    case run
    case path
  }
  enum Nest: String, CaseIterable {
    case dir
    case peers
  }
  enum Script: String, CaseIterable {
    case uptodate
    case binaryGone
    case binaryStale
    case peerStale
    case new
  }
  public static let allCases: [Self] = [
    .script(.uptodate),
    .script(.binaryGone),
    .script(.binaryStale),
    .script(.peerStale),
    .script(.new),
    .nest(.dir),
    .nest(.peers),
    .peer(.cat),
    .peer(.run),
    .peer(.path),
  ]
  var description: String {
    name
  }
  var name: String {
    switch self {
    case .script(let name): return "script/\(name)"
    case .nest(let name): return "nest/\(name)"
    case .peer(let name): return "peer/\(name)"
    }
  }
}

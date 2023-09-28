extension DriverConfig {
  /// Clutch operations as requested/provoked by user
  //enum UserAsk: CaseIterable

  /// Organize ``UserAsk`` by rough semantics and data required
  public enum UserAskKind {
    case error(UserAsk, String)
    case script(UserAsk, NestItem, ModuleName)
    case commandPeer(UserAsk, ModuleName)
    case commandNest(UserAsk, ModuleName)
    // NB: this relies on client to match ask - verify
  }
}

extension DriverConfig.UserAskKind {
  public var ask: UserAsk {
    switch self {
    case .error(let ask, _): return ask
    case .script(let ask, _, _): return ask
    case .commandPeer(let ask, _): return ask
    case .commandNest(let ask, _): return ask
    }
  }

  public var peer: ModuleName? {
    if let askScriptPeer = scriptAskScriptPeer {
      return askScriptPeer.peer
    }
    if let commandPeerAsk = commandPeerAsk {
      return commandPeerAsk.peer
    }
    return nil
  }

  public var isNestOnly: Bool {
    if case .commandNest(_, _) = self {
      return true
    }
    return false
  }

  public var errorAskNote: (ask: UserAsk, note: String)? {
    if case let .error(ask, note) = self {
      return (ask, note)
    }
    return nil
  }
  public var scriptAskScriptPeer:
    (ask: UserAsk, script: NestItem, peer: ModuleName)?
  {
    if case let .script(ask, script, peer) = self {
      return (ask, script, peer)
    }
    return nil
  }
  public var commandPeerAsk: (peer: ModuleName, ask: UserAsk)? {
    if case let .commandPeer(ask, peer) = self {
      return (peer, ask)
    }
    return nil
  }
  public var commandNestAsk: (nest: ModuleName, ask: UserAsk)? {
    if case let .commandNest(ask, nest) = self {
      return (nest, ask)
    }
    return nil
  }

  public var nestNameInput: String? {
    isNestOnly ? commandNestAsk?.nest.nest : peer?.nest
  }
}

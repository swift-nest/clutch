#if swift(>=6)
  import ArgumentParser
  extension CommandConfiguration: @unchecked @retroactive Sendable {}
#endif

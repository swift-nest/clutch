#if swift(>=6)
  import SystemPackage
  extension FilePath: @unchecked @retroactive Sendable {}
#endif

import struct SystemPackage.FilePath

public struct PeerOp {
  typealias MakeErr = ClutchDriver.Problem.ErrBuilder
  let sysCalls: SystemCalls
  let fileSeeker: FileItemSeeker
  init(
    _ sysCalls: SystemCalls,
    fileSeeker: FileItemSeeker? = nil
  ) {
    self.sysCalls = sysCalls
    self.fileSeeker = fileSeeker ?? FileItemSeeker(systemCalls: sysCalls)
  }

  public func listPeers(
    _ manifest: NestItem,
    _ sourcesDir: NestItem
  ) async throws -> [(name: String, item: NestItem)]? {
    guard manifest.status.isFile && sourcesDir.status.isDir else {
      return nil
    }
    let content = try await sysCalls.readFile(manifest.fullPath)
    guard let names = try await listExecutableProducts(content) else {
      return nil
    }
    let dir = sourcesDir.filePath

    var result = [(String, NestItem)]()
    for name in names {
      let peerDir = dir.appending(name)
      let item = fileSeeker.seekDir(.peerSourceDir, peerDir.string)
      if item.status.isDir {
        result.append((name, item))
      }
    }
    return result
  }

  public func listExecutableProducts(
    _ manifest: String
  ) async throws -> [String]? {
    guard !manifest.isEmpty else {
      return nil
    }

    #if canImport(Regex) && swift(>=5.8)
      guard #available(macOS 13, *) else {
        return listExecutableProductsBeforeRegex(manifest)
      }
      return try listExecutableProductsWithRegexAfterSwift58(manifest)
    #else
      return listExecutableProductsBeforeRegex(manifest)
    #endif
  }

  #if canImport(Regex) && swift(>=5.8)
    @available(macOS 13, *)
    @available(swift 5.8)
    public func listExecutableProductsWithRegexAfterSwift58(
      _ manifest: String  // consuming?
    ) throws -> [String]? {
      let executableTargName = #/\.executableTarget\(name: "([^"]*)/#
      return manifest.matches(of: executableTargName).map { String($0.1) }
    }
  #endif

  public func listExecutableProductsBeforeRegex(
    _ manifest: String  // consuming?
  ) -> [String]? {
    let lead = #".executableTarget(name: "#
    let end = manifest.endIndex
    var range = manifest.startIndex..<end
    var result = [String]()
    while let next = manifest.range(of: lead, range: range) {
      let start = manifest.index(after: next.upperBound)
      guard let quote = manifest.range(of: "\"", range: start..<end) else {
        break
      }
      result.append(String(manifest[start..<quote.lowerBound]))
      range = quote.upperBound..<end
    }
    return result
  }

  func newPeerSource(
    script: FilePath,
    peerDir: FilePath,
    fileSeeker: FileItemSeeker
  ) async throws -> NestItem {
    var code = "//"
    code += try await sysCalls.readFile(script.string)
    var name = "main"
    if code.contains("@main") {
      if let n = peerDir.lastComponent?.string, !n.isEmpty {
        name = n
      } else {
        let m = "Empty script name for \(script) in \(peerDir)"
        throw MakeErr.local.err(
          reason: .badSyntax(m),
          input: .resource(.peerSourceDir)
        )
      }
    }
    let filepath = peerDir.appending("\(name).swift").string
    try await sysCalls.writeFile(path: filepath, content: code)
    return fileSeeker.seekFile(.peer, filepath)
  }

  func updatePeerSource(script: NestItem, peer: NestItem) async throws {
    var code = "//"
    code += try await sysCalls.readFile(script.fullPath)
    try await sysCalls.writeFile(path: peer.filePath.string, content: code)
  }

  /// Add peer to manifest
  /// - Parameters:
  ///   - peer: ModuleName with kind .nameNest (i.e., nest is defined)
  ///   - manifest: FilePath
  /// - Returns: true when added
  func addPeerToManifestFile(
    _ peer: ModuleName,
    manifest: FilePath
  ) async throws -> Bool {
    if peer.kind != .nameNest {
      return false
    }
    let code = try await sysCalls.readFile(manifest.string)
    guard
      let newCode = addPeerToPackageCode(
        peerModuleName: peer.name,
        nestModuleName: peer.nest,
        packageCode: code
      )
    else {
      return false
    }
    try await sysCalls.writeFile(path: manifest.string, content: newCode)
    return true
  }

  func addPeerToPackageCode(
    peerModuleName peer: String,
    nestModuleName nest: String,
    packageCode code: String
  ) -> String? {
    // TODO: regex variant of addPeer?
    Self.addPeerToPackageBeforeRegex(peer, nest, code)
  }

  public static func addPeerToPackageBeforeRegex(
    _ peer: String,
    _ nest: String,
    _ code: String
  ) -> String? {
    let end = code.endIndex
    func eolAfter(_ query: String, _ from: String.Index) -> String.Index? {
      if let range = code.range(of: query, range: from..<end) {
        return code.range(of: "\n", range: range.upperBound..<end)?.upperBound
      }
      return nil
    }
    if let prod = eolAfter(#"products: ["#, code.startIndex),
      let pack = eolAfter(#"  targets: ["#, prod)
    {  // false positives!
      return addPeer(code, peer: peer, nest: nest, product: prod, package: pack)
    }
    let envTarget = PeerNest.EnvName.TAG_TARGET
    let envProduct = PeerNest.EnvName.TAG_PRODUCT
    guard let prod2 = eolAfter(envProduct, code.startIndex),
      let pack2 = eolAfter(envTarget, prod2)
    else {
      return nil
    }
    return addPeer(code, peer: peer, nest: nest, product: prod2, package: pack2)
  }

  static func addPeer(
    _ code: String,
    peer: String,
    nest: String,
    product: String.Index,
    package: String.Index
  ) -> String {
    precondition(code.startIndex < product)
    precondition(product < package)
    precondition(package < code.endIndex)
    let lead = "    .executable"
    var out = String(code[code.startIndex..<product])
    out += "\(lead)(name: \"\(peer)\", targets: [\"\(peer)\"]),\n"
    out += String(code[product..<package])
    out += "\(lead)Target(name: \"\(peer)\", dependencies: [\"\(nest)\"]),\n"
    out += String(code[package...])
    return out
  }

}

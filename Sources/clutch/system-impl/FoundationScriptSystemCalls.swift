struct FoundationScriptSystemCalls: SystemCalls {

  typealias FS = FoundationScript

  func environment(_ keys: Set<String>) -> [String: String] {
    FS.environment(keys)
  }

  func printErr(_ message: String) {
    FS.printErr(message)
  }

  func printOut(_ message: String) {
    FS.printOut(message)
  }

  func createDir(_ path: String) throws {
    try FS.createDir(path)
  }

  func lastModified(_ path: String) -> LastModified? {
    FS.lastMod(path)
  }

  func fileStatus(_ path: String) -> Bool? {
    FS.fileStatus(path)
  }

  func now() -> LastModified {
    FS.now()
  }

  func runProcess(_ path: String, args: [String]) async throws {
    try await FS.runProcess(path, args: args)
  }

  func readFile(_ path: String) async throws -> String {
    try await FS.readFile(path)
  }

  func writeFile(path: String, content: String) async throws {
    try await FS.writeFile(path: path, content: content)
  }

  func findExecutable(named name: String) async throws -> String {
    try await FS.findExecutable(named: name)
  }
}

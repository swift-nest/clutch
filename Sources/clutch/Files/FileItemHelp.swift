extension FileItemSeeker {
  func findFile(_ NestKey: NestKey, _ path: String) throws -> NestItem {
    try find(kind: .file, NestKey: NestKey, path, status: nil)
  }
  func seekFile(_ NestKey: NestKey, _ path: String) -> NestItem {
    seek(kind: .file, NestKey: NestKey, path, status: nil)
  }
  func seekDir(_ NestKey: NestKey, _ path: String) -> NestItem {
    seek(kind: .dir, NestKey: NestKey, path, status: nil)
  }
  func seekDirOrNil(_ NestKey: NestKey, _ path: String) -> NestItem? {
    let result = seek(kind: .dir, NestKey: NestKey, path, status: nil)
    return result.status.isDir ? result : nil
  }
}

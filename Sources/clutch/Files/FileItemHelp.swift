extension FileItemSeeker {
  func seekFile(_ NestKey: NestKey, _ path: String) -> NestItem {
    seek(kind: .file, NestKey: NestKey, path)
  }
  func seekDir(_ NestKey: NestKey, _ path: String) -> NestItem {
    seek(kind: .dir, NestKey: NestKey, path)
  }
  func seekDirOrNil(_ NestKey: NestKey, _ path: String) -> NestItem? {
    let result = seek(kind: .dir, NestKey: NestKey, path)
    return result.status.isDir ? result : nil
  }
}

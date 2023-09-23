enum Dict {
  static func from<Key: Equatable, Value>(
    _ keys: Set<Key>,
    _ getValue: (Key) -> Value?
  ) -> [Key: Value] {
    let kv: [(Key, Value)] = keys.compactMap { key in
      if let value = getValue(key) {
        return (key, value)
      }
      return nil
    }
    return Dictionary(uniqueKeysWithValues: kv)
  }
}

enum Str {
  /// treat empty string as nil, esp. for compactMap
  static func emptyToNil(_ s: String?) -> String? {
    (s?.isEmpty ?? true) ? nil : s
  }
}

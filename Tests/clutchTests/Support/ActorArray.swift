/// Wrapping array means access is implicitly asynchronous
actor ActorArray<T: Sendable> {
  private var array: [T]
  public init() {
    array = [T]()
  }
  public func copy() -> [T] {
    array
  }
  public func append(_ item: T) {
    array.append(item)
  }
  public func append<S: Sequence<T>>(contentsOf sequence: S) where S: Sendable {
    array.append(contentsOf: sequence)
  }
}


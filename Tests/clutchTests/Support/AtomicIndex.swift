import Atomics

/// Thread-safe incrementing index
public struct AtomicIndex: Sendable {
  private let nextInt: ManagedAtomic<Int>

  public init(next: Int = 0) {
    self.nextInt = ManagedAtomic(next)
  }

  /// Get next value without incrementing
  public func peekNext() -> Int {
    nextInt.load(ordering: .sequentiallyConsistent)
  }

  /// Get next value (warning: wraps without warning)
  public func next() -> Int {
    nextInt.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
  }

  public var str: String { "\(peekNext())" }
}


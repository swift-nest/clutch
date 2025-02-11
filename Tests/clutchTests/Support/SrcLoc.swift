import Atomics
import XCTest

/// Capture Source location at test creation time for use in assertions.
///
/// Messages prefixed with `{index}] {prefix}`
struct SrcLoc {

  private static let index = ManagedAtomic<Int>(100)
  private static func nextIndex() -> Int {
    index.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
  }

  let index: Int
  let prefix: String
  let file: StaticString
  let line: UInt

  /// Staticly index
  init(
    prefix: String = "",
    _ file: StaticString = #file,
    _ line: UInt = #line
  ) {
    let index = Self.nextIndex()
    self.init(index: index, prefix: prefix, file, line)
  }
  /// Index directly
  init(
    index: Int,
    prefix: String = "",
    _ file: StaticString = #file,
    _ line: UInt = #line
  ) {
    self.file = file
    self.line = line
    self.index = index
    self.prefix = prefix
  }
}

// MARK: Assertions use the file+line location and index messages
extension SrcLoc {

  func message(_ label: @autoclosure () -> String) -> String {
    "\(index)] \(prefix)\(label())"
  }
  /// Expected/actual comparison
  @discardableResult
  func ea<T: Equatable>(
    _ exp: T,
    _ act: T,
    _ label: @autoclosure () -> String
  ) -> Bool {
    guard exp != act else {
      return true
    }
    XCTAssertEqual(exp, act, message(label()), file: file, line: line)
    return false
  }

  /// fail with message and location
  func fail(_ label: @autoclosure () -> String) {
    XCTFail("\(message(label()))", file: file, line: line)
  }

  /// Boolean test (with output)
  @discardableResult
  func ok(
    _ test: Bool,
    _ label: @autoclosure () -> String
  ) -> Bool {
    guard !test else {
      return true
    }
    XCTFail("\(message(label()))", file: file, line: line)
    return false
  }

  /// Boolean test (with inout)
  @discardableResult
  func okAnd(
    _ rhs: inout Bool,
    _ test: Bool,
    _ label: @autoclosure () -> String
  ) -> Bool {
    let result = ok(test, label())
    if !result && rhs {
      rhs = false
    }
    return result
  }
  /// Expect/actual (with inout)
  @discardableResult
  func eaAnd<T: Equatable>(
    _ rhs: inout Bool,
    _ exp: T,
    _ act: T,
    _ label: @autoclosure () -> String
  ) -> Bool {
    let result = ea(exp, act, label())
    if !result && rhs {
      rhs = false
    }
    return result
  }
  /// conditional expect/act runs only if expect is not nil
  @discardableResult
  func eaAndIf<T: Equatable>(
    _ rhs: inout Bool,
    _ exp: T?,
    _ act: T?,
    _ label: @autoclosure () -> String
  ) -> Bool {
    guard let exp else {
      return true
    }
    return eaAnd(&rhs, exp, act, label())
  }
}

// MARK: Factories
extension SrcLoc {

  /// Factory for reliable indexing
  struct Maker {
    private let count: AtomicIndex
    init(count: Int = 100) {
      self.count = AtomicIndex(next: count)
    }
    func sl(
      prefix: String = "",
      _ file: StaticString = #file,
      _ line: UInt = #line
    ) -> SrcLoc {
      SrcLoc(index: count.next(), prefix: prefix, file, line)
    }
  }
  /// Factory with unreliable indexing
  static func sl(
    prefix: String = "",
    _ file: StaticString = #file,
    _ line: UInt = #line
  ) -> SrcLoc {
    Self(prefix: prefix, file, line)
  }
}

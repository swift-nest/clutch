import XCTest

@testable import clutchLib

enum TestHelper {
  static let inCI = nil != FoundationScript.environment("CLUTCH_CI")
  static let quiet = true
  static let runFlaky = nil != FoundationScript.environment("CLUTCH_FLAKY")
  typealias SrcLoc = (file: StaticString, line: UInt)
  static func loc(
    _ file: StaticString = #filePath,
    _ line: UInt = #line
  ) -> SrcLoc {
    (file, line)
  }
  static func ea<T: Equatable>(
    _ exp: T,
    _ act: T,
    _ label: String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(exp, act, label ?? "", file: file, line: line)
  }
  static func ea<T: Equatable>(
    _ exp: T,
    _ act: T,
    _ label: String? = nil,
    _ debug: SrcLoc  // put first? label label?
  ) {
    XCTAssertEqual(exp, act, label ?? "", file: debug.0, line: debug.1)
  }

}

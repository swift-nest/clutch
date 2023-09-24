import Script
import XCTest
@testable import clutchLib

enum TestHelper {
  // true when committed; sometimes false when local
  static let inCI = nil != FoundationScript.environment("CLUTCH_CI")
  static let quiet = true
  typealias SrcLoc = (file: StaticString, line: UInt)
  static func loc(
    _ file: StaticString = #file,
    _ line: UInt = #line
  ) -> SrcLoc {
    (file, line)
  }
  static func ea<T: Equatable>(
    _ exp: T,
    _ act: T,
    _ label: String? = nil,
    file: StaticString = #file,
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
enum Either<LHS, RHS> {
  case lhs(LHS)
  case rhs(RHS)
}

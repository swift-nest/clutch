import XCTest
import clutch

import struct SystemPackage.FilePath

@testable import clutchLib

final class DriverTests: XCTestCase {
  typealias Scenario = ClutchCommandScenario
  typealias KnownCalls = KnownSystemCalls
  typealias ScenarioCase = KnownSystemCallFixtures.ScenarioCase
  typealias Check = KnownSystemCallFixtures.Check
  typealias SceneCheck = KnownSystemCallFixtures.ScenarioCheck
  typealias CallCheck = RecordSystemCalls.IndexFuncCall
  typealias ClutchErr = ClutchDriver.Problem.ErrParts
  typealias UserAsk = DriverConfig.UserAsk

  let fixtures = KnownSystemCallFixtures()
  let dataToStdout = false

  public func testAllScenarios() async throws {
    let cases = Scenario.allCases
    //let cases: [Scenario] = [.nest(.peers)]
    for scenario in cases {
      let sc =  fixtures.newScenario(scenario)
      try await runTest(scenario, sc)
    }
  }

  public func testSyntaxErr() async throws {
    let scenario: Scenario = .nest(.dir)
    let sc =  fixtures.newScenario(scenario)
    guard let prefix = UserAsk.nestDir.prefix else {
      preconditionFailure("no prefix on UserAsk.nestDir")
    }
    let args = sc.args.with(args: ["\(prefix)NOT_FOUND"])
    try await runTest(.nest(.dir), .sc(sc.calls, args, [.clutchErr("syntax")]))
  }

  func runTest(_ scenario: Scenario, _ test: ScenarioCase) async throws {
    for (error, srcLoc) in test.calls.internalErrors {
        XCTFail(error, file: srcLoc.file, line: srcLoc.line)
    }
    guard test.calls.internalErrors.isEmpty else {
      return
    }
    let (calls, args, checks) = (test.calls, test.args.args, test.checks)
    let name = calls.scenarioName
    do {
      let recordCalls = try await run(label: name, calls: calls, args: args)
      check(scenario, checks: checks, calls: recordCalls)
    } catch  {
      if let err = error as? ClutchDriver.Problem.ErrParts {
        check(scenario, checks: checks, clutchError: err)
      } else {
        check(scenario, checks: checks, error: error)
      }
    }
  }

  func check(_ test: Scenario, checks: [Check], calls: RecordSystemCalls) {
    let found = calls.renders
    func match(_ check: SceneCheck, _ callCheck: CallCheck) -> Bool {
      check.call == callCheck.funct
        && callCheck.call.contains(check.match)
    }
    for check in checks.scenarios {
      if nil == found.first(where: { match(check, $0) }) {
        XCTFail("\(test) expected \(check)")
      }
    }
    for error in checks.errors {
      XCTFail("\(test) missing error \(error.label)")
    }
  }
  func check(_ test: Scenario, checks: [Check], clutchError: ClutchErr) {
    checkError(test, checks: checks, error: "\(clutchError)")
  }
  func check(_ test: Scenario, checks: [Check], error: Error) {
    checkError(test, checks: checks, error: "\(error)")
  }
  func checkError(_ test: Scenario, checks: [Check], error: String) {
    for check in checks.scenarios {
      XCTFail("\(test) expected \(check)")
    }
    for check in checks.errors {
      if !error.contains(check.match) {
        XCTFail("\(test)\nexp error: \(check.label)\ngot error: \(error)")
      }
    }
  }

  @discardableResult
  public func run(
    label: String,
    calls: KnownCalls,
    args: [String]
  ) async throws -> RecordSystemCalls {
    let count = Count(next: 100)
    let recordCalls = RecordSystemCalls(delegate: calls, counter: count)
    let cwd = FilePath(".")
    let home = calls.envKeyValue["HOME"] ?? "UNKNOWN HOME"  // ? fail-fast?
    let (ask, mode) = AskData.read(args, cwd: cwd, sysCalls: recordCalls)
    let driver = ClutchDriver(sysCalls: recordCalls, mode: mode)

    func finish(_ err: (any Error)?) {
      let lines = recordCalls.renderLines(home: home, date: true)
      let linesJoined = lines.joined(separator: "\n")
      let prefix = "## \(label) data"
      let dump = "\(prefix) - START\n\(linesJoined)\n\(prefix) - END"
      if let err = err {
        XCTFail("[\(label)] \(err)")
        print(dump)
      } else if dataToStdout || !TestHelper.quiet {
        print(dump)
      }
    }
    var err: (any Error)?
    do {
      try await driver.runAsk(cwd: cwd, args: args, ask: ask)
    } catch {
      err = error
    }
    finish(err)
    return recordCalls
  }
}

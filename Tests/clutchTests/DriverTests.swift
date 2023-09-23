import XCTest
import clutch

import struct SystemPackage.FilePath

@testable import clutchLib

final class DriverTests: XCTestCase {
  typealias Scenario = ClutchCommandScenario
  typealias KnownCalls = KnownSystemCalls
  typealias Check = KnownSystemCallFixtures.ScenarioCheck
  typealias CallCheck = RecordSystemCalls.IndexFuncCall

  let fixtures = KnownSystemCallFixtures()
  let dataToStdout = false

  public func testAllScenarios() async throws {
    let cases = Scenario.allCases
    //let cases: [Scenario] = [.nest(.peers)]
    for scenario in cases {
      let (calls, scenarioArgs, checks) = fixtures.newScenario(scenario)
      for (error, srcLoc) in calls.internalErrors {
        XCTFail(error, file: srcLoc.file, line: srcLoc.line)
      }
      if calls.internalErrors.isEmpty {
        let name = scenario.name
        let args = scenarioArgs.args
        let recordCalls = try await run(label: name, calls: calls, args: args)
        check(scenario, calls: recordCalls, checks: checks)
      }
    }
  }

  func check(_ test: Scenario, calls: RecordSystemCalls, checks: [Check]) {
    let found = calls.renders
    func match(_ check: Check, _ callCheck: CallCheck) -> Bool {
      check.call == callCheck.funct
        && callCheck.call.contains(check.match)
    }
    for check in checks {
      if nil == found.first(where: { match(check, $0) }) {
        XCTFail("\(test) expected \(check)")
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

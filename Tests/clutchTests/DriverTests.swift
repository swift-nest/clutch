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
      let scenarioCase =  fixtures.newScenario(scenario)
      try await runTest(scenarioCase)
    }
  }

  public func testErrNestNotFound() async throws {
    let scenario: Scenario = .nest(.dir)
    let sc =  fixtures.newScenario(scenario)
    sc.calls.remove(.manifest)
    guard let prefix = UserAsk.nestDir.prefix else {
      throw setupFailed("no prefix on UserAsk.nestDir")
    }
    let unfound = "NOT_FOUND"
    sc.with(args: ["\(prefix)\(unfound)"], checks: [.error(unfound)])
    try await runTest(sc)
  }

  public func testErrNestSansManifest() async throws {
    let scenario: Scenario = .peer(.run)
    let sc =  fixtures.newScenario(scenario)
    guard sc.calls.remove(.manifest) else {
      throw setupFailed("No manifest to remove")
    }
    let match = "manifest"
    sc.with(checks: [.error(match)])
    try await runTest(sc)
  }

  func setupFailed(_ m: String) -> Err {
    Err.err("Setup failed: \(m)")
  }
  func runTest(_ test: ScenarioCase) async throws {
    guard test.calls.internalErrors.isEmpty else {
      for (error, srcLoc) in test.calls.internalErrors {
        XCTFail(error, file: srcLoc.file, line: srcLoc.line)
      }
      return
    }
    let (recordCalls, err) = await run(test)
    guard let err = err else {
      check(test,  calls: recordCalls)
      return
    }
    guard let clutchError = err as? ClutchDriver.Problem.ErrParts else {
      check(test, error: err)
      return
    }
    check(test, clutchError: clutchError)
  }

  func check(_ test: ScenarioCase, calls: RecordSystemCalls) {
    let found = calls.renders
    func match(_ check: SceneCheck, _ callCheck: CallCheck) -> Bool {
      check.call == callCheck.funct
        && callCheck.call.contains(check.match)
    }
    for check in test.checks.scenarios {
      if nil == found.first(where: { match(check, $0) }) {
        XCTFail("\(test) expected \(check)")
      }
    }
    for error in test.checks.errors {
      XCTFail("\(test) expected error \(error.label)")
    }
  }
  func check(_ test: ScenarioCase, clutchError: ClutchErr) {
    checkError(test, error: "\(clutchError)")
  }
  func check(_ test: ScenarioCase, error: Error) {
    checkError(test, error: "\(error)")
  }
  func checkError(_ test: ScenarioCase, error: String) {
    for check in test.checks.scenarios {
      XCTFail("\(test) expected \(check)")
    }
    for check in test.checks.errors {
      if !error.contains(check.match) {
        XCTFail("\(test)\nexp error: \(check.label)\ngot error: \(error)")
      }
    }
  }

  public func run(
    _ test: ScenarioCase
  ) async -> (RecordSystemCalls, (any Error)?) {
    let (recordCalls, error) = await runCapturing(test)
    var dump = dataToStdout || !TestHelper.quiet
    let expectedErrors = test.checks.filter{ $0.isError }
    let expectError = !expectedErrors.isEmpty
    let haveError = nil != error
    if haveError != expectError {
      if let err = error {
        XCTFail("[\(test.scenario.name)] \(err)") // unexpected error
      } else {
        let expected = expectedErrors.map { "\($0)" }
        XCTFail("[\(test.scenario.name)] expected errors \(expected)")
      }
      dump = true
    }
    if dump {
      let home = test.calls.envKeyValue["HOME"] ?? "UNKNOWN HOME"  // ? fail-fast?
      let lines = recordCalls.renderLines(home: home, date: true)
      let linesJoined = lines.joined(separator: "\n")
      let prefix = "## \(test.scenario.name) data"
      let dump = "\(prefix) - START\n\(linesJoined)\n\(prefix) - END"
      print(dump)
    }
    return (recordCalls, error)
  }

  func runCapturing(
    _ test: ScenarioCase
  ) async -> (RecordSystemCalls, (any Error)?) {
    let count = Count(next: 100)
    let recordCalls = RecordSystemCalls(delegate: test.calls, counter: count)
    let cwd = FilePath(".")
    let args = test.args.args
    let (ask, mode) = AskData.read(args, cwd: cwd, sysCalls: recordCalls)
    let driver = ClutchDriver(sysCalls: recordCalls, mode: mode)

    var err: (any Error)?
    do {
      try await driver.runAsk(cwd: cwd, args: args, ask: ask)
    } catch {
      err = error
    }
    return (recordCalls, err)
  }
}

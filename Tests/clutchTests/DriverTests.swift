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
  typealias ErrParts = ClutchDriver.Problem.ErrParts
  typealias UserAsk = DriverConfig.UserAsk

  let fixtures = KnownSystemCallFixtures()
  let dataToStdout = false
  let commandPrefixes = CommandPrefixes()

  public func testAllScenarios() async throws {
    let cases = Scenario.allCases
    //let cases: [Scenario] = [.nest(.peers)]
    for scenario in cases {
      let scenarioCase =  fixtures.newScenario(scenario)
      try await runTest(scenarioCase)
    }
  }

  public func testErrNestNameBad() async throws {
    let sc =  fixtures.newScenario(.nest(.dir))
    let prefix = commandPrefixes.nestDir
    var checks: [Check] = [.errPart(.ask(.syntaxErr))] // actual is syntax err
    let unfound = "1BAD_NAME" // invalid as module name
    checks += [.errPart(.reason(.badSyntax(unfound)))]
    sc.with(args: ["\(prefix)\(unfound)"], checks: checks)
    try await runTest(sc)
  }

  public func testErrNestNotFound() async throws {
    let sc =  fixtures.newScenario(.nest(.dir))
    let prefix = commandPrefixes.nestDir
    let unfound = "NOT_FOUND" // valid as module name, but no such dir
    sc.with(args: ["\(prefix)\(unfound)"], checks: [.error(unfound)])
    try await runTest(sc)
  }

  public func testErrNestNoManifest() async throws {
    let sc =  fixtures.newScenario(.peer(.run))
    guard sc.calls.remove(.manifest) else {
      throw setupFailed("No manifest to remove")
    }
    sc.with(checks: [.errPart(.input(.resource(.manifest)))])
    try await runTest(sc)
  }

  // MARK: Helpers
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
      checkNormal(test,  calls: recordCalls)
      return
    }
    for check in test.checks.scenarios {
      XCTFail("\(test) expected \(check)")
    }
    guard let errParts = err as? ErrParts else {
      checkError(test, error: "\(err)")
      return
    }
    checkErrParts(test, errParts: errParts)
  }

  func checkNormal(_ test: ScenarioCase, calls: RecordSystemCalls) {
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
    // already reported extra errors
  }
  func checkErrParts(_ test: ScenarioCase, errParts actual: ErrParts) {
    for expect in test.checks.errParts {
      if let errorMessage = expect.check(actual) {
        XCTFail("\(test) \(errorMessage)")
      }
    }
  }
  func checkError(_ test: ScenarioCase, error: String) {
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
        for expectedError in expectedErrors {
          XCTFail("[\(test.scenario.name)] missed error: \(expectedError)")
        }
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
  struct CommandPrefixes {
    let nestDir: String
    let nestPeers: String
    let peerPath: String
    let catPeer: String
    init() {
      self.nestDir = UserAsk.nestDir.prefix!
      self.nestPeers = UserAsk.nestPeers.prefix!
      self.peerPath = UserAsk.pathPeer.prefix!
      self.catPeer = UserAsk.catPeer.prefix!
    }
  }
}

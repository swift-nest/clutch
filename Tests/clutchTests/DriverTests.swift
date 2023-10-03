import XCTest
import clutchLib

import struct SystemPackage.FilePath

@testable import clutchLib

/// Integration test all normal scenarios and some error scenarios and effects.
///
/// In most cases, checks are incomplete.
///
/// Known-missing tests:
/// - Script with @main gets peer source name name.swift, not main.swift
///
/// Known-missing error tests:
/// - No listing for peer in manifest without peer-source dir
/// - Cannot read manifest?
/// - Cannot update manifest for new peer
/// - Cannot create file for new peer

final class DriverTests: XCTestCase {
  typealias Scenario = ClutchCommandScenario
  typealias KnownCalls = KnownSystemCalls
  typealias ScenarioCase = KnownSystemCallFixtures.ScenarioCase
  typealias Check = KnownSystemCallFixtures.Check
  typealias SceneCheck = KnownSystemCallFixtures.ScenarioCheck
  typealias CallCheck = RecordSystemCalls.IndexFuncCall
  typealias ErrParts = ClutchDriver.Errors.ErrParts
  typealias UserAsk = DriverConfig.UserAsk

  let fixtures = KnownSystemCallFixtures()
  let dataToStdout = false
  let commandPrefixes = CommandPrefixes()

  public func testAllScenarios() async throws {
    let cases = Scenario.allCases
    //let cases: [Scenario] = [.nest(.peers)]
    for scenario in cases {
      let scenarioCase = fixtures.newScenario(scenario)
      await runTest(scenarioCase)
    }
  }

  public func testTraceBuildRun() async throws {
    let sc = fixtures.newScenario(.script(.new))
    sc.calls.configEnv(.CLUTCH_LOG, "anything")
    let checks: [Check] = ["Create", "Add", "New", "Build", "Run"].map {
      .sysCall(.printErr, "TRACE clutch: \($0)")
    }
    sc.with(checks: checks)
    await runTest(sc)
  }

  public func testErrNestNameBad() async throws {
    let sc = fixtures.newScenario(.nest(.dir))
    let prefix = commandPrefixes.nestDir
    var checks: [Check] = [.errPart(.ask(.syntaxErr))]  // actual is syntax err
    let unfound = "1BAD_NAME"  // invalid as module name
    checks += [.errPart(.problem(.badSyntax(unfound)))]
    sc.with(args: ["\(prefix)\(unfound)"], checks: checks)
    await runTest(sc)
  }

  public func testErrNestNotFound() async throws {
    let sc = fixtures.newScenario(.nest(.dir))
    let prefix = commandPrefixes.nestDir
    let unfound = "NOT_FOUND"  // valid as module name, but no such dir
    sc.with(
      args: ["\(prefix)\(unfound)"],
      checks: [  // two ways to check errors
        .error(unfound),  // any error containing the message
        .errPart(.problem(.opFailed(unfound))),  // ErrParts.problem = .bad(match)
      ]
    )
    await runTest(sc)
  }

  public func testErrPeerRunNoManifestOn() async throws {
    let sc = fixtures.newScenario(.peer(.run))
    guard sc.calls.remove(.manifest) else {
      throw setupFailed("No manifest to remove")
    }
    sc.with(checks: [.errPart(.subject(.resource(.manifest, "")))])
    await runTest(sc)
  }

  public func testErrScriptNewNoManifest() async throws {
    let sc = fixtures.newScenario(.script(.new))
    guard sc.calls.remove(.manifest) else {
      throw setupFailed("No manifest to remove")
    }
    sc.with(checks: [
      .errPart(.subject(.resource(.manifest, ""))),
      .errPart(.problem(.fileNotFound(""))),
    ])
    await runTest(sc)
  }

  public func testErrScriptRunPeerMissing() async throws {
    let sc = fixtures.newScenario(.script(.uptodate))
    guard sc.calls.remove(.peer) else {
      throw setupFailed("No peer to remove")
    }
    sc.with(checks: [
      .errPart(.subject(.resource(.peer, ""))),
      .errPart(.problem(.fileNotFound(""))),
    ])
    await runTest(sc)
  }

  public func testErrListPeersNoManifest() async throws {
    let sc = fixtures.newScenario(.nest(.peers))
    guard sc.calls.remove(.manifest) else {
      throw setupFailed("No manifest to remove")
    }
    sc.with(checks: [
      .errPart(.subject(.resource(.manifest, ""))),
      .errPart(.problem(.fileNotFound(""))),
    ])
    await runTest(sc)
  }

  public func testErrPeerCatPeerMissing() async throws {
    let sc = fixtures.newScenario(.script(.new))
    sc.with(
      args: ["\(commandPrefixes.catPeer)script"],  // urk: known value
      checks: [
        .errPart(.subject(.resource(.peer, ""))),
        .errPart(.problem(.fileNotFound("peer script"))),
      ]
    )
    await runTest(sc)
  }

  public func testErrPeerCatPeerEmpty() async throws {
    let sc = fixtures.newScenario(.peer(.cat))
    guard sc.calls.setFileDetails(.peer, content: "//") else {
      throw setupFailed("Unable to clear peer")
    }
    sc.with(
      checks: [
        .errPart(.subject(.resource(.peer, ""))),
        .errPart(.problem(.invalidFile("peer script"))),
      ])
    await runTest(sc)
  }

  /// Test each path to a nest name.
  ///
  /// Does not test combinations of settings, where priority would matter.
  public func testFindNest() {
    let sc = fixtures.newScenario(.nest(.dir))
    typealias EnvVal = (name: EnvName, value: String)
    typealias Config = ([EnvVal]) -> Void
    struct TC {
      let label: String
      let input: String?
      let name: String
      let path: FilePath
      let envVals: [EnvVal]
      init(
        _ label: String,
        _ input: String?,
        _ name: String,
        p path: FilePath,
        _ envVals: [EnvVal] = []
      ) {
        self.label = label
        self.input = input
        self.name = name
        self.path = path
        self.envVals = envVals
      }
    }
    let defName = "Nest"
    let altName = "AltNest"
    let altHomeRel = "home-alt"
    let randomName = "random"
    let home = FilePath(sc.calls.seekEnv(.HOME) ?? "BAD")
    let homeGit = home.appending("git")
    let homeGitNest = homeGit.appending(defName)
    let homeGitAltNest = homeGit.appending(altName)
    let homeAltRel = home.appending(altHomeRel)
    let homeAltRelNest = homeAltRel.appending(defName)
    let homeAltRelAltNest = homeAltRel.appending(altName)
    let base = FilePath("BASE")
    let baseNest = base.appending(defName)
    let baseAltNest = base.appending(altName)
    let randomPath = FilePath("randomBase").appending(randomName)
    // swift-format-ignore
    let tests: [TC] = [
      // default
      TC("default", nil, defName, p: homeGitNest),
      TC("alt-name-input", altName, altName, p: homeGitAltNest),
      TC("alt-name-env", nil, altName, p: homeGitAltNest,
         [(.CLUTCH_NEST_NAME, altName)]),
      TC("full-env-path", nil, randomName, p: randomPath,
         [(.CLUTCH_NEST_PATH, randomPath.string)]),
      TC("env-rpath-default", nil, defName, p: homeAltRelNest,
         [(.CLUTCH_NEST_RELPATH, altHomeRel)]),
      TC("env-rpath-name-input", altName, altName, p: homeAltRelAltNest,
         [(.CLUTCH_NEST_RELPATH, altHomeRel)]),
      TC("env-base-default", nil, defName, p: baseNest,
         [(.CLUTCH_NEST_BASE, base.string)]),
      TC("env-base-name-input", altName, altName, p: baseAltNest,
         [(.CLUTCH_NEST_BASE, base.string)]),
      TC("env-base-name-env", nil, altName, p: baseAltNest,
         [
          (.CLUTCH_NEST_BASE, base.string),
          (.CLUTCH_NEST_NAME, altName)
         ]),
    ]
    let envDirs: [EnvName] = [.CLUTCH_NEST_BASE, .CLUTCH_NEST_PATH]
    for test in tests {
      let next = sc.calls.copyInit()
      next.setFileDetails(path: test.path.string, status: .dir)
      for (name, value) in test.envVals {
        next.envKeyValue[name.key] = value
        if envDirs.contains(name) {
          next.setFileDetails(path: value, status: .dir)
        } else if name == .CLUTCH_NEST_RELPATH {
          next.setFileDetails(path: homeAltRel.string, status: .dir)
          let key: EnvName = .CLUTCH_NEST_NAME
          let relName = test.input ?? next.envKeyValue[key.key] ?? defName
          let path = homeAltRel.appending(relName)
          next.setFileDetails(path: path.string, status: .dir)
        }
      }
      let driver = ClutchDriver(sysCalls: next, mode: .QUIET)
      let result = try? driver.findNest(inputNestName: test.input)
      if let result = result {
        XCTAssertEqual(test.name, result.nestOnly.nest, "name for \(test)")
        XCTAssertEqual(test.path, result.nestDir, "path for \(test)")
      } else {
        _ = try? driver.findNest(inputNestName: test.input)
        XCTFail("\(test) threw error")
      }
    }
  }

  // MARK: Helpers
  func setupFailed(_ m: String) -> Err {
    Err.err("Setup failed: \(m)")
  }
  func runTest(_ test: ScenarioCase, caller: StaticString = #function) async {
    guard test.calls.internalErrors.isEmpty else {
      for (error, srcLoc) in test.calls.internalErrors {
        XCTFail(error, file: srcLoc.file, line: srcLoc.line)
      }
      return
    }
    let (recordCalls, err) = await runCheckingErrMismatch(test)
    checkCalls(test, calls: recordCalls)  // check even for errors

    defer {
      if dataToStdout || !TestHelper.quiet || !test.pass {
        // permit missing HOME since that might be tested
        let home = test.calls.envKeyValue["HOME"] ?? "UNKNOWN HOME"
        let lines = recordCalls.renderLines(home: home, date: true)
        let linesJoined = lines.joined(separator: "\n")
        let prefix = "## \(caller) (\(test.scenario.name)) data"
        let dump = "\(prefix) - START\n\(linesJoined)\n\(prefix) - END"
        print(dump)
      }
    }

    guard let err = err else {
      return
    }
    guard let errParts = err as? ErrParts else {
      checkErrorExpected(test, error: "\(err)")
      return
    }
    checkErrPartsExpected(test, errParts: errParts)
  }

  func checkCalls(_ test: ScenarioCase, calls: RecordSystemCalls) {
    let found = calls.renders
    func match(_ check: SceneCheck, _ callCheck: CallCheck) -> Bool {
      check.call == callCheck.funct
        && callCheck.call.contains(check.match)
    }
    for check in test.checks.scenarios {
      if nil == found.first(where: { match(check, $0) }) {
        XCTFail("\(test) expected \(check)")
        fail(&test.pass)
      }
    }
    // already reported extra errors
  }
  func checkErrPartsExpected(_ test: ScenarioCase, errParts actual: ErrParts) {
    for expect in test.checks.errParts {
      if let errorMessage = expect.check(actual) {
        XCTFail("\(test) \(errorMessage)")
        fail(&test.pass)
      }
    }
  }
  func checkErrorExpected(_ test: ScenarioCase, error: String) {
    for check in test.checks.errors {
      if !error.contains(check.match) {
        XCTFail("\(test)\nexp error: \(check.label)\ngot error: \(error)")
        fail(&test.pass)
      }
    }
  }

  func runCheckingErrMismatch(
    _ test: ScenarioCase
  ) async -> (RecordSystemCalls, (any Error)?) {
    let (recordCalls, error) = await runCapturing(test)
    let expectedErrors = test.checks.filter { $0.isError }
    let expectError = !expectedErrors.isEmpty
    let haveError = nil != error
    if haveError != expectError {
      if let err = error {
        XCTFail("[\(test.scenario.name)] \(err)")  // unexpected error
        fail(&test.pass)
      } else {
        for expectedError in expectedErrors {
          XCTFail("[\(test.scenario.name)] missed error: \(expectedError)")
          fail(&test.pass)
        }
      }
    }
    return (recordCalls, error)
  }

  func fail(_ pass: inout Bool) {
    if pass {
      pass = false
    }
  }

  func runCapturing(
    _ test: ScenarioCase
  ) async -> (RecordSystemCalls, (any Error)?) {
    let count = Count(next: 100)
    let recordCalls = RecordSystemCalls(delegate: test.calls, counter: count)
    let cwd = FilePath(".")
    let args = test.args.args
    var (ask, mode) = AskData.read(args, cwd: cwd, sysCalls: recordCalls)
    mode = mode.with(logConfig: recordCalls.seekEnv(.CLUTCH_LOG))
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

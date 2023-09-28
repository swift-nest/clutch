import XCTest

@testable import clutchLib

final class ClutchTests: XCTestCase {
  let swift = true
  let notSwift = false
  typealias ScriptParts = ScriptFilenameParts
  typealias PartsTuple = (
    file: String, mod: String, nest: String?, swift: Bool
  )

  func testBuildOptionParsing() {
    typealias Options = PeerNest.BuildOptions
    struct TC {
      let input: String
      let expect: [String]
      let debug: Bool
      init(_ ins: String, _ exp: [String], _ debug: Bool = false) {
        self.input = ins
        self.expect = exp
        self.debug = debug
      }
    }
    let debugQuiet = Options.DEFAULT.args
    let releaseQuiet = ["-c", "release", "--quiet"]
    let releaseLoud = ["-c", "release"]
    let releaseVerbose = ["-c", "release", "--verbose"]
    let tests: [TC] = [
      TC("", debugQuiet, true),
      TC("debug", debugQuiet, true),
      TC("loud debug", ["-c", "debug"], true),
      TC("release", releaseQuiet),
      TC("release quiet", releaseQuiet),
      TC("release loud", releaseLoud),
      TC("release verbose", releaseVerbose),
      TC("@1@2", ["1", "2"], true),
      TC("@1@2@release@", ["1", "2", "release"])
    ]
    for test in tests {
      let actual = Options.parse(test.input)
      XCTAssertEqual(test.debug, actual.debug, "debug \(test.input)")
      XCTAssertEqual(test.expect, actual.args, "args \(test.input)")
    }
  }

  func testScriptParts() throws {

    let tests: [(String, PartsTuple)] = [
      ("a", ("a", "a", "", notSwift)),  //
      ("a.swift", ("a.swift", "a", "", swift)),  //
      ("a.Nest", ("a.Nest", "a", "Nest", notSwift)),  //
      ("a.n.SWIFT", ("a.n.SWIFT", "a", "n", swift)),  //
      ("a.b.y.z", ("a.b.y.z", "a", "z", notSwift)),  //
    ]
    func makeParts(_ r: PartsTuple) -> ScriptParts {
      ScriptParts(r.file, swift: r.swift, module: r.mod, nest: r.nest)
    }
    for (input, expected) in tests {
      let exp = Self.makeParts(expected)
      let act = ScriptParts.make(input)
      ea(exp, act, input)
    }
  }

  struct Config {
    public let module: String
    public let nestName: String
    public let nest: FileItem<NestKey>
  }
  func testConfig() throws {
    typealias NDCfg = DriverConfig
    // TODO: configure pathSep for windows
    // nothing in environment but path
    let home = "/Users/NONE"
    let homeGit = "\(home)/git"
    let defaultNest = "\(homeGit)/Nest"

    let clutchSys = KnownSystemCalls()
    func make(_ parts: ScriptParts) throws -> Config {
      guard let nestName = NDCfg.findNest(parts.nest, using: clutchSys) else {
        throw Err.err("not found")
      }
      return Config(
        module: parts.module,
        nestName: nestName.name,
        nest: nestName.nest
      )
    }

    // default nest and basic naming
    let script = Self.makeParts(("script.swift", "script", nil, swift))
    clutchSys.setEnv([.HOME: home])
    clutchSys.setDirs([home, homeGit, defaultNest])
    var result = try make(script)  // default nest
    ea("Nest", result.nestName)
    ea(script.module, result.module)
    ea(defaultNest, result.nest.fullPath)

    // specify nest in script and rpath in env
    let toolName = "tool"
    let altNestName = "NestPath"
    let tool = "\(toolName).i.\(altNestName).sw"
    let toolNest = Self.makeParts((tool, toolName, altNestName, false))
    let rpNestBase = "\(home)/rpath"
    let rpNestPath = "\(rpNestBase)/\(altNestName)"
    clutchSys.setEnv([.HOME: home, .NEST_HOME_RPATH: "rpath"])
    clutchSys.setDirs([home, rpNestBase, rpNestPath])
    result = try make(toolNest)  // rpath + script-nest
    ea(toolName, result.module)
    ea(altNestName, result.nestName)
    ea(rpNestPath, result.nest.fullPath)

    // nest by path - ignores other features
    let altNest = "\(home)/foo/\(altNestName)"
    clutchSys.setEnv([.NEST_PATH: altNest], clear: false)
    clutchSys.setDirs([altNest])
    result = try make(script)  // env.nest_path
    ea(altNestName, result.nestName)
    ea(script.module, result.module)
    ea(altNest, result.nest.fullPath)
  }

  func ea<T: Equatable>(
    _ exp: T,
    _ act: T,
    _ NestKey: String? = nil,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    XCTAssertEqual(exp, act, NestKey ?? "", file: file, line: line)
  }

  static func makeParts(_ p: PartsTuple) -> ScriptParts {
    ScriptParts(p.file, swift: p.swift, module: p.mod, nest: p.nest)
  }

}

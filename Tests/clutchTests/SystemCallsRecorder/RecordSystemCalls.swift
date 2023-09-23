import Foundation
import clutchLib

import struct Script.FilePath
import protocol clutchLib.SystemCalls

/// Record calls and results passed to SystemCalls delegate.
///
/// - Calls are enumerated.
/// - Each call has a recorder (to index and capture call records).
/// - Each recorder has a factory to wrap the call context and a renderer to convert it to String.
/// - Tests validate either the captured context or the String rendering.
///
/// The types involved:
/// - Enumerated calls (SCF): ``SystemCallsFunc``
/// - given: RSC=RecordingSystemCalls, SC=SystemCalls
/// - Then for callOp in SC functions [environment, printErr, ...] per SCF:
///      - SCRec.callOp is the call record type
/// - MakeRecordOfSystemCall.callOp creates SCRec.callOp
/// - RenderSystemCallRecord.callOp renders SCRec.callOp to String
/// - RSC has 1 IndexedRecorder of SCRec.callOp
/// - RSC proxies callOp to delegate.callOp, recording record with indexed recorder
///
/// Limitations:
/// - Tests should not depend on index order in the new-script scenario because
///   it has async operations to update the package and write the new file.
///
class RecordSystemCalls {
  typealias Record = Call.Record
  typealias SC = SystemCalls
  typealias SCType = SystemCallsType
  typealias Make = MakeRecordOfSystemCall
  typealias Render = RenderSystemCallRecord
  typealias RecordIndex = Int
  typealias IndexFuncCall = (
    index: RecordIndex, funct: SystemCallsFunc, call: String
  )

  public private(set) var renders = [IndexFuncCall]()

  static func recorder<T>(
    _ funct: SystemCallsFunc,
    _ render: @escaping (T) -> String
  ) -> IndexedRecorder<RecordIndex, SystemCallsFunc, T> {
    IndexedRecorder<RecordIndex, SystemCallsFunc, T>(funct, render)
  }

  let createDirRecorder = recorder(.createDir, Render.createDir)
  let environmentRecorder = recorder(.environment, Render.environment)
  let fileStatusRecorder = recorder(.fileStatus, Render.fileStatus)
  let findExecutableRecorder = recorder(.findExecutable, Render.findExecutable)
  let lastModifiedRecorder = recorder(.lastModified, Render.lastModified)
  let nowRecorder = recorder(.now, Render.now)
  let printErrRecorder = recorder(.printErr, Render.printErr)
  let printOutRecorder = recorder(.printOut, Render.printOut)
  let readFileRecorder = recorder(.readFile, Render.readFile)
  let runProcessRecorder = recorder(.runProcess, Render.runProcess)
  let writeFileRecorder = recorder(.writeFile, Render.writeFile)

  let delegate: SystemCalls
  var count: Count

  init(delegate: SystemCalls, counter: Count) {
    self.delegate = delegate
    self.count = counter
  }
}

// MARK: print data
extension RecordSystemCalls {
  public func renderLines(home: String? = nil, date: Bool = false) -> [String] {
    let result = renders.map { (index, funct, str) in
      "\(index)\t\(funct.name)\t\(str)"
    }

    guard nil == home && !date else {
      return result
    }
    return result.map { Self.normalizeHomeDate($0, home: home, date: date) }
  }
  /// Towards making rendered output comparable across runs.
  static func normalizeHomeDate(
    _ callData: String,
    home: String? = nil,
    date: Bool = true
  ) -> String {
    var result = callData
    if let home = home, !home.isEmpty, let range = result.range(of: home) {
      result.replaceSubrange(range, with: "HOME")
    }
    if date, let range = result.range(of: "Date(") {
      let after = range.upperBound..<result.endIndex
      if let end = result.range(of: ")", range: after) {
        let replace = range.upperBound..<end.lowerBound
        result.replaceSubrange(replace, with: "DATE")
      }
    }
    return result
  }
}

// MARK: SystemCalls conformance
extension RecordSystemCalls: SystemCalls {
  func createDir(_ path: String) throws {
    try wrapThrowing(
      path,
      f: delegate.createDir,
      makeRecord: Make.createDir,
      recorder: createDirRecorder
    )
  }

  func environment(_ keys: Set<String>) -> [String: String] {
    wrap(
      keys,
      f: delegate.environment,
      makeRecord: Make.environment,
      recorder: environmentRecorder
    )
  }

  func fileStatus(_ path: String) -> Bool? {
    wrap(
      path,
      f: delegate.fileStatus,
      makeRecord: Make.fileStatus,
      recorder: fileStatusRecorder
    )
  }

  func findExecutable(named: String) async throws -> String {
    try await wrapThrowingAsync(
      named,
      f: delegate.findExecutable,
      makeRecord: Make.findExecutable,
      recorder: findExecutableRecorder
    )
  }

  func lastModified(_ path: String) -> LastModified? {
    wrap(
      path,
      f: delegate.lastModified,
      makeRecord: Make.lastModified,
      recorder: lastModifiedRecorder
    )
  }

  func now() -> clutchLib.LastModified {
    wrap(
      (),
      f: delegate.now,
      makeRecord: Make.now,
      recorder: nowRecorder
    )
  }

  func printErr(_ message: String) {
    wrap(
      message,
      f: delegate.printErr,
      makeRecord: Make.printErr,
      recorder: printErrRecorder
    )
  }

  func printOut(_ message: String) {
    wrap(
      message,
      f: delegate.printOut,
      makeRecord: Make.printOut,
      recorder: printOutRecorder
    )
  }

  func readFile(_ path: String) async throws -> String {
    try await wrapThrowingAsync(
      path,
      f: delegate.readFile,
      makeRecord: Make.readFile,
      recorder: readFileRecorder
    )
  }

  func runProcess(_ path: String, args: [String]) async throws {
    try await wrapThrowingAsync(
      (path, args),
      f: delegate.runProcess,
      makeRecord: Make.runProcess,
      recorder: runProcessRecorder
    )
  }

  func writeFile(path: String, content: String) async throws {
    try await wrapThrowingAsync(
      (path, content),
      f: delegate.writeFile,
      makeRecord: Make.writeFile,
      recorder: writeFileRecorder
    )
  }
}

// MARK: wrapping used by SystemCalls implementations
extension RecordSystemCalls {
  func wrap<P, R>(
    _ p: P,
    f: (P) -> R,
    makeRecord: (P, R?) -> Call.Record<SC, P, R>,
    recorder: IndexedRecorder<
      RecordIndex, SystemCallsFunc, Call.Record<SC, P, R>
    >
  ) -> R {
    let result = f(p)
    recording(p: p, r: result, makeRecord, recorder)
    return result
  }

  func wrapThrowing<P, R>(
    _ p: P,
    f: (P) throws -> R,
    makeRecord: (P, R?) -> Call.Record<SC, P, R>,
    recorder: IndexedRecorder<
      RecordIndex, SystemCallsFunc, Call.Record<SC, P, R>
    >
  ) throws -> R {
    do {
      let result = try f(p)
      recording(p: p, r: result, makeRecord, recorder)
      return result
    } catch {
      recording(p: p, r: nil, makeRecord, recorder)
      throw error
    }
  }
  func wrapThrowingAsync<P, R>(
    _ p: P,
    f: (P) async throws -> R,
    makeRecord: (P, R?) -> Call.Record<SC, P, R>,
    recorder: IndexedRecorder<
      RecordIndex, SystemCallsFunc, Call.Record<SC, P, R>
    >
  ) async throws -> R {
    do {
      let result = try await f(p)
      recording(p: p, r: result, makeRecord, recorder)
      return result
    } catch {
      recording(p: p, r: nil, makeRecord, recorder)
      throw error
    }
  }
  func recording<P, R>(
    p: P,
    r: R?,
    _ makeRecord: (P, R?) -> Call.Record<SC, P, R>,
    _ recorder: IndexedRecorder<
      RecordIndex, SystemCallsFunc, Call.Record<SC, P, R>
    >
  ) {
    let record = makeRecord(p, r)
    let index = count.nextInc()
    let s = recorder.render(record)
    renders.append((index, recorder.tag, s))
    recorder.record(index, record)
  }
}

/// Render ``Call/Record`` for ``SystemCalls``
/// status: demoing for readability - optimize actual for comparability
enum RenderSystemCallRecord {
  typealias SC = clutchLib.SystemCalls
  typealias SCRec = SystemCallsType
  typealias Record = Call.Record
  typealias Frame = Call.Frame
  typealias Def = Call.Def
  typealias Spec = SystemCallsFunc

  // ----------------------------------- SystemCalls Record -> String
  static func createDir(_ record: SCRec.createDir) -> String {
    SH.strParm(record.def, record.frame.parms)
  }

  static func environment(_ record: SCRec.environment) -> String {
    let (def, frame) = (record.def, record.frame)
    let p = "\(def.parmNames[0])=\(frame.parms)"
    var result = "n/a"
    if let r = frame.result {
      result = "\(r)"
    }
    return "\(record.def.name)(\(p)) -> \(result)"
  }

  static func fileStatus(_ record: SCRec.fileStatus) -> String {
    let call = SH.strParm(record.def, record.frame.parms)
    let frame = record.frame
    let type = Spec.fileStatus.resultTypeName
    let result = SH.result(type, frame.result) {  // ' -> '...
      nil == $0 ? "(nil)" : "\($0!)"
    }
    return "\(call)\(result)"
  }
  static func findExecutable(_ record: SCRec.findExecutable) -> String {
    let call = SH.strParm(record.def, record.frame.parms)
    let frame = record.frame
    let type = Spec.findExecutable.resultTypeName
    let result = SH.result(type, frame.result) { "\"\($0)\"" }
    return "\(call)\(result)"
  }

  static func lastModified(
    _ record: SCRec.lastModified
  ) -> String {
    let call = SH.strParm(record.def, record.frame.parms)
    let type = Spec.lastModified.resultTypeName
    let result = SH.resultOpt(type, record.frame.result) { "Date(\($0.value))" }
    return "\(call)\(result)"
  }

  static func now(_ record: SCRec.now) -> String {
    let call = "\(record.def.name)()"
    let frame = record.frame
    let type = Spec.now.resultTypeName
    let result = SH.result(type, frame.result) { "Date(\($0.value))" }
    return "\(call)\(result)"
  }

  static func printErr(_ record: SCRec.printErr) -> String {
    SH.strParm(record.def, record.frame.parms)
  }

  static func printOut(_ record: SCRec.printOut) -> String {
    SH.strParm(record.def, record.frame.parms)
  }

  static func readFile(_ record: SCRec.readFile) -> String {
    let call = SH.strParm(record.def, record.frame.parms)
    let frame = record.frame
    let type = Spec.readFile.resultTypeName
    let result = SH.result(type, frame.result) { "\"\($0)\"" }
    return "\(call)\(result)"
  }

  static func writeFile(_ record: SCRec.writeFile) -> String {
    let def = record.def
    let path = record.frame.parms.0
    let content = record.frame.parms.1
    var call = "\(def.name)"
    call += "(\(def.parmNames[0]): \(SH.q(path))"
    call += ", \(def.parmNames[1]): \(SH.q(content))"
    call += ")"
    return call
  }

  static func runProcess(_ record: SCRec.runProcess) -> String {
    let def = record.def
    let execPath = record.frame.parms.0
    let args = record.frame.parms.1
    var call = "\(def.name)"
    call += "(\(def.parmNames[0]): \(SH.q(execPath))"
    call += ", \(def.parmNames[1]): \(SH.qq(args))"
    call += ")"
    return call
  }

  // ----------------------------------- helpers
  typealias SH = StrHelp
  enum StrHelp {
    static func strParm<T>(_ def: Def<T>, _ value: String) -> String {
      "\(def.name)(\(def.parmNames[0]): \(SH.q(value)))"
    }
    static func join(_ delim: String, _ args: [String]) -> String {
      args.joined(separator: delim)
    }

    static func path(_ value: FilePath) -> String {
      value.lastComponent?.string ?? "n/a"
    }

    static func q(_ value: String) -> String {
      "\"\(value)\""
    }
    static func qq(_ values: [String]) -> String {
      "[\(values.map {q($0)}.joined(separator: ", "))]"
    }

    static func result<T>(
      _ type: String,
      _ result: T?,
      _ render: (T) -> String
    ) -> String {
      var suffix = " -> "
      if let holder = result {
        suffix += "\(render(holder))"
      } else {
        suffix += "\(type) [thrown]"
      }
      return suffix
    }

    static func resultOpt<T>(
      _ type: String,
      _ result: (T?)?,
      _ render: (T) -> String
    ) -> String {
      var suffix = " -> "
      if let holder = result {
        if let realResult = holder {
          suffix += "\(render(realResult))"
        } else {
          suffix += "\(type) [nil]"
        }
      } else {
        suffix += "\(type) [thrown]"
      }
      return suffix
    }
  }
}
/// Produce ``Call/Record`` of ``SystemCalls``
enum MakeRecordOfSystemCall {
  typealias SC = clutchLib.SystemCalls
  typealias Record = Call.Record
  typealias Frame = Call.Frame
  typealias Def = Call.Def
  typealias SCRec = SystemCallsType

  static func createDir(
    _ path: String,
    _ result: Void?
  ) -> SCRec.createDir {
    record(.createDir, .frame(path))
  }

  static func environment(
    _ keys: Set<String>,
    _ result: [String: String]?
  ) -> SCRec.environment {
    record(.environment, .frame(keys, returning: result))
  }

  static func fileStatus(
    _ path: String,
    _ result: (Bool?)?
  ) -> SCRec.fileStatus {
    record(.fileStatus, .frame(path, returning: result))
  }

  static func findExecutable(
    _ path: String,
    _ result: String?
  ) -> SCRec.findExecutable {
    record(.findExecutable, .frame(path, returning: result))
  }

  static func lastModified(
    _ path: String,
    _ result: LastModified??
  ) -> SCRec.lastModified {
    record(.lastModified, .frame(path, returning: result))
  }

  static func now(
    _ none: Void,
    _ result: LastModified?
  ) -> SCRec.now {
    record(.lastModified, .frame((), returning: result))
  }

  static func printErr(
    _ message: String,
    _ result: Void?
  ) -> SCRec.printErr {
    record(.printErr, .frame(message))
  }

  static func printOut(
    _ message: String,
    _ result: Void?
  ) -> SCRec.printOut {
    record(.printOut, .frame(message))
  }

  static func readFile(
    _ path: String,
    _ result: String?
  ) -> SCRec.readFile {
    record(.readFile, .frame(path, returning: result))
  }

  static func runProcess(
    _ pathArgs: (String, [String]),
    _ result: Void?
  ) -> SCRec.runProcess {
    record(.runProcess, .frame(pathArgs, returning: result))
  }

  static func writeFile(
    _ pathContent: (String, String),
    _ result: Void?
  ) -> SCRec.writeFile {
    record(.writeFile, .frame(pathContent, returning: result))
  }

  private static func record<Parm, Result>(
    _ f: SystemCallsFunc,
    _ frame: Frame<Parm, Result>
  ) -> Record<SC, Parm, Result> {
    Record(def: f.def, frame: frame)
  }
}

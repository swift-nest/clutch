import clutchLib
import struct MinSys.FilePath

/// Record calls and results passed to SystemCalls delegate.
///
/// - Calls are enumerated.
/// - Each call has a recorder (to index and capture call records).
/// - Each recorder has a factory to wrap the call context and a renderer to convert it to String.
/// - Tests validate either the captured context or the String rendering.
///
/// The types involved:
/// - Target API: ``SystemCalls``
/// - Each call has enumerated tag: ``SystemCallsFunc``
/// - Each call has parameters P and result R, so closure signature is `(P) -> R` (modulo throws)
/// - Each call has a renderer to reduce P and R to String for recording (to avoid saving/copying context)
/// - To wrap each call: run the closure, record the result or error thrown, and return/throw
/// - Each record is indexed and saved after the call completes, normally or otherwise
///
/// Limitations:
/// - Async API's mean the call index/order can vary in tests
final class RecordSystemCalls {
  typealias Record = Call.Record
  typealias SC = SystemCalls
  typealias SCType = SystemCallsType
  typealias Make = MakeRecordOfSystemCall
  typealias Render = RenderSystemCallRecord
  typealias RecordIndex = Int

  let records = ActorArray<CallRecord>()

  static func recorder<T>(
    _ funct: SystemCallsFunc,
    _ render: @escaping @Sendable (T) -> String
  ) -> TagRender<SystemCallsFunc, T> {
    .init(tag: funct, renderer: render)
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
  let index: AtomicIndex
  let first: Int

  init(delegate: SystemCalls, index: AtomicIndex = .init(next: 100)) {
    self.delegate = delegate
    self.index = index
    self.first = index.peekNext()
  }

  public nonisolated func indexFirstNext() -> (first: Int, next: Int) {
    (first, index.peekNext())
  }
  public struct TagRender<Tag, T>: Sendable where Tag: Sendable {
    public typealias Renderer = @Sendable (T) -> String
    public let tag: Tag
    let renderer: Renderer

    public func render(_ item: T) -> String {
      renderer(item)
    }
    public func copy() -> [(String, String, String)] { [] }  // TODO P0 REMOVE
  }
}

extension RecordSystemCalls {
  public struct CallRecord: Sendable {
    let index: RecordIndex
    let funct: SystemCallsFunc
    let call: String
    init(_ index: RecordIndex, _ f: SystemCallsFunc, _ call: String) {
      self.index = index
      self.funct = f
      self.call = call
    }

    /// Tab-delimited fields, optionally stripping HOME or date to compare output across runs.
    public func tabbed(
      home: String? = nil,
      date: Bool = true
    ) -> String {
      Self.normalize("\(index)\t\(funct.name)\t\(call)", home: home, date: date)
    }

    public static func normalize(
      _ input: String,
      home: String? = nil,
      date: Bool = true
    ) -> String {
      guard date || !(home?.isEmpty ?? true) else {
        return input
      }
      var result = input
      if let home, !home.isEmpty, let range = result.range(of: home) {
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
}

// MARK: SystemCalls conformance
extension RecordSystemCalls: @unchecked Sendable {}
//extension RecordSystemCalls: SystemCallsSendable {}
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
    recorder: TagRender<
      SystemCallsFunc, Call.Record<SC, P, R>
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
    recorder: TagRender<
      SystemCallsFunc, Call.Record<SC, P, R>
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
    recorder: TagRender<
      SystemCallsFunc, Call.Record<SC, P, R>
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

  /// URK: uses detached Task
  func recording<P, R>(
    p: P,
    r: R?,
    _ makeRecord: (P, R?) -> Call.Record<SC, P, R>,
    _ recorder: TagRender<
      SystemCallsFunc, Call.Record<SC, P, R>
    >
  ) {
    let recording = recordingPrep(p: p, r: r, makeRecord, recorder)
    let copyRecords = records
    Task {
      await copyRecords.append(recording)
    }
  }

  func recordingAsync<P, R>(
    p: P,
    r: R?,
    _ makeRecord: (P, R?) -> Call.Record<SC, P, R>,
    _ recorder: TagRender<
      SystemCallsFunc, Call.Record<SC, P, R>
    >
  ) async {
    let recording = recordingPrep(p: p, r: r, makeRecord, recorder)
    await records.append(recording)
  }

  /// common recording steps
  private func recordingPrep<P, R>(
    p: P,
    r: R?,
    _ makeRecord: (P, R?) -> Call.Record<SC, P, R>,
    _ recorder: TagRender<
      SystemCallsFunc, Call.Record<SC, P, R>
    >
  ) -> CallRecord {
    let record = makeRecord(p, r)
    let index = index.next()
    let s = recorder.render(record)
    return CallRecord(index, recorder.tag, s)
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
  // TODO: @Sendable only required before tools-6.0 (s6:transition)
  @Sendable  // s6:Transition
  static func createDir(_ record: SCRec.createDir) -> String {
    SH.strParm(record.def, record.frame.parms)
  }

  @Sendable  // s6:Transition
  static func environment(_ record: SCRec.environment) -> String {
    let (def, frame) = (record.def, record.frame)
    let p = "\(def.parmNames[0])=\(frame.parms)"
    var result = "n/a"
    if let r = frame.result {
      result = "\(r)"
    }
    return "\(record.def.name)(\(p)) -> \(result)"
  }

  @Sendable  // s6:Transition
  static func fileStatus(_ record: SCRec.fileStatus) -> String {
    let call = SH.strParm(record.def, record.frame.parms)
    let frame = record.frame
    let type = Spec.fileStatus.resultTypeName
    let result = SH.result(type, frame.result) {  // ' -> '...
      nil == $0 ? "(nil)" : "\($0!)"
    }
    return "\(call)\(result)"
  }

  @Sendable  // s6:Transition
  static func findExecutable(_ record: SCRec.findExecutable) -> String {
    let call = SH.strParm(record.def, record.frame.parms)
    let frame = record.frame
    let type = Spec.findExecutable.resultTypeName
    let result = SH.result(type, frame.result) { "\"\($0)\"" }
    return "\(call)\(result)"
  }

  @Sendable  // s6:Transition
  static func lastModified(
    _ record: SCRec.lastModified
  ) -> String {
    let call = SH.strParm(record.def, record.frame.parms)
    let type = Spec.lastModified.resultTypeName
    let result = SH.resultOpt(type, record.frame.result) { "Date(\($0.value))" }
    return "\(call)\(result)"
  }

  @Sendable  // s6:Transition
  static func now(_ record: SCRec.now) -> String {
    let call = "\(record.def.name)()"
    let frame = record.frame
    let type = Spec.now.resultTypeName
    let result = SH.result(type, frame.result) { "Date(\($0.value))" }
    return "\(call)\(result)"
  }

  @Sendable  // s6:Transition
  static func printErr(_ record: SCRec.printErr) -> String {
    SH.strParm(record.def, record.frame.parms)
  }

  @Sendable  // s6:Transition
  static func printOut(_ record: SCRec.printOut) -> String {
    SH.strParm(record.def, record.frame.parms)
  }

  @Sendable  // s6:Transition
  static func readFile(_ record: SCRec.readFile) -> String {
    let call = SH.strParm(record.def, record.frame.parms)
    let frame = record.frame
    let type = Spec.readFile.resultTypeName
    let result = SH.result(type, frame.result) { "\"\($0)\"" }
    return "\(call)\(result)"
  }

  @Sendable  // s6:Transition
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

  @Sendable  // s6:Transition
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
    record(.createDir, .frame(path, returning: result))
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
    _ = none
    return record(.lastModified, .frame((), returning: result))
  }

  static func printErr(
    _ message: String,
    _ result: Void?
  ) -> SCRec.printErr {
    record(.printErr, .frame(message, returning: result))
  }

  static func printOut(
    _ message: String,
    _ result: Void?
  ) -> SCRec.printOut {
    record(.printOut, .frame(message, returning: result))
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

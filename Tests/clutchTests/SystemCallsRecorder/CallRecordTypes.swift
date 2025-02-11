import clutchLib

import struct SystemPackage.FilePath

public protocol SystemCallsSendable: SystemCalls, Sendable {}

/// SystemCall call-record type aliases
///
/// Using lowercase to distinction per-function call record types
enum SystemCallsType {
  typealias SC = clutchLib.SystemCalls
  typealias Record = Call.Record
  typealias SCRec = SystemCallsFunc

  typealias environment = Record<SC, Set<String>, [String: String]>
  typealias lastModified = Record<SC, String, LastModified?>
  typealias fileStatus = Record<SC, String, Bool?>
  typealias now = Record<SC, Void, LastModified>
  typealias printErr = Record<SC, String, Void>
  typealias printOut = Record<SC, String, Void>
  typealias createDir = Record<SC, String, Void>
  typealias runProcess = Record<SC, (String, [String]), Void>
  typealias readFile = Record<SC, String, String>
  typealias writeFile = Record<SC, (String, String), Void>
  typealias findExecutable = Record<SC, String, String>
}

public enum SystemCallsFunc: String, Sendable {
  typealias SC = clutchLib.SystemCalls
  case environment, lastModified, fileStatus, now
  case printErr, printOut, createDir
  case runProcess
  case readFile, writeFile
  case findExecutable
  var name: String { rawValue }
  var def: Call.Def<SC> {
    Call.Def(SC.self, self.rawValue, parms: parmNames, results: resultNames)
  }
  var parmNames: [String] {
    switch self {
    case .environment: return ["keys"]
    case .lastModified: return ["path"]
    case .fileStatus: return ["path"]
    case .now: return []
    case .printErr: return ["message"]
    case .printOut: return ["message"]
    case .createDir: return ["path"]
    case .runProcess: return ["path", "args"]
    case .readFile: return ["path"]
    case .writeFile: return ["path", "content"]
    case .findExecutable: return ["name"]
    }
  }
  var resultNames: [String] {
    switch self {
    case .environment:
      return ["keyValues"]
    case .lastModified:
      return ["lastModifiedDate"]
    case .fileStatus:
      return ["isDir?"]
    case .now:
      return ["currentDate"]
    case .findExecutable:
      return ["path"]
    default:
      return Call.voidResult
    }
  }
  var resultTypeName: String {
    switch self {
    case .environment:
      return "[String:String]"
    case .lastModified:
      return "LastModified"
    case .fileStatus:
      return "Bool?"
    case .now:
      return "LastModified"
    case .findExecutable:
      return "String"
    default:
      return ""  // avoid Void as too verbose?
    }
  }

}

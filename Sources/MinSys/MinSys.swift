
#if useSwiftSystem
public typealias FilePath = SystemPackage.FilePath
public import struct SystemPackage.FilePath
#elseif canImport(System)
public typealias FilePath = System.FilePath
public import struct System.FilePath
#elseif canImport(SystemPackage) // Linux
public typealias FilePath = SystemPackage.FilePath
public import struct SystemPackage.FilePath
#else
#error("Unable to find FilePath library (from swift-system, et al")
#endif

// low-level access to model stderr
#if canImport(Darwin)
@preconcurrency import Darwin
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(WASI)
@preconcurrency import WASI
#elseif canImport(Musl)
@preconcurrency import Musl
#else
#warning("no stderr")
#endif

#if os(Linux)
@preconcurrency import Foundation
#if swift(<6.0)
import FoundationNetworking
#endif
#else
// Date, FileManager, ProcessInfo, URL; contains, fputs, range
import Foundation
#endif

public enum MinStdio {
    public static func printOut(_ m: String, eol: String = "\n") {
        Swift.print(m, terminator: eol)
    }
    public static func printErr(_ m: String, eol: String = "\n") {
        let message = "\(m)\(eol)"
#if canImport(Darwin)
        fputs(message, stderr)
#elseif canImport(Glibc)
        fputs(message, stderr)
#elseif canImport(WASI)
        let bytes = Array(m.utf8)
        var count = 0
        _ = fd_write(2, bytes, bytes.count, &count)
#elseif canImport(Musl)
        fputs(message, stderr)
#else
        printOut(m, eol: eol)
#endif
    }
    public static func newFileUrl(_ path: String) -> URL? {
#if swift(>=6.0) || os(macOS)
        return URL(filePath: path)
#else
        let scheme = "file://"
        let filePath = path.hasPrefix(scheme) ? path : "\(scheme)\(path)"
        return URL(string: filePath)
#endif
    }
}

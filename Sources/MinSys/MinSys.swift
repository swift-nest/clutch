
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

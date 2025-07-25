
#if useSwiftSystem
public typealias FilePath = SystemPackage.FilePath
public import struct SystemPackage.FilePath
#else
public typealias FilePath = System.FilePath
public import struct System.FilePath
#endif

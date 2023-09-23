//#!/usr/bin/env clutch

import Nest
import Foundation
import Script

@main struct Main: Script {
  func run() async throws {
    report()
    print("Replay each input line to output")
    print("Enter lines, stop with Ctrl-C")
    try await cat(to: Output.standardOutput)
  }

  func report()  {
    print("# minime")
    print("-        date: \(CommonTime.now)")
    print("-       #file: \(#file)")
    print("-   #filePath: \(#filePath)")
    print("- binary path: \(Bundle.main.executablePath ?? "n/a")")
    print("- bundle path: \(Bundle.main.bundlePath)")
    print("- bundle  url: \(Bundle.main.bundleURL)")
  }
}

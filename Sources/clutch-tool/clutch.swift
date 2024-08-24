import Foundation
import clutchLib

@main public struct Main {
  public static func main() async {
    let args = ProcessInfo.processInfo.arguments
    await ClutchDriver.main(args: Array(args[1...]))
  }
}

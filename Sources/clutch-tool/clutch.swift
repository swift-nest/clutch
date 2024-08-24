import clutchLib
import Foundation

@main public struct Main {
  public static func main() {
    let args = ProcessInfo.processInfo.arguments
    ClutchDriver.main(args: args)
  }
}

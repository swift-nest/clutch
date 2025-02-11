import clutchLib

@main public struct Main {
  public static func main() async {
    let args = CommandLine.arguments
    await ClutchDriver.main(args: Array(args[1...]))
  }
}

import clutchLib

@main
public enum Main {
  public static func main() async {
    let args = CommandLine.arguments
    await ClutchDriver.main(args: Array(args[1...]))
  }
}

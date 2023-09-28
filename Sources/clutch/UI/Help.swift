public enum Help {
  static let name = "clutch"
  static let VERSION = "0.5.0"
  static let LABEL =
    "# \(name) # Run Swift scripts using a common nest package library"
  static let SYNTAX =
    """
      #!/usr/bin/env clutch         # First line of script, if clutch on PATH
      \(name) <scriptfile> <arg>...  # create/build/run script from peer in nest
                                    # filename: name{.ignore}*{.nest}{.swift}
      \(name) <name{.nest}> <arg>... # run peer in nest (from any directory)
      \(name) path-<name{.nest}>     # get path to peer source file
      \(name) cat-<name{.nest}>      # emit source code for peer (as template)
      \(name) peers-<nest>           # list peers in nest
      \(name) dir-<nest>             # emit nest package directory path
    """
  public static let HELP =
    """
    \(LABEL)
      from https://github.com/swift-nest/clutch \(VERSION)

    \(SYNTAX)

    \(DESCRIPTION)
    """
  static let DESCRIPTION =
    """
    Given a Swift script, clutch will create, build, and run a peer in a nest.

    The nest is a Swift package directory with executable script products.
    A peer product declaration and module source are added for each new script.

    ## Script

    - The peer name is the initial filename segment (before `.`).
        - The nest name is any trailing segment (ignoring .swift), or `Nest`.
        - Both the nest and peer name must be valid ASCII identifiers.
    - The file is executable and has a valid hash-bang on the first line:
        - `#!/path/to/clutch`
        - `#!/usr/bin/env clutch` (best, if clutch is on your PATH)
    - The script has valid top-level code, depending only on the nest library.

    The nest peer `{nest}/Sources/{peer}` will be created on first impression.
    The peer filename is `main.swift`, or `{peer}.swift` if it contains `@main`.

    `Package.swift` will be updated with peer product and target declarations:
    - `.executable(name: "{peer}", targets: [ "{peer}" ]),`
    - `.executableTarget(name: "{peer}", dependencies: ["{nest}"]),`

    ## Building script peer in the nest

    By default clutch builds using `-c debug --quiet` (to avoid delay and noise),
    the nest package is named `Nest`, and it lives at `$HOME/git/Nest`.

    To configure the nest location or output, set environment variables:
    - `NEST_NAME`: to find the nest in `$HOME/{relative-path}/{nest-name}`
    - `NEST_HOME_RPATH`: relative path from HOME (defaults to `git`)
    - `NEST_PATH`: full path to nest package directory (ignores other variables)
    - `NEST_LOG`: any value to log steps to standard error
    - `NEST_BUILD`: `@..` for `@`-delimited args, or `release`, `loud`, `verbose`

    The nest directory name must be the name of the library module.

    """
  static let GUIDE =
    """
    e.g.,

    ```
    #!/usr/bin/env clutch
    print("Hi!")
    ```

    or, if the nest project depends on the Swift Argument Parser:

    ```
    #!/usr/bin/env clutch
    import ArgumentParser

    @main struct Main: ParsableCommand {
      @Argument var args: [String] = []
      func run() async throws {
          print("Hello \\(args.first ?? "World")!")
       }
    }
    ```

    Below is a sample nest Package.swift (with no dependencies and 1 demo):

    ```
    import PackageDescription

    let package = Package(
      name: "Nest",
      products: [
        .executable(name: "demo", targets: [ "demo" ]),
        .library(name: "Nest", targets: ["Nest"]),
      ],
      targets: [
        .executableTarget(name: "demo", dependencies: ["Nest"]),
        .target(name: "Nest"),
      ]
    )
    ```

    """
}

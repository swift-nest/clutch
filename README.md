# clutch 🪺 run Swift scripts from a nest of dependencies

Swift scripting is easier using `clutch` to build and launch scripts when
- scripts have dependencies, or
- you want common code in a library, or
- you want scattered scripts checked into a common local package, or
- scripts build & run faster because common code is pre-built in the nest package

For each script, `clutch` makes a matching "peer" executable in a local "nest" package:
- A "nest" host is a Swift package with a library of the same name (e.g., in `HOME/git/Build`). 
- Clutch maintains a "peer" copy of the script in its own executable target module in the nest package.
- The script is an executable file anywhere
    - with `#!/usr/bin/env clutch` on the first line (if clutch is on the PATH).
- The script filename is `name.{Nest}.swift` 
    - (or see below for other ways to specify the nest)
- When the script is run, `clutch` creates and/or builds the peer executable as needed:
    - `Build/Package.swift` is updated with an executable product `name` when the script is first run.
    - Peer `Build/Sources/name/main.swift` (or `name.swift`) is created or updated to match the script file.
    - The executable depends on the nest library module (`Build`) 
        - The library module can depend on others, e.g.,  
          [Swift Argument Parser](https://github.com/apple/swift-argument-parser) 
          or [Shwift](https://github.com/GeorgeLyon/Shwift).
- When everything is up-to-date, clutch runs the executable with any arguments.

`clutch` can also run peers by name (from anywhere) and manage peers in the nest.

## Quickstart

Tested on macOS 12+ and Linux (Ubuntu LTS/latest)

Assuming `~/git`, PATH has `~/bin` along with `swift` and `git`
(and you're ok with [Sources/clutch](Sources/clutch) 
and [nests/simple/Nest](nests/simple/Nest))...

```
# Build clutch and install to `~/bin` on `PATH` (for `/usr/bin/env`)
git clone https://github.com/swift-clutch/clutch.git
cd clutch && swift build 
cp .build/debug/clutch ~/bin

# Create a sample nest package
cp -rf nests/simple/Nest ~/git/Nest
  # or: mkdir ~/git/Nest && cd "$_" && swift package init --type library

# Create a hello script (anywhere)
cat > hello <<EOF
#!/usr/bin/env clutch

let name = CommandLine.arguments[1...].first ?? "World"
print("Hello \(name)")
EOF

chmod +x hello 
./hello friend    # builds, runs `~/git/Nest/Sources/hello/main.swift`

# Use clutch directly to run or manage peers or nests
clutch hello      # run by name from anywhere (use `hello.{Nest}` if not default)

clutch cat-hello  # output peer source (`clutch cat-hello > hi.swift`)
clutch path-hello # echo peer path (`vi "$(clutch path-hello)"`)
clutch peers-Nest # list peers known in nest `Nest`
clutch dir-Nest   # emit location of nest `Nest`
```

## Usage
Install clutch, create a nest package, and write a Swift script file anywhere.

When you invoke the script, clutch runs it after ensuring its nest package peer
(`~/git/Nest/Sources/peer/peer.swift`) is created, updated, and/or built.  A nest
package has a nest library (with the nest name) for common code and dependencies.

<details><summary>

### Write `name.{Nest.}swift`: use `#!/usr/bin/env clutch` when `clutch` is on the PATH

</summary>

- The peer name is the initial filename segment (before `.`).
    - The nest name is any trailing segment (ignoring .swift)
        - If there is no trailing segment, clutch uses the default nest `Nest`.
    - Both the nest and peer name must be valid ASCII identifiers.
- The file is executable.
- The hash-bang on the first line depends on where you install clutch:
    - `#!/usr/bin/env clutch` (best, if clutch is on your PATH)
    - `#!/path/to/clutch`  (when clutch is installed but not on the PATH)
- The script file has valid top-level code, depending only on the nest library.

The nest peer in `{nest}/Sources/{peer}` will be created on first impression.
The peer filename is `main.swift`, or `{peer}.swift` if it contains `@main`.

`Package.swift` will be updated with peer product and target declarations:
- `.executable(name: "{peer}", targets: [ "{peer}" ]),`
- `.executableTarget(name: "{peer}", dependencies: ["{nest}"]),` 

</details>

<details><summary>

### The nest package, e.g., `$HOME/git/{nest}/Package.swift`
The package contains at least the nest library and
an executable target for each associated script.

```
// in Package.swift (e.g., as created by `swift package --init`)

products: [
  // peer product created for each script, using the script name {peer}
  .executable(name: "{peer}", targets: [ "{peer}" ]),
  .library(name: "{nest}", targets: ["{nest}"]),
],
targets: [
  // peer executable created for each script
  .executableTarget(name: "{peer}", dependencies: ["{nest}"]),
  .target(
    name: "{nest}",
    dependencies: [ ... ] 
``` 
</summary>

The nest directory name must be the name of the library module.

For sample nest packages, see [nests](nests) or use 
`swift package init --type library`.

#### Configuration
By default clutch builds using `-c debug --quiet` (to avoid delay and noise),
the nest package is named `Nest`, and it lives at `$HOME/git/Nest`. 

You can configure the nest location, output, or build flags.

Configuration is rarely needed (mostly just `CLUTCH_NEST_RELPATH`
to change the git parent directly).

To configure, set environment variables:
- `CLUTCH_NEST_NAME`: find nest in `$HOME/{relative-path}/{nest-name}`
- `CLUTCH_NEST_RELPATH`: relative path from HOME (defaults to `git`)
- `CLUTCH_NEST_BASE`: find nest in `$CLUTCH_NEST_BASE/{nest-name}` instead
- `CLUTCH_NEST_PATH`: full path to nest directory (ignoring other variables)
- `CLUTCH_LOG`: any value to log clutch build steps to standard error
- `CLUTCH_BUILD`: `@{arg0}@{arg1}..`, or `{release} {loud | verbose}`
    - The special values `release`, `loud`, and `verbose` produce appropriate build flags.
    - Arbitrary `@`-delimited args are passed through to swift build command.

</details>

<details><summary>

### Using clutch directly to run and manage peers
```
clutch name{.Nest}             # Run peer by name
clutch [peers|path]-Nest       # Emit Nest peers or location
clutch [cat|path]-name{.Nest}  # Emit peer code or location
```

</summary>

Use clutch directly to run scripts by filename or peer name
```
clutch name.swift      # Create/build/run `name` from default nest
clutch name            # Run by name
```

Use clutch to list peers in a nest and find or copy the peer source file:
```
clutch peers-Data      # List peers in the `Data` nest
clutch path-name       # Echo path to source file for peer `name`
clutch cat-init.Data   # Output code from peer `init` in Data nest
```
</details>


<details><summary>

### Limitations (under development)
- `@main` and `Package.swift` operations can fail when declarations don't follow expected format.
- `swift build` keeps the old executable when script edits produce no binary changes, resulting in harmless but unnecessary no-op builds.
- Script exit codes are converted to 1.
- For known bugs and missing features, see [README-clutch](README-clutch.md).

</summary>

- The `@main` detection is simplistic for new scripts (and not done for updates).
- The `Package.swift` editing for new scripts is also a simple scan.
    - It seeks `products: ` and `  targets:` (the latter with 2 leading spaces)
        - `target:` is common; please avoid 2 spaces before it. 
        - And please avoid that text in comments or other declarations. 
    - To avoid missed/invalid insertions, tag the line before the declaration:
      with `CLUTCH_PRODUCT` or `CLUTCH_TARGET`
- Users have to manually edit the package to rename/delete peers or fix errors.
    - To delete, remove `Sources/peer` and two lines for peer in `Package.swift`
- Builds are based only on last-modified time.
    - Swift does not re-link the binary after edits result in the same code
      (so a second clutch run would trigger another no-op build).
- Output streams and exit codes mix clutch, swift build, and executables.
    - A failed exit code will always be 1 (even if the script exits with 2).

</details>

## Package Status
- Tested on macOS/Linux, but unproven in the wild...
    - [![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fswift-nest%2Fclutch%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/swift-nest/clutch)
    - [![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fswift-nest%2Fclutch%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/swift-nest/clutch)
- Command set, CLI interface, configuration, and error-handling could change.

## Alternatives and related libraries
- [clatch](Sources/clatch/clatch.swift) is clutch done quick.
    - It just builds and run scripts, without hooks for porting or testing.
    - No nest-management commands, no environment configuration, no error or SystemCalls wrapper
- The `swift` command works fine if no libraries are needed.
    - Use `#!/usr/bin/env swift` at the start of a script file to run directly
    - `swift script.swift` does the same, without the `#!` hash-bang line
    - `swift -e 'statement{; statement}'` runs a snippet of code
    - Or `generateCode | swift -` to run code from the input stream
- [swift-sh](https://github.com/mxcl/swift-sh) builds and runs using libraries from import comments
- Try [Swift Argument Parser](https://github.com/apple/swift-argument-parser) to simplify writing CLI's
- Try [Shwift](https://github.com/GeorgeLyon/Shwift) for async cross-platform scripting
- To install Swift package command-line tools, consider [Mint](https://github.com/yonaskolb/Mint)
    - `mint install swift-nest/clutch`

## Development
- Please [create an issue](https://github.com/swift-nest/clutch/issues) with any feedback, to help get to 1.0 :)
- See [README-clutch](README-clutch.md) for known issues
- License: [Apache 2.0](LICENSE.txt)
- Copyright Contributors on their contribution date.  All rights reserved.
- Apologies for the cutesy nomenclature...

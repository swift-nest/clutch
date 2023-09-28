# clutch 🪺 run Swift scripts from a nest of dependencies
- Put `#!/usr/bin/env clutch` on the first line of `tool.swift`.
- When `tool.swift` is run, clutch creates and builds a peer as needed in a nest.
- `tool` can depend on libraries in the nest, 
  like [Swift Argument Parser](https://github.com/apple/swift-argument-parser) 
  or [Shwift](https://github.com/GeorgeLyon/Shwift).

Swift scripting is easier with clutch when 
- scripts have dependencies, or
- you want common code in a nest library, or
- you want scattered scripts checked into a common package, or
- scripts build & run faster because most code is pre-built in the nest package

## Quickstart

Tested on macOS 12+ and Linux (Ubuntu LTS/latest)

Assuming `~/git`, PATH has `~/bin` along with `swift` and `git`
(and you're ok with [Sources/clutch](Sources/clutch) 
and [nests/simple/Nest](nests/simple/Nest))...

```
# Build clutch and put on PATH (for `env`)
git clone https://github.com/swift-clutch/clutch.git
cd clutch && swift build 
cp .build/debug/clutch ~/bin

# Try it with a sample nest package
cp -rf nests/simple/Nest ~/git/Nest

cat > hello <<EOF
#!/usr/bin/env clutch

print("Hello")
EOF

chmod +x hello 
./hello          # builds, runs `~/git/Nest/Sources/hello/main.swift`

# Use clutch directly to run or manage peers or nests
clutch hello      # run by name from anywhere
clutch hello.Nest # specify nest if not the default

clutch cat-hello  # output peer source (`clutch cat-start > newscript.swift`)
clutch path-hello # echo peer path (`vi "$(clutch path-hello)"`)
clutch peers-Nest # list peers known in nest `Nest`
clutch dir-Nest   # emit location of nest `Nest`
```

## Usage
Install clutch, create a nest package, and write a Swift script file anywhere.

When you invoke the script, clutch runs it after ensuring its nest package peer
(`Nest/Sources/peer/peer.swift`) is created, updated, and/or built.  A nest
package has a nest target (with the nest name) for common code and dependencies.


<details><summary>

### Write script: `#!/usr/bin/env clutch`

</summary>

- The peer name is the initial filename segment (before `.`).
    - The nest name is any trailing segment (ignoring .swift), or `Nest`.
    - Both the nest and peer name must be valid ASCII identifiers.
- The file is executable and has a valid hash-bang on the first line:
    - `#!/path/to/clutch`
    - `#!/usr/bin/env clutch` (best, if clutch is on your PATH)
- The script has valid top-level code, depending only on the nest library.

The nest peer in `{nest}/Sources/{peer}` will be created on first impression.
The peer filename is `main.swift`, or `{peer}.swift` if it contains `@main`.

`Package.swift` will be updated with peer product and target declarations:
- `.executable(name: "{peer}", targets: [ "{peer}" ]),`
- `.executableTarget(name: "{peer}", dependencies: ["{nest}"]),` 

</details>

<details><summary>

### Build in nest: `$HOME/git/{nest}/Package.swift`
```
  products: [
    .executable(name: "peer", targets: [ "peer" ]), // for each peer
    .library(name: "{nest}", targets: ["{nest}"]),
  ],
  targets: [
    .executableTarget(name: "peer", dependencies: ["{nest}"]), // for each peer
    .target(
      name: "{nest}",
      dependencies: [ ... ] 
``` 
</summary>

By default clutch builds using `-c debug --quiet` (to avoid delay and noise),
the nest package is named `Nest`, and it lives at `$HOME/git/Nest`. 

To configure the nest location or output, set environment variables:
- `CLUTCH_NEST_NAME`: find nest in `$HOME/{relative-path}/{nest-name}`
- `CLUTCH_NEST_RELPATH`: relative path from HOME (defaults to `git`)
- `CLUTCH_NEST_BASE`: find nest in `$CLUTCH_NEST_BASE/{nest-name}` instead
- `CLUTCH_NEST_PATH`: full path to nest directory (ignoring other variables)
- `CLUTCH_LOG`: any value to log steps to stdout
- `CLUTCH_BUILD`: `@{arg0}@{arg1}..`, or `{release} {loud | verbose}`

The nest directory name must be the name of the library module.

For sample nest packages, see [nests](nests).

</details>

<details><summary>

### Using clutch directly to run and manage peers
```
clutch name{.Nest}             # run peer by name
clutch [peers|path]-Nest       # Nest peers or location
clutch [cat|path]-name{.Nest}  # Peer code or location
```

</summary>

Use clutch directly to run scripts by filename or peer name
```
clutch name.swift      # Build and run name from default nest (even if new)
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
- `@main` and `Package.swift` operations can be brittle.
- `swift build` keeps the old executable when updates produce no binary changes.
- For known bugs and missing features, see [README-clutch](README-clutch.md).

</summary>

- The `@main` detection is simplistic for new scripts (and not done for updates).
- The `Package.swift` editing for new scripts is also a simple scan.
    - It seeks `products: ` and `  targets:` (the latter with 2 leading spaces)
        - `target:` is common; please avoid 2 spaces before it. 
        - And please avoid that text in comments or other declarations. 
    - To avoid missed/invalid insertions, tag the line before the declaration:
      with `CLUTCH_PRODUCT` or `CLUTCH_TARGET`
- Builds are based only on last-modified time.
    - Swift does not re-link the binary after edits result in the same code
      (so a second clutch run would trigger another no-op build).
- Output streams and exit codes mix clutch, swift build, and executables.
- Users have to manually move or remove the peer to rename or delete.
    - Remove `Sources/peer` and two lines for peer in the nest `Package.swift`

</details>

## Package Status
- Tested, but unproven in the wild...
    - Not tested yet on different variants of `Package.swift`
- Command set, CLI interface, and configuration could change

## Alternatives and related libraries
- The `swift` command works fine if no libraries are needed.
    - Use `#!/usr/bin/env swift` at the start of a script file to run directly
    - `swift script.swift` does the same, without the `#!` hash-bang line
    - `swift -e 'statement{; statement}'` runs a snippet of code
    - Or `generateCode | swift -` to run code from the input stream
- [swift-sh](https://github.com/mxcl/swift-sh) builds and runs using libraries from import comments
- Try [Swift Argument Parser](https://github.com/apple/swift-argument-parser) to simplify writing CLI's
- Try [Shwift](https://github.com/GeorgeLyon/Shwift) for async cross-platform scripting

## Development
- License: Apache 2.0
- Please [create an issue](https://github.com/swift-nest/clutch/issues) with any feedback, to help get to 1.0 :)
- See [README-clutch](README-clutch.md)


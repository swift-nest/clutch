# Clutch development

## UI issues
- Current {command}-{target} forms are awkward and idiosyncratic, but
- Unclear how to model in ArgParser: first argument as script, name, or command
    - and async weirdness integrating with Script?
- Global config
    - Prefer config file? (yuck: want to avoid file-read to run-script?)

<details>
<summary>

## Testing

</summary>

### Platforms
- tested mostly on macOS 13+
- CI tests macOS 12 & Ubuntu Linux 22.04 with Swift 5.9 and 5.7
    - Need to test in 5.5 if targeting (arg parser async had an older API)
- Re-verify that package declarations are compatible back to 5.5

### Automated testing status
- Some configuration
- Integration testing using hand-rolled mock for SystemCalls

### Manual testing variants
- Only current macOS tested
- See main [Scenarios](Tests/clutchTests/Scenarios/ClutchCommandScenario.swift)
- See [ClutchMainTests](Tests/clutchTests/ClutchMainTests.swift) for manual integration driver

#### Nest configuration
- tracing: env [none, CLUTCH_LOG]
- nest finding:
    - NEST_PATH: dominates 
    - name: from input, `NEST_NAME`, or 'Nest'
    - base: `NEST_BASE`, `HOME/REL_PATH` or `HOME/git`
    - nest names that are not identifiers should be rejected

#### Script
- name: 0, 1, n extensions
- invalid module names: spaces, non-ascii
- lifecycle: new, update
- main type: top-level or @main (limitation: only on new)
- verify library dependency
    - new script manifest declarations should track nest library name
- build: release or debug

#### Brittle
- `// some @main comment` in a top-level main
- main style changing from top-level to `@main` on edit
- Non-compliant Package.swift
- Error messages not clear or suited for users
- Test relative paths
- Polish documentation

#### Modes
- all errors to stderr

</details>

<details>
<summary>

## Planning

</summary>

### Bugs the user has to work around
- Touch binary if rebuilt, but same (handle risk of false-positive build) 
- `fatal error` added to build failures - by Script gacking?
- handle build code=!0 errors nicely - currently shwift throwing
    - goal is to pass the same code back, no?

#### Organize user messages 
- [ErrParts](Sources/clutch/ClutchDriverErrors.swift) needs UI work
    - agent: clutch, swift-build, etc
    - subject: usually missing resource or bad input or env var
    - problem: bug to fix
    - fixHint: need to support more hints
- tracing is minimal, just build and run

### Missing user features
- P2 CI+badging for reliability signal
- P2 caution mode (or just upgrade?)
    - detect unexpected duplicates (peer much larger than script from new source)
    - check peer-declaration == source-presence
    - report when peer found in multiple Nest (esp. if using env variable)
    - main goal is to avoid losing any changes
- P3 sysCall tracing for FFDC (below)
    - record calls, then replay on exception when --verbose-clutch
- P3 init-name{.Nest}: cat-name plus capture, chmod?
- P3 SCM - automatically check in each version of a script?
- P3 Persistent config +/- environment
    - Read configuration from `$HOME/.clutch` (or `$XDG_CONFIG_HOME`)
    - Update code to load configuration defaults at build-time
- P3 Deploy?: scatter scripts, audit scatter, report status, and build/deploy all
    - based on tracking source of peer
- P4 Guide: more needed for junior developers to get started?
- P4 Support generating and running scripts by reading input stream
    - If script file does not exist and there is standard input
    - then pipe stdin to the script file before starting
    - e.g., `someGenScript | clutch newScriptName --help`:
        - create local file `newScriptName`
        - build to nest as usual
        - run as usual (here to test --help arguments)

#### P3 first-failure data capture
- goal-1 is for unknowing users to solve issue on first record of error
- Capture clutch and SystemCalls messages, report details on error
- using RecordSystemCalls from tests
- goal-2 limited control over feedback
    - sensor: output channel
    - sensitivity: (quiet, record, and loud)
    - but default should be most helpful in most cases
- related: segregating output channels for clutch, build, and executable

### Features avoided, mainly for simplicity and disutility
- monitoring executions? No, want the tool to build and invoke, not be big brother
- build trigger based on diffs
- more indirection or control over naming
- ? reading config.  Happy path should be 2 file+date-checks & invocation

</details>

<details>
<summary>

## Development

</summary>

## Development
### Missing dev features
- version (command, help string; update as part of tagging)
- git practices/policies

### Code issues
- remove run-peer command - runs without prefix

### ArgParser (AP) variant failing - solve or reject
- Unclear how AP can model the first arg as a script, name, or command
- Investigate whether Schwift wrapping is interfering:
- not running async run()'s if not AsyncParsableCommand
- but top-level command must be AsyncParsable
- but ClutchAP extends Script to get Shell support
- ArgParser happy when ClutchAP extends AsyncParsable
- but Shell gacks b/c not running the magic underloaded run() async


#### Libraries: shwift seems to get it right for Linux et al
- Using System, NIO
- Avoiding Foundation
- Avoiding [tools support core](https://github.com/apple/swift-tools-support-core) as deprecated though from Apple
    - but see testing InMemoryFileSystem?
- archive TBD: Apple Data has compression API's, but no zip option?
    - https://www.hackingwithswift.com/example-code/system/how-to-compress-and-decompress-data
    - https://github.com/ZipArchive/ZipArchive
    - https://forums.swift.org/t/task-safe-way-to-write-a-file-asynchronously/54639

</details>

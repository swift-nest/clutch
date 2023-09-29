# Clutch development

## UI issues
- Error messages are rough
- Current {command}-{target} forms are awkward and idiosyncratic, but
- ArgParser support is DRAFT only: untested, UI rough, poorly factored
    - [ClutchAP/ClutchMain](Sources/ClutchAP/ClutchMain.swift)
- Use global config file instead of or in addition to environment variables?
    - urk: shouldn't need to read file to just run the script binary

<details>
<summary>

## Testing
- Tested on macOS and Linux
- Covers all scenarios and most errors
</summary>

### Platforms
- tested mostly on macOS 13+
- CI tests macOS 12 & Ubuntu Linux 22.04 with Swift 5.9 and 5.7
    - Need to test in 5.5 if targeting (arg parser async had an older API)
- Re-verify that package declarations are compatible back to 5.5

### Automated testing status
- Some configuration
- Integration testing using hand-rolled mock for [SystemCalls](Sources/clutch/system/SystemCalls.swift)
    - [DriverTests.swift](Tests/clutchTests/DriverTests.swift)
    - mock SystemCalls: [KnownSystemCalls](Tests/clutchTests/Fixtures/KnownSystemCalls.swift)
    - with [Recorder](Tests/clutchTests/SystemCallsRecorder/RecordSystemCalls.swift)

### Manual testing variants
- Only current macOS tested
- See main [Scenarios](Tests/clutchTests/Scenarios/ClutchCommandScenario.swift)
- See [ClutchMainTests](Tests/clutchTests/ClutchMainTests.swift) for manual integration driver

#### Nest configuration and clutch modes
- tracing: env [none, CLUTCH_LOG]
- nest finding:
    - NEST_PATH: dominates 
    - name: from input, `NEST_NAME`, or 'Nest'
    - base: `NEST_BASE`, `HOME/REL_PATH` or `HOME/git`
    - nest names that are not identifiers should be rejected
- `CLUTCH_LOG` defined or not
- `CLUTCH_BUILD` undefined, `@`-delimited, or ~release +/- loud, verbose

#### Script
- path: absolute or relative (env converts to absolute)
- name: 1, 2, 3+ segments
- invalid module names: non-alphanumeric, non-ascii
- main type: top-level or @main (limitation: only on new)
- build: release or debug
- currency: new, up-to-date, bin-stale, peer-stale
- validity: ok, or compile or run failure
- verify library dependency
    - new script manifest declarations should track nest library name

#### Commands
- see readme demo

</details>

<details>
<summary>

## Planning
- Try to avoid current user workaround's?
- Improve error feedback
    - Capture SystemCalls for super-verbose mode of failure feedback?
</summary>

### Bugs the user has to work around
- Touch binary if rebuilt, but same (handle risk of false-positive build) 

#### New script is brittle
- top-level code with misleading `// @main comment`
    - workaround: rename peer.swift to main.swift
- main style changing between top-level and `@main` on edit
    - workaround: rename manually
- Non-compliant Package.swift
    - workaround: integrate manually

#### Error feedback and codes
- tracing is minimal, just build and run
- workaround's: TBD
- Error messages not clear or suited for users
- `fatal error` added to build failures - by Script gacking?
- handle build code=!0 errors nicely - currently shwift throwing
    - goal is to pass the same code back, no?
- [ErrParts](Sources/clutch/ClutchDriverErrors.swift) needs UI work
    - agent: clutch, swift-build, etc
    - subject: usually missing resource or bad input or env var
    - problem: bug to fix
    - fixHint: need to support more hints

### Missing user features
- P2 CI+badging for reliability signal
- P2 caution mode (or just upgrade?)
    - detect unexpected duplicates (peer much larger than script from new source)
    - check peer-declaration == source-presence
    - report when peer found in multiple Nest (esp. if using env variable)
    - main goal is to avoid losing any changes
- P3 logging integration? esp. to segregate clutch from tool, and to monitor
- P3 exec script executable (test platform variants, streams, exit codes, etc.)
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
- Copyright headers - not required but conventional...

</summary>

## Development
### Missing dev features
- urk: copyright headers
- version (command, help string; update as part of tagging)
- git practices/policies

</details>

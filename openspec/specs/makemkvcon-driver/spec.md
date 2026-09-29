# makemkvcon driver

## Purpose

The `MakeMKV` library runs `makemkvcon` in robot mode for three operations: list the drives, scan
a source, and rip a title from that scan. It holds the two facts that make direct use of
`makemkvcon` fragile: a title index means something only with the source and settings of the scan
that produced it, and track selection is a machine preference unless a profile says otherwise. This
spec covers locating the executable, the arguments each operation passes, how each result is read
and when it is refused. The profile itself is the `track-selection` spec's; the long-lived engine
is the `engine-session` spec's.

Documentation: [README](../../../README.md) ("Use").

## Requirements

### Requirement: The executable is found in the app bundle, then on PATH
`MakeMKV.locate(defaultLocations:environment:)` SHALL search the default locations in order, then
`makemkvcon` in each directory of the environment's `PATH` in order, and SHALL return the first
whose path the file manager reports as executable, which a directory named `makemkvcon` with its
execute bit set also satisfies. When none is, it SHALL throw `executableNotFound` listing every place
searched, in search order. The default location SHALL be MakeMKV's application bundle under
`/Applications`. `MakeMKV()` SHALL be `MakeMKV(executable:)` with the located executable.

#### Scenario: nothing found
- **WHEN** `locate` is called with one default location and a `PATH` of one directory, neither holding an executable `makemkvcon`
- **THEN** it throws `executableNotFound` whose searched list is the default location and then that directory's `makemkvcon`

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`locateReportsWhereItLooked`).

### Requirement: A source becomes MakeMKV's source argument
`Source.argument` SHALL be `disc:<index>` for a MakeMKV drive index, `dev:<name>` for an operating
system device, `iso:<path>` for an image file and `file:<path>` for a folder holding a disc tree.

#### Scenario: each kind of source
- **WHEN** the arguments of drive 0, device `/dev/rdisk5`, image `/tmp/a.iso` and folder `/tmp/backup` are read
- **THEN** they are `disc:0`, `dev:/dev/rdisk5`, `iso:/tmp/a.iso` and `file:/tmp/backup`

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`sourceArguments`).

### Requirement: Scan settings become switches in a fixed order
`ScanSettings.arguments` SHALL be, in this order and each only when set: `--minlength=<seconds>`,
`--cache=<megabytes>`, `--directio=<true|false>`, `--noscan`, and then the additional arguments
verbatim. Default settings SHALL produce no switches.

#### Scenario: every setting
- **WHEN** settings with minimum length 0, cache 1024, direct I/O on, no-scan on and the additional argument `--debug` are read
- **THEN** the arguments are `--minlength=0`, `--cache=1024`, `--directio=true`, `--noscan`, `--debug`

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`scanSettingsArgumentsInFixedOrder`).

### Requirement: Every run is robot mode with messages and progress on one stream
Each operation SHALL run the executable with `-r`, `--messages=-stdout` and `--progress=-same`,
then the settings' switches, then the command. Standard output and standard error SHALL be read as
one stream, parsed with `RobotLineParser` as lines arrive, and each parsed line SHALL be passed to
the caller's line handler, when there is one, as it arrives and kept for the result. A non-zero exit
status SHALL throw `processFailed` with the status and the messages printed, except where an
operation tolerates it.

#### Scenario: a scan's messages while the disc is read
- **WHEN** a scan is started with a line handler
- **THEN** the handler receives each line while the process runs, and the same lines are in the result's log

Pinned by: nothing yet.

### Requirement: The drive list comes from asking about a disc that cannot exist
`drives()` SHALL run `info disc:9999` with a one-megabyte cache, tolerate its non-zero exit, and
return the drive table the run printed, one entry per slot MakeMKV knows.

#### Scenario: listing drives
- **WHEN** `drives()` is called
- **THEN** it returns the parsed `DRV` lines of that run and does not throw for the run's non-zero exit

Pinned by: nothing yet.

### Requirement: A scan that reached no disc is refused
`scan(_:settings:onLine:)` SHALL run `info <source>` with the settings, and SHALL throw
`discUnavailable` with the run's messages when the result has no disc, or carries the
no-usable-drives (`MessageCode.noUsableDrives`, 5042) or failed-to-open-disc
(`MessageCode.failedToOpenDisc`, 5010) message. Otherwise it SHALL return a `Scan` holding the
source, the settings and the parsed run.

#### Scenario: no drive
- **WHEN** a scan's run prints the no-usable-drives and failed-to-open messages and `TCOUNT:0`
- **THEN** `scan` throws `discUnavailable`, although the parsed run has a disc with no titles

Pinned by: nothing yet.

### Requirement: A scan exposes its disc whichever path made it
`Scan.disc` SHALL be the disc an engine session supplied when the scan was made from one, and the
robot run's disc otherwise; a scan made from an engine disc SHALL carry an empty robot run.
`Scan.titles` SHALL be the disc's titles, empty when there is no disc, and `title(index:)` the
title with that MakeMKV index.

#### Scenario: a scan made from an engine disc
- **WHEN** a scan is made from an engine-supplied disc with two titles
- **THEN** its `disc` is that disc, its titles are indices 0 and 1, and `title(index: 1)` is the second

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`engineMadeScanExposesItsTitles`).

### Requirement: A rip accepts only a title its scan listed, with a name to find it by
`rip(_:from:to:profile:onLine:progress:)` SHALL throw `titleNotInScan` with the title's index when
the title is not equal, as a whole value, to one of the scan's titles, and `titleHasNoOutputName`
when it has no output file name, both before any process runs or any folder is created.

#### Scenario: a title from another scan
- **WHEN** a title with the same index as the scan's only title but a different playlist is ripped from that scan
- **THEN** `rip` throws `titleNotInScan(index: 0)`

#### Scenario: a title with no output name
- **WHEN** the scan's only title has no output file name and is ripped
- **THEN** `rip` throws `titleHasNoOutputName(index: 0)`

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`ripRefusesATitleFromAnotherScan`, `ripRefusesATitleWithNoOutputName`).

### Requirement: A rip reuses the scan's source and settings and passes its profile as a file
A rip SHALL create the destination folder, then run `mkv <source> <title index> <destination>` with
the scan's source and settings unchanged. With a profile, it SHALL write the profile to a fresh
temporary file, append `--profile=<path>` to the settings' switches for this run, and remove the
file when the rip ends, whether or not it succeeded.

#### Scenario: a rip with a profile
- **WHEN** a title is ripped with a conversion profile
- **THEN** `makemkvcon` receives the scan's switches followed by `--profile=` and a temporary file's path, and that file no longer exists after `rip` returns or throws

Pinned by: nothing yet.

### Requirement: A rip's result is the file MakeMKV named
After the process exits cleanly, the rip SHALL look for the title's output file name inside the
destination, SHALL throw `outputMissing` with that URL and the run's messages when it is not there,
and otherwise SHALL return a `RipResult` holding its URL and the run's log, whose `messages` are the
log's message lines.

#### Scenario: MakeMKV exits cleanly without writing the file
- **WHEN** `makemkvcon mkv` exits with status zero and no file with the title's output name is in the destination
- **THEN** `rip` throws `outputMissing`

Pinned by: nothing yet.

### Requirement: Progress is reported once per progress value
When a progress handler is given, the rip SHALL call it once for each `PRGV` line, with that value
and the most recent `PRGC` and `PRGT` captions seen before it, `nil` for a caption not yet seen.

#### Scenario: a caption then a value
- **WHEN** a rip's output holds a current-operation caption followed by two progress values
- **THEN** the handler is called twice, each time with that caption as `current`

Pinned by: nothing yet.

### Requirement: Calls on one driver are not serialised
`MakeMKV` SHALL be an actor, but it SHALL NOT serialise its operations: each suspends while its
process runs, so a second call on the same instance starts its own `makemkvcon` while the first is
still running. The type's documentation and the README say calls run one after another because
MakeMKV tolerates one process per drive at a time; that claim is false, and is tracked as a defect
in https://github.com/project-smd/MakeMKVKit/issues/6.

#### Scenario: two scans at once
- **WHEN** two scans are started concurrently on one `MakeMKV` instance
- **THEN** two `makemkvcon` processes run at the same time

Pinned by: nothing yet.

# Disc scan

## Purpose

`DiscScan` is everything one `makemkvcon info` run said, sorted into the shape it describes: the
whole log in order, the drive table, the messages, the lines nothing could read, and the disc with
its titles and their tracks. This spec covers that assembly, the disc-level reads, and agreement
with TheDiscDb's own parse of the same logs. The typed reads of a title and a track are the
`titles-and-tracks` spec's.

Documentation: [README](../../../README.md) ("The format, as measured").

## Requirements

### Requirement: The log is kept whole and sorted by line type
`DiscScan(lines:)` SHALL keep every line in `lines` in order, and SHALL collect the drive lines in
`drives`, the message lines in `messages` and the unrecognised lines' text in `unrecognised`, each
in log order. Progress lines SHALL appear only in `lines`. `DiscScan(parsing:)` SHALL be
`DiscScan(lines:)` over `RobotLineParser.parse(_:)` of the text. `message(code:)` SHALL return the
first message with that code.

#### Scenario: a Blu-ray log from TheDiscDb
- **WHEN** a Blu-ray log with sixteen `DRV` lines, one for a present drive, to which TheDiscDb has appended eleven `HSH:` lines, is scanned
- **THEN** `unrecognised` holds exactly those eleven lines, `drives` holds the sixteen slots, and one of them is present

#### Scenario: duplicate playlists skipped
- **WHEN** a log in which MakeMKV skipped two playlists as equal to ones already listed is scanned
- **THEN** the messages with the duplicate-skipped code carry, as parameters, each skipped playlist and the playlist it equals, in log order

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`blurayFacts`).

### Requirement: Titles and tracks are grouped by index and sorted
The disc's titles SHALL be built from the `TINFO` and `SINFO` lines grouped by title index, sorted
by title index, each title's tracks grouped by stream index and sorted by it. A later attribute
with the same id on the same item SHALL replace an earlier one. `titleCount` SHALL be the value of
the last `TCOUNT` line, or the number of titles built when there is none.

#### Scenario: a Blu-ray with ten titles
- **WHEN** a Blu-ray log with `TCOUNT:10` and ten titles is scanned
- **THEN** the disc's `titleCount` is 10 and it holds ten titles

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`blurayFacts`, `dvdFacts`, `uhdIsReportedAsBluray`).

### Requirement: A disc exists whenever any disc-shaped line was seen
`disc` SHALL be non-nil exactly when the log holds a `TCOUNT`, `CINFO`, `TINFO` or `SINFO` line.
MakeMKV prints `TCOUNT:0` after failing to open a disc, so a run that found no usable drive and
failed to open a disc yields a disc with a title count of zero and no titles, not `nil`; the
messages are what tell the two apart. The type's own documentation says `disc` is `nil` when the
run never reached a disc, which is tracked as a defect in
https://github.com/project-smd/MakeMKVKit/issues/11.

#### Scenario: a run with no drive
- **WHEN** a log with the no-usable-drives message, one empty drive slot, the failed-to-open message and `TCOUNT:0` is scanned
- **THEN** both messages are found by code, and `disc` is non-nil with a title count of zero and no titles

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`emptyRunHasNoDisc`), whose name says the
opposite of what it asserts.

### Requirement: A log without disc lines has no disc
`disc` SHALL be `nil` when the log holds no `TCOUNT`, `CINFO`, `TINFO` or `SINFO` line.

#### Scenario: a log with no disc lines at all
- **WHEN** a log of only messages and drive lines is scanned
- **THEN** `disc` is `nil`

Pinned by: nothing yet.

### Requirement: The media type is read from the message code
`DiscInfo.mediaType` SHALL be `.dvd` when the disc's `type` attribute has message code 6206,
`.bluray` for 6209, `.other(code:)` with the code for any other code, and `.other(code: 0)` when
the disc has no `type` attribute. A UHD disc SHALL be reported as `.bluray`, since MakeMKV gives it
the Blu-ray code. The localised text of the attribute SHALL NOT be consulted.

#### Scenario: a DVD
- **WHEN** a DVD log is scanned
- **THEN** the disc's `mediaType` is `.dvd`

#### Scenario: a UHD disc
- **WHEN** a UHD log is scanned
- **THEN** the disc's `mediaType` is `.bluray`

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`blurayFacts`, `dvdFacts`, `uhdIsReportedAsBluray`).

### Requirement: The disc's typed reads come from its attributes
`DiscInfo.name`, `volumeName` and `metadataLanguageCode` SHALL be the values of the disc's `name`,
`volumeName` and `metadataLanguageCode` attributes, and `title(index:)` SHALL return the title
with that MakeMKV index, not the one at that position.

#### Scenario: a Blu-ray's names
- **WHEN** a Blu-ray log is scanned
- **THEN** the disc's `name` and `volumeName` are the values of its `CINFO` name and volume-name lines

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`blurayFacts`).

### Requirement: Every title agrees with TheDiscDb's record of it
For each title in TheDiscDb's record of a log, the scan SHALL have a title with that index whose
source identifier, segment map, duration text and size in bytes equal the record's, and each
recorded track SHALL exist with a kind that matches the recorded type, or whose type text equals
it when the record holds localised text. This SHALL hold for the vendored Blu-ray, DVD and UHD
fixtures in every run, and for the whole corpus when a clone is supplied.

#### Scenario: a vendored fixture
- **WHEN** a vendored log is scanned and compared with the JSON TheDiscDb derived from it
- **THEN** there are no disagreements

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`agreesWithTheDiscDb`), `Tests/MakeMKVRobotTests/CorpusTests.swift` (`everyLogAgreesWithItsRecord`).

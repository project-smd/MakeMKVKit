# Robot output parsing

## Purpose

`MakeMKVRobot` turns the output of `makemkvcon -r` into typed lines, from any source: a live
process, a saved log, TheDiscDb's data repository. MakeMKV documents the line types but not the
grammar, so the grammar here is the one measured against TheDiscDb's corpus. This spec covers the
logical-line grammar, how each line type is read, and what happens to a line that cannot be read.
How the lines are assembled into a disc is the `disc-scan` spec's.

Documentation: [README](../../../README.md) ("The format, as measured").

## Requirements

### Requirement: Fields are comma-separated and strings are quoted with backslash escapes
A line's payload, everything after the first colon, SHALL be split into fields at commas outside
double quotes. Quotes SHALL be removed from the field's value, and inside a quoted string a
backslash SHALL escape the next character, so `\"` is a quote and `\\` a backslash. A comma inside
quotes SHALL be part of the value.

#### Scenario: a comma inside a quoted value
- **WHEN** a `TINFO` line whose quoted value contains a comma is parsed
- **THEN** the attribute's value is the whole quoted text, comma included

#### Scenario: escaped quotes in a message
- **WHEN** a `MSG` line whose text and format contain `\"` is parsed
- **THEN** the message's text and format contain plain quote characters

Pinned by: `Tests/MakeMKVRobotTests/RobotLineParserTests.swift` (`titleAttributeKeepsCommaInsideQuotes`, `messageResolvesEscapedQuotesAndParameters`).

### Requirement: A quoted string may continue across physical lines
`RobotLineParser.feed(_:)` SHALL join a physical line to the ones after it, with a newline between
them, until every quote is closed and the line does not end in an unconsumed backslash, returning
`nil` while the logical line is incomplete and the parsed line when it completes. Only a line that
begins with a known prefix — `MSG`, `PRGC`, `PRGT`, `PRGV`, `DRV`, `TCOUNT`, `CINFO`, `TINFO` or
`SINFO` before its first colon — SHALL start a logical line that may continue; any other line SHALL
be returned at once as `.unrecognised` with its text, so a damaged line with an odd number of
quotes that does not start with a known prefix costs itself and nothing after it. A damaged line
that does start with one — a `MSG` cut off inside its quoted text — SHALL keep absorbing the lines
after it until its quotes happen to balance or input ends, and they come back together as one
`.unrecognised`; this is tracked as a defect in
https://github.com/project-smd/MakeMKVKit/issues/10.

#### Scenario: a message holding two line breaks
- **WHEN** a `MSG` line whose quoted text ends each physical line with a backslash is fed over five physical lines
- **THEN** the first four feeds return `nil` and the fifth returns one message whose text contains both line breaks

#### Scenario: a known-prefix line cut off inside a quote
- **WHEN** a document of a `MSG` line whose last quoted field is never closed, followed by a `TCOUNT` line and a `CINFO` line, is parsed
- **THEN** all three physical lines come back as a single `.unrecognised`

#### Scenario: a log that opens mid-message
- **WHEN** a document whose first two lines are the tail of a message, with an unbalanced quote, is followed by a `TCOUNT` line
- **THEN** the first two lines are each `.unrecognised` and the `TCOUNT` line is read as a title count

Pinned by: `Tests/MakeMKVRobotTests/RobotLineParserTests.swift` (`quotedStringMayContinueAcrossLines`, `damagedLineDoesNotSwallowWhatFollows`).

### Requirement: Blank lines are skipped and a trailing open line is flushed
Outside a pending logical line, a physical line that is empty or all whitespace SHALL yield
nothing. `RobotLineParser.finish()` SHALL parse a pending incomplete logical line as best it can
and return it, and SHALL return `nil` when nothing is pending. `RobotLineParser.parse(_:)` SHALL
split a document at newlines, feed every physical line, and finish.

#### Scenario: blank input
- **WHEN** an empty line or a line of spaces is fed to a fresh parser
- **THEN** `feed` returns `nil`

#### Scenario: a document without a final newline
- **WHEN** a document of a `TCOUNT` line and a `CINFO` line with no newline after it is parsed
- **THEN** both lines are returned

Pinned by: `Tests/MakeMKVRobotTests/RobotLineParserTests.swift` (`unknownPrefixAndBlankLines`, `parseDocumentFlushesTrailingLine`).

### Requirement: Each line type is read by its field count
The parser SHALL read `MSG` as code, flags, parameter count, text, format and exactly that many
parameters; `PRGC` and `PRGT` as exactly code, id and name; `PRGV` as exactly three integers,
current, total and maximum; `DRV` as index, state, enabled, media flags, drive name and disc name,
with a device path when there is a seventh field and an empty one when there are six, the state as
a `DriveState` and the media flags as a `MediaFlags` of the raw integers; `TCOUNT` as
one integer; `CINFO`, `TINFO` and `SINFO` as an attribute — id, message code and value — preceded
by nothing, the title index, or the title and stream indices respectively. `DriveState` names the
`AP_DriveState*` values (`inserted` is 2, `noDrive` 256) and `MediaFlags` the `AP_DskFsFlag*` bits
(`blurayFiles` 4, `aacsFiles` 8); a drive's `isPresent` SHALL be `state != .noDrive` and `hasDisc`
SHALL be `state == .inserted`.

#### Scenario: a stream attribute
- **WHEN** `SINFO:0,1,1,6202,"Audio"` is parsed
- **THEN** it is a stream attribute of title 0, stream 1, with id `type`, message code 6202 and value `Audio`

#### Scenario: a drive line
- **WHEN** a `DRV` line with state 2, media flags 12 and a device path is parsed
- **THEN** the drive has state `inserted`, media `[.blurayFiles, .aacsFiles]` and that device path, and `hasDisc` is true

#### Scenario: an empty drive slot
- **WHEN** a `DRV` line with state 256 and empty strings is parsed
- **THEN** the drive's state is `noDrive` and `isPresent` is false

#### Scenario: progress lines
- **WHEN** `PRGV:100,200,65536` is parsed
- **THEN** it is a progress value with current 100, total 200 and maximum 65536

Pinned by: `Tests/MakeMKVRobotTests/RobotLineParserTests.swift` (`messageResolvesEscapedQuotesAndParameters`, `driveLineDecodesStateAndMediaFlags`, `emptyDriveSlot`, `streamAttributeCarriesMessageCode`, `discAttributeTitleCountAndProgress`).

### Requirement: A line that does not fit is kept verbatim, never half-read
A logical line with an unknown prefix, no colon, the wrong number of fields for its type, a
non-integer where an integer is required, or a `MSG` whose parameters do not number its declared
count SHALL be returned as `.unrecognised` with the whole logical line, rather than dropped or
turned into a partly filled value. The exception is `finish()`, which parses a logical line left
open at end of input as it stands, so an unclosed quoted value is read up to the end of input.

#### Scenario: a TheDiscDb hash line
- **WHEN** an `HSH:` line is parsed
- **THEN** it is `.unrecognised` with the line's text

#### Scenario: an unclosed value at end of input
- **WHEN** a document ends with a `TINFO` line whose quoted value is never closed
- **THEN** it is read as a title attribute whose value runs to the end of input

#### Scenario: a message missing a parameter
- **WHEN** a `MSG` line declaring two parameters and carrying one is parsed
- **THEN** it is `.unrecognised` with the line's text

Pinned by: `Tests/MakeMKVRobotTests/RobotLineParserTests.swift` (`unknownPrefixAndBlankLines`, `messageWithMismatchedParameterCountIsUnrecognised`).

### Requirement: Attribute ids mirror upstream and unknown ids survive
`AttributeID` SHALL accept any integer, SHALL name ids 0 through 50 as `AP_ItemAttributeId` in
makemkv-oss's `apdefs.h` names them without the `ap_ia` prefix, and SHALL give `nil` for `name`
on any other id. Its `description` SHALL be the name followed by the raw id in parentheses, or
`attribute(<id>)` for an unnamed id.

#### Scenario: an id this version does not know
- **WHEN** a `TINFO` line with attribute id 99 is parsed
- **THEN** the attribute's id has raw value 99 and `name` nil

#### Scenario: a known id
- **WHEN** `AttributeID.segmentsMap.description` is read
- **THEN** it is `SegmentsMap(26)`

Pinned by: `Tests/MakeMKVRobotTests/RobotLineParserTests.swift` (`unknownAttributeIDSurvives`).

### Requirement: Message flags and progress fractions are derived
`Message.isDebug`, `isHidden` and `isEvent` SHALL test flag bits 32, 64 and 128. A
`ProgressValue`'s `currentFraction` and `totalFraction` SHALL be `current` and `total` divided by
`maximum`, and `nil` when `maximum` is zero.

#### Scenario: a progress value with no maximum
- **WHEN** a progress value with maximum 0 is read
- **THEN** both fractions are `nil`

Pinned by: nothing yet.

### Requirement: The parser reads TheDiscDb's whole corpus
Every log in TheDiscDb's data repository that has a derived record beside it SHALL parse with no
unrecognised line other than TheDiscDb's own `HSH:` lines, except in logs damaged upstream, which
are listed by path with the reason. Logs saved as UTF-16 with a byte-order mark are read in that
encoding by the test.

#### Scenario: a corpus run
- **WHEN** the corpus test is run against a clone of TheDiscDb's data repository
- **THEN** more than a thousand logs are read and no line outside the allow-listed logs is unrecognised except `HSH:` lines

Pinned by: `Tests/MakeMKVRobotTests/CorpusTests.swift` (`everyLogAgreesWithItsRecord`).

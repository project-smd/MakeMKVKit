# Titles and tracks

## Purpose

A `Title` is one title MakeMKV listed and a `Track` one stream of it, each a bag of attributes
keyed by `AttributeID` with typed reads over it. This spec covers what those reads return, the
identity of a title that survives a change of scan settings, the structure MakeMKV encodes in
stream flags and adjacency (a lossless track's lossy core, a subtitle stream's forced-only
companion), and keeping a disc past the scan that produced it.

Documentation: [README](../../../README.md) ("The format, as measured").

## Requirements

### Requirement: Typed reads are the attribute's value, or its integer
The subscript of any attribute-bearing value SHALL return the attribute's value as text, and
`integer(_:)` SHALL return it parsed as an integer, `nil` when absent or not an integer. Each named
property of `Title` and `Track` SHALL be the read of the attribute of the same name, textual or
integer as its type says, where the attribute's upstream name differs: `durationText` reads
`duration`, `diskSizeText` `diskSize`, `sizeBytes` `diskSizeBytes`, `segmentCount` `segmentsCount`,
`segmentMap` `segmentsMap`, `languageCode` `langCode`, `languageName` `langName` and `bitrateText`
`bitrate`.

#### Scenario: a Blu-ray feature
- **WHEN** the first title of a Blu-ray log is read
- **THEN** its `sourceFileName`, `segmentMap`, `segmentCount`, `durationText`, `chapterCount`, `sizeBytes` and `outputFileName` are the values of its `TINFO` lines for those attributes, and its `originalTitleId` is `nil`

#### Scenario: an audio track
- **WHEN** a DTS audio track of that title is read
- **THEN** its `languageCode`, `codecId`, `audioChannelsCount`, `audioSampleRate`, `mkvFlags` and `audioChannelLayoutName` are the values of its `SINFO` lines for those attributes

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`blurayFacts`, `dvdFacts`).

### Requirement: A duration is parsed from its printed form
`Title.durationSeconds` SHALL parse `durationText` as one to three colon-separated integers read as
hours, minutes and seconds from the right, and SHALL be `nil` when a non-empty part is not an
integer or there are more than three. Empty parts SHALL be dropped before counting and signed
integers accepted, so `1::20` reads as 80 seconds and `-1:00` as −60. `Title.duration` SHALL be that
many seconds as a `Duration`.

#### Scenario: an hour and a quarter
- **WHEN** a title whose duration text is `1:15:20` is read
- **THEN** `durationSeconds` is 4520 and `duration` is 4520 seconds

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`blurayFacts`).

### Requirement: A title's source identifier is its playlist or its DVD title id
`Title.sourceIdentifier` SHALL be `sourceFileName` when the title has one and `originalTitleId`
otherwise, so a Blu-ray title is identified by its playlist or clip and a DVD title by its VTS
title number. With `segmentMap` and `durationText` it is the identity of a title that survives a
change of scan settings.

#### Scenario: a DVD title
- **WHEN** a title of a DVD log with original title id `03` and no source file name is read
- **THEN** its `sourceIdentifier` is `03`

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`dvdFacts`), `Tests/MakeMKVTests/MakeMKVTests.swift` (`engineMadeScanExposesItsTitles`).

### Requirement: A track's kind is read from the message code
`Track.kind` SHALL be `.video` when the track's `type` attribute has message code 6201, `.audio` for
6202, `.subtitles` for 6203 and `.unknown` otherwise, whatever the localised text says.
`videoTracks`, `audioTracks` and `subtitleTracks` of a title SHALL be its tracks of that kind in
order.

#### Scenario: the audio tracks of a Blu-ray feature
- **WHEN** the audio tracks of a Blu-ray feature with a DTS-HD MA track, its DTS core and a TrueHD track are listed
- **THEN** the first three have short codecs `DTS-HD MA`, `DTS` and `TrueHD`

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`blurayFacts`).

### Requirement: Stream flags mirror upstream bits
`Track.flags` SHALL be the track's `streamFlags` integer as `StreamFlags`, empty when absent, whose
members are the `AP_AVStreamFlag_*` bits of `apdefs.h`. `isDerived` SHALL test `derivedStream`,
`hasCore` `hasCoreAudio`, `isCore` `coreAudio`, and `isForcedOnly` SHALL be true when the track has
both `forcedSubtitles` and `derivedStream`.

#### Scenario: a lossless track and its core
- **WHEN** a DTS-HD MA track with stream flags 1024 and the track after it, with stream flags 2304, are read
- **THEN** the first's flags are exactly `hasCoreAudio` and it `hasCore`, and the second's are exactly `derivedStream` and `coreAudio`, and it `isDerived` and `isCore`

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`coreAndForcedTracksAreDerivedFromTheOneBefore`).

### Requirement: A derived track belongs to the primary track before it
MakeMKV lists a derived stream directly after the stream it came from, and adjacency is the only
link. `Title.derivedTracks(of:)` SHALL return the run of derived tracks immediately after the given
track, up to the next track that is not derived, and an empty list for a track not in the title.
`Title.parentTrack(of:)` SHALL return the nearest earlier track that is not derived, and `nil` for a
track that is not itself derived. `primaryTracks` SHALL be the tracks that are not derived.

#### Scenario: a lossy core
- **WHEN** a lossless track's derived tracks and its core's parent are asked for
- **THEN** the lossless track's derived tracks are its core alone, the core's parent is the lossless track, and the core has no derived tracks

#### Scenario: a forced-only subtitle stream
- **WHEN** the parent of a forced-only subtitle track is asked for
- **THEN** it is a subtitle track whose derived tracks include the forced-only one

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`coreAndForcedTracksAreDerivedFromTheOneBefore`).

### Requirement: A disc outlives its scan as JSON
`DiscInfo`, `Title`, `Track`, `Attribute` and `AttributeID` SHALL be `Codable`, with an attribute
dictionary encoded as a flat array alternating each key's raw id and its attribute, so a disc encoded and decoded compares equal, tracks and all, whatever
names a later version gives the ids.

#### Scenario: a Blu-ray disc through JSON
- **WHEN** the disc of a Blu-ray log is encoded with `JSONEncoder` and decoded with `JSONDecoder`
- **THEN** the decoded disc equals the original and its first title keeps its tracks

Pinned by: `Tests/MakeMKVRobotTests/FixtureTests.swift` (`discInfoRoundTripsThroughJSON`).

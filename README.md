# MakeMKVKit

A small Swift wrapper around `makemkvcon`, MakeMKV's command-line front end, covering what a ripping
tool needs: list the drives, scan a disc, rip a title from that scan. Nothing else.

Two libraries, so that the wire format can be used without a MakeMKV installation:

- `MakeMKVRobot` — parses robot-mode output (`makemkvcon -r`) from any source: a live process, a
  saved log, TheDiscDb's data repository. Pure Swift, no `Process`, no file system.
- `MakeMKV` — locates `makemkvcon`, runs `info` and `mkv`, and hands back typed results.

## Why a wrapper at all

MakeMKV has no library to link against. The GUI is a thin client of the same engine over the same
message set, so robot mode is the supported programmatic surface and the only one. The `libmmbd`
libraries in the application bundle go the other way: they lend MakeMKV's decryption to
libbluray-based players, and give nothing back about titles or muxing.

What a wrapper adds is a place to hold the two facts that make direct use of `makemkvcon` fragile:

- **Title indices are positional and depend on the scan settings.** `mkv` takes MakeMKV's title
  number, not a playlist name, and that number shifts with `--minlength` and with MakeMKV's own
  skipping of duplicate playlists. So `rip` takes a `Scan` and a `Title` from it, reuses the scan's
  source and settings, and refuses a title the scan did not list.
- **Track selection is a preference, not a given.** Without a profile, `makemkvcon` keeps whatever
  tracks the selection rule saved in this machine's MakeMKV preferences says, which is whatever the
  GUI last had. `rip` takes a `ConversionProfile` built from a `SelectionRule`, written in MakeMKV's
  own rule language, so the same call keeps the same tracks on any machine.

## Use

Three operations: list the drives, scan a source, rip a title from that scan.

```swift
import MakeMKV

let makeMKV = try MakeMKV()                       // finds makemkvcon in the app bundle or on PATH
let drives = try await makeMKV.drives().filter(\.hasDisc)
let scan = try await makeMKV.scan(.disc(0), settings: ScanSettings(minimumTitleLength: 0))

for title in scan.titles {
    print(title.index, title.sourceIdentifier ?? "", title.segmentMap ?? "", title.durationText ?? "")
}

let feature = scan.titles.max { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }!

// Every track except the lossy cores MakeMKV would otherwise add beside each lossless track.
let profile = ConversionProfile(selection: SelectionRule([
    .select(.attribute(.all)),
    .deselect(.attribute(.core)),
]))
let result = try await makeMKV.rip(feature, from: scan, to: URL(fileURLWithPath: "/Volumes/Rips"), profile: profile) { progress in
    print(progress.current?.name ?? "", progress.value.currentFraction ?? 0)
}
print(result.outputURL)
```

### Keeping the engine open

Every `makemkvcon` process re-reads the disc before it can do anything, so ripping several titles
through `mkv` costs a scan per title. `EngineSession` avoids that the way MakeMKV's own GUI does:
it spawns `makemkvcon guiserver` and speaks the GUI's protocol to it over stdin and stdout, keeps
one disc open, ticks titles and tracks individually, and writes the ticked titles in one job.

```swift
let session = EngineSession(executable: try MakeMKV.locate())
try await session.start()
let drives = try await session.drives()
let disc = try await session.open(.disc(0), minimumTitleLength: 120)   // the same DiscInfo a scan gives
for title in disc.titles {
    try await session.setSelected(title.index == 13, title: title.index)
}
try await session.saveSelectedTitles(to: URL(fileURLWithPath: "/Volumes/Rips"))
try await session.close()
await session.quit()
```

The protocol is not documented by MakeMKV. It is read from the open-source half of MakeMKV
1.18.4 — the command enum and ABI tag in `aproxy.h`, which its authors placed in the public
domain, the framing in `clt_pipe.cpp`, the callback handling in `client.cpp` — and it is gated
by an ABI tag the engine checks exactly, so a MakeMKV that bumps it will refuse this client
rather than misbehave. Measured on a Collection disc: the title tree the engine hands back matched
a robot-mode scan attribute for attribute across all 32 titles, a rip of one title took 18 seconds
where robot mode took 72, and the user's settings file was untouched. The engine lists a disc's
cover art as an item beside the tracks and ticks it; robot mode never does, so the session keeps
it out of `Title.tracks` and unticks it, and the two paths write the same file. One thing the
engine will do that robot mode cannot is ask a question; the session answers "no answer", which
makes the engine take its default, and reports what was asked as a message.

`SelectionRule` is MakeMKV's selection language with its own keywords — `all`, `audio`, `favlang`,
`core`, `havecore`, `forced` and the rest, each carrying MakeMKV's definition as its doc comment —
and `SelectionRule.makeMKVDefault` reproduces the rule in MakeMKV's shipped `default.mmcp.xml`
character for character. `ConversionProfile` mirrors that file rule for rule, with the selection
written in as a literal rather than as a reference to the installed preference, and is handed to
`makemkvcon` as a temporary `--profile` file for the run. The profile does not change which title
an index names; that was checked against a disc rather than assumed.

Parsing a saved log needs only the format library:

```swift
import MakeMKVRobot

let scan = DiscScan(parsing: try String(contentsOf: logURL, encoding: .utf8))
scan.disc?.titles.first?.audioTracks.map(\.codecShort)
```

`MakeMKV` is an actor. MakeMKV tolerates one process per drive at a time, so calls run one after
another and there is nothing else to arrange.

## The format, as measured

The developer page documents the line types. It does not document the grammar, so that was measured
against the 5,177 logs in TheDiscDb's data repository that have a derived record beside them, and
the parser is checked against every one of them in `CorpusTests`.

- Fields are comma-separated. A string is double-quoted. Inside a string a backslash escapes the
  next character: `\"`, `\\`, and a backslash at the end of a physical line escapes the line break,
  so a message can span lines. `RobotLineParser` is stateful for that reason alone.
- `CINFO`, `TINFO` and `SINFO` carry an attribute id, a message code and a value. The ids are
  `AP_ItemAttributeId` from `apdefs.h` in makemkv-oss, mirrored by name in `AttributeID`. The
  message code is non-zero when the value is a localised string with a stable numeric identity:
  a stream's type is `6201`, `6202` or `6203` whether the text says `Audio` or something else,
  and a disc is `6206` (DVD) or `6209` (Blu-ray, and UHD too). Match on the code.
- A Blu-ray title is identified by `SourceFileName` (`00117.mpls`); a DVD title has no such
  attribute and is identified by `OriginalTitleId` (`03`). `Title.sourceIdentifier` is whichever
  the disc has, and with `segmentMap` and `durationText` it is the identity of a title that
  survives a change of scan settings. TheDiscDb records the same three fields.
- A track's `StreamFlags` are the `AP_AVStreamFlag_*` bits, mirrored in `StreamFlags`. Two carry
  structure: a lossless audio track flagged `hasCoreAudio` is followed by its lossy core, flagged
  `derivedStream` and `coreAudio`, and a subtitle stream is followed by a forced-only one flagged
  `derivedStream` and `forcedSubtitles`. Adjacency is the only link, so `Title.derivedTracks(of:)`
  and `parentTrack(of:)` read it, and `primaryTracks` is the list without the derived ones.
- `DRV` lines always come sixteen at a time, one per possible drive slot; state and media flags
  are the `AP_DriveState*` and `AP_DskFsFlag*` constants from the same header.
- Switch names were checked against the `makemkvcon` binary: `messages`, `progress`, `cache`,
  `minlength`, `noscan`, `directio`, `decrypt`, `debug`, `profile`.
- The selection rule language is documented by MakeMKV on its forum (topic 4386), and the profile
  format by the `default.mmcp.xml` in the application's own data archive. A rule is a list of
  actions applied in order, later ones overriding earlier; `-sel:all` really does deselect
  everything, leaving a video-only file, so a rule that wants tracks starts with `+sel:all`.
  Measured on one title with a DTS-HD MA track and its core: `-sel:core` drops the core and keeps
  the lossless track, `-sel:havecore` does the opposite, and `-sel:subtitle` drops subtitles. A
  forced-only subtitle stream that turns out empty is dropped by MakeMKV whatever the rule says.

Anything the parser cannot read is kept verbatim as `.unrecognised` rather than dropped. TheDiscDb
appends `HSH:` lines of its own to the logs it keeps; those are the one expected occupant. A line
may only continue onto the next when it starts with a known prefix, so a damaged line with an odd
number of quotes — one log in the corpus is truncated at the top and opens mid-message — costs
itself and nothing after it.

## Tests

```sh
swift test
MAKEMKVKIT_THEDISCDB_DATA=~/src/thediscdb-data swift test -c release --filter CorpusTests
```

The first runs offline against three vendored logs — a Blu-ray, a DVD and a UHD — each compared
with the JSON TheDiscDb derived from it (`Tests/MakeMKVRobotTests/Fixtures`, MIT, notice
included). The second walks a clone of github.com/TheDiscDb/data and requires every log to parse
and every title's source, segment map, duration, size and stream types to agree with TheDiscDb's
record of it.

The driver's process handling has no automated test. It needs a drive with a disc in it, and is
exercised by hand.

## Not here

- Disc fingerprints. TheDiscDb's content hash is an MD5 over stream file sizes and its disc id a
  SHA1 of `AACS/Unit_Key_RO.inf`; both are plain reads of the mounted volume and belong to whatever
  tool wants them, not to a MakeMKV wrapper.
- `backup`, streaming, firmware tools, registration. Two operations was the brief.
- Chapter names and any editing of the ripped file. MKVToolNix does that.

## Licence

Apache 2.0 — see [LICENSE](LICENSE). Every Swift file carries an SPDX header and
`Scripts/check-license-headers.sh` enforces it in CI.

// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import MakeMKVRobot
import XCTest

/// Three whole logs from TheDiscDb, chosen for shape: a Blu-ray with duplicate playlists skipped, a
/// DVD, and a UHD. Each is checked against the JSON TheDiscDb derived from it.
final class FixtureTests: XCTestCase {
    func testBlurayAgreesWithTheDiscDb() throws {
        let scan = DiscScan(parsing: try Fixture.text("daleks-in-colour-disc01-bluray.txt"))
        XCTAssertEqual(disagreements(between: scan, and: try Fixture.record("daleks-in-colour-disc01-bluray.json")), [])
    }

    func testDVDAgreesWithTheDiscDb() throws {
        let scan = DiscScan(parsing: try Fixture.text("daleks-in-colour-disc02-dvd.txt"))
        XCTAssertEqual(disagreements(between: scan, and: try Fixture.record("daleks-in-colour-disc02-dvd.json")), [])
    }

    func testUHDAgreesWithTheDiscDb() throws {
        let scan = DiscScan(parsing: try Fixture.text("real-life-disc01-uhd.txt"))
        XCTAssertEqual(disagreements(between: scan, and: try Fixture.record("real-life-disc01-uhd.json")), [])
    }

    func testBlurayFacts() throws {
        let scan = DiscScan(parsing: try Fixture.text("daleks-in-colour-disc01-bluray.txt"))
        let disc = try XCTUnwrap(scan.disc)

        XCTAssertEqual(disc.mediaType, .bluray)
        XCTAssertEqual(disc.name, "Doctor Who - The Daleks In Colour - Disc 1")
        XCTAssertEqual(disc.volumeName, "DOCTOR_WHO")
        XCTAssertEqual(disc.titleCount, 10)
        XCTAssertEqual(disc.titles.count, 10)

        let feature = try XCTUnwrap(disc.title(index: 0))
        XCTAssertEqual(feature.sourceFileName, "00117.mpls")
        XCTAssertNil(feature.originalTitleId)
        XCTAssertEqual(feature.segmentMap, "45")
        XCTAssertEqual(feature.segmentCount, 1)
        XCTAssertEqual(feature.durationText, "1:15:20")
        XCTAssertEqual(feature.durationSeconds, 4520)
        XCTAssertEqual(feature.duration, .seconds(4520))
        XCTAssertEqual(feature.chapterCount, 12)
        XCTAssertEqual(feature.sizeBytes, 22_590_148_608)
        XCTAssertEqual(feature.outputFileName, "Doctor Who - The Daleks In Colour - Disc 1_t00.mkv")
        XCTAssertEqual(feature.videoTracks.count, 1)
        XCTAssertEqual(feature.audioTracks.prefix(3).map(\.codecShort), ["DTS-HD MA", "DTS", "TrueHD"])

        let audio = try XCTUnwrap(feature.tracks.first { $0.index == 1 })
        XCTAssertEqual(audio.kind, .audio)
        XCTAssertEqual(audio.languageCode, "eng")
        XCTAssertEqual(audio.codecId, "A_DTS")
        XCTAssertEqual(audio.audioChannelsCount, 6)
        XCTAssertEqual(audio.audioSampleRate, 48000)
        XCTAssertEqual(audio.mkvFlags, "d")
        XCTAssertEqual(audio.audioChannelLayoutName, "5.1(side)")

        // Two playlists were equal to ones already listed; MakeMKV says so and skips them.
        let skipped = scan.messages.filter { $0.code == MessageCode.titleSkippedDuplicate }
        XCTAssertEqual(skipped.map(\.parameters), [["00025.mpls", "00117.mpls"], ["00148.mpls", "00289.mpls"]])
        XCTAssertNotNil(scan.message(code: MessageCode.operationCompleted))

        // TheDiscDb's hash lines are not MakeMKV output; they are kept, not read.
        XCTAssertEqual(scan.unrecognised.count, 11)
        XCTAssertTrue(scan.unrecognised.allSatisfy { $0.hasPrefix("HSH:") })

        XCTAssertEqual(scan.drives.count, 16)
        XCTAssertEqual(scan.drives.filter(\.isPresent).count, 1)
        XCTAssertEqual(scan.drives[0].media, [.blurayFiles, .aacsFiles])
    }

    func testCoreAndForcedTracksAreDerivedFromTheOneBefore() throws {
        let scan = DiscScan(parsing: try Fixture.text("daleks-in-colour-disc01-bluray.txt"))
        let feature = try XCTUnwrap(scan.disc?.title(index: 0))

        let lossless = try XCTUnwrap(feature.tracks.first { $0.index == 1 })
        let core = try XCTUnwrap(feature.tracks.first { $0.index == 2 })
        XCTAssertEqual(lossless.flags, [.hasCoreAudio])
        XCTAssertEqual(core.flags, [.derivedStream, .coreAudio])
        XCTAssertTrue(lossless.hasCore)
        XCTAssertTrue(core.isDerived)
        XCTAssertTrue(core.isCore)
        XCTAssertEqual(feature.derivedTracks(of: lossless), [core])
        XCTAssertEqual(feature.parentTrack(of: core), lossless)
        XCTAssertNil(feature.parentTrack(of: lossless))
        XCTAssertEqual(feature.derivedTracks(of: core), [])

        let forced = feature.tracks.filter(\.isForcedOnly)
        XCTAssertFalse(forced.isEmpty)
        for track in forced {
            XCTAssertEqual(track.kind, .subtitles)
            XCTAssertEqual(track.flags, [.derivedStream, .forcedSubtitles])
            let parent = try XCTUnwrap(feature.parentTrack(of: track))
            XCTAssertEqual(parent.kind, .subtitles)
            XCTAssertTrue(feature.derivedTracks(of: parent).contains(track))
        }

        XCTAssertEqual(feature.primaryTracks.count + feature.tracks.filter(\.isDerived).count, feature.tracks.count)
    }

    func testDVDFacts() throws {
        let scan = DiscScan(parsing: try Fixture.text("daleks-in-colour-disc02-dvd.txt"))
        let disc = try XCTUnwrap(scan.disc)
        XCTAssertEqual(disc.mediaType, .dvd)
        XCTAssertEqual(disc.titleCount, 12)

        let episode = try XCTUnwrap(disc.title(index: 1))
        XCTAssertNil(episode.sourceFileName)
        XCTAssertEqual(episode.originalTitleId, "03")
        XCTAssertEqual(episode.sourceIdentifier, "03")
        XCTAssertEqual(episode.segmentMap, "1-6")
        XCTAssertEqual(episode.durationText, "0:24:22")
        XCTAssertEqual(episode.chapterCount, 6)
        XCTAssertEqual(episode.comment, "D2")
    }

    func testUHDIsReportedAsBluray() throws {
        let scan = DiscScan(parsing: try Fixture.text("real-life-disc01-uhd.txt"))
        let disc = try XCTUnwrap(scan.disc)
        XCTAssertEqual(disc.mediaType, .bluray, "UHD discs carry the Blu-ray type code; the format is not distinguishable here")
        XCTAssertEqual(disc.titleCount, 4)
    }

    func testEmptyRunHasNoDisc() {
        let scan = DiscScan(parsing: """
            MSG:1005,0,1,"MakeMKV v1.18.4 darwin(arm64-release) started","%1 started","MakeMKV v1.18.4 darwin(arm64-release)"
            MSG:5042,0,0,"The program can't find any usable optical drives.","The program can't find any usable optical drives."
            DRV:0,256,999,0,"","",""
            MSG:5010,0,0,"Failed to open disc","Failed to open disc"
            TCOUNT:0
            """)
        XCTAssertNotNil(scan.message(code: MessageCode.noUsableDrives))
        XCTAssertNotNil(scan.message(code: MessageCode.failedToOpenDisc))
        XCTAssertEqual(scan.disc?.titleCount, 0)
        XCTAssertEqual(scan.disc?.titles, [])
    }
}

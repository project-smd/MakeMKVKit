// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import MakeMKVRobot
import Testing

/// Three whole logs from TheDiscDb, chosen for shape: a Blu-ray with duplicate playlists skipped, a
/// DVD, and a UHD. Each is checked against the JSON TheDiscDb derived from it.
struct FixtureTests {
    @Test(arguments: ["daleks-in-colour-disc01-bluray", "daleks-in-colour-disc02-dvd", "real-life-disc01-uhd"])
    func agreesWithTheDiscDb(fixture: String) throws {
        let scan = DiscScan(parsing: try Fixture.text(fixture + ".txt"))
        #expect(disagreements(between: scan, and: try Fixture.record(fixture + ".json")) == [])
    }

    @Test func blurayFacts() throws {
        let scan = DiscScan(parsing: try Fixture.text("daleks-in-colour-disc01-bluray.txt"))
        let disc = try #require(scan.disc)

        #expect(disc.mediaType == .bluray)
        #expect(disc.name == "Doctor Who - The Daleks In Colour - Disc 1")
        #expect(disc.volumeName == "DOCTOR_WHO")
        #expect(disc.titleCount == 10)
        #expect(disc.titles.count == 10)

        let feature = try #require(disc.title(index: 0))
        #expect(feature.sourceFileName == "00117.mpls")
        #expect(feature.originalTitleId == nil)
        #expect(feature.segmentMap == "45")
        #expect(feature.segmentCount == 1)
        #expect(feature.durationText == "1:15:20")
        #expect(feature.durationSeconds == 4520)
        #expect(feature.duration == .seconds(4520))
        #expect(feature.chapterCount == 12)
        #expect(feature.sizeBytes == 22_590_148_608)
        #expect(feature.outputFileName == "Doctor Who - The Daleks In Colour - Disc 1_t00.mkv")
        #expect(feature.videoTracks.count == 1)
        #expect(feature.audioTracks.prefix(3).map(\.codecShort) == ["DTS-HD MA", "DTS", "TrueHD"])

        let audio = try #require(feature.tracks.first { $0.index == 1 })
        #expect(audio.kind == .audio)
        #expect(audio.languageCode == "eng")
        #expect(audio.codecId == "A_DTS")
        #expect(audio.audioChannelsCount == 6)
        #expect(audio.audioSampleRate == 48000)
        #expect(audio.mkvFlags == "d")
        #expect(audio.audioChannelLayoutName == "5.1(side)")

        // Two playlists were equal to ones already listed; MakeMKV says so and skips them.
        let skipped = scan.messages.filter { $0.code == MessageCode.titleSkippedDuplicate }
        #expect(skipped.map(\.parameters) == [["00025.mpls", "00117.mpls"], ["00148.mpls", "00289.mpls"]])
        #expect(scan.message(code: MessageCode.operationCompleted) != nil)

        // TheDiscDb's hash lines are not MakeMKV output; they are kept, not read.
        #expect(scan.unrecognised.count == 11)
        #expect(scan.unrecognised.allSatisfy { $0.hasPrefix("HSH:") })

        #expect(scan.drives.count == 16)
        #expect(scan.drives.filter(\.isPresent).count == 1)
        #expect(scan.drives[0].media == [.blurayFiles, .aacsFiles])
    }

    @Test func coreAndForcedTracksAreDerivedFromTheOneBefore() throws {
        let scan = DiscScan(parsing: try Fixture.text("daleks-in-colour-disc01-bluray.txt"))
        let feature = try #require(scan.disc?.title(index: 0))

        let lossless = try #require(feature.tracks.first { $0.index == 1 })
        let core = try #require(feature.tracks.first { $0.index == 2 })
        #expect(lossless.flags == [.hasCoreAudio])
        #expect(core.flags == [.derivedStream, .coreAudio])
        #expect(lossless.hasCore)
        #expect(core.isDerived)
        #expect(core.isCore)
        #expect(feature.derivedTracks(of: lossless) == [core])
        #expect(feature.parentTrack(of: core) == lossless)
        #expect(feature.parentTrack(of: lossless) == nil)
        #expect(feature.derivedTracks(of: core) == [])

        let forced = feature.tracks.filter(\.isForcedOnly)
        #expect(!forced.isEmpty)
        for track in forced {
            #expect(track.kind == .subtitles)
            #expect(track.flags == [.derivedStream, .forcedSubtitles])
            let parent = try #require(feature.parentTrack(of: track))
            #expect(parent.kind == .subtitles)
            #expect(feature.derivedTracks(of: parent).contains(track))
        }

        #expect(feature.primaryTracks.count + feature.tracks.filter(\.isDerived).count == feature.tracks.count)
    }

    @Test func dvdFacts() throws {
        let scan = DiscScan(parsing: try Fixture.text("daleks-in-colour-disc02-dvd.txt"))
        let disc = try #require(scan.disc)
        #expect(disc.mediaType == .dvd)
        #expect(disc.titleCount == 12)

        let episode = try #require(disc.title(index: 1))
        #expect(episode.sourceFileName == nil)
        #expect(episode.originalTitleId == "03")
        #expect(episode.sourceIdentifier == "03")
        #expect(episode.segmentMap == "1-6")
        #expect(episode.durationText == "0:24:22")
        #expect(episode.chapterCount == 6)
        #expect(episode.comment == "D2")
    }

    @Test func uhdIsReportedAsBluray() throws {
        let scan = DiscScan(parsing: try Fixture.text("real-life-disc01-uhd.txt"))
        let disc = try #require(scan.disc)
        #expect(disc.mediaType == .bluray, "UHD discs carry the Blu-ray type code; the format is not distinguishable here")
        #expect(disc.titleCount == 4)
    }

    @Test func emptyRunHasNoDisc() {
        let scan = DiscScan(parsing: """
            MSG:1005,0,1,"MakeMKV v1.18.4 darwin(arm64-release) started","%1 started","MakeMKV v1.18.4 darwin(arm64-release)"
            MSG:5042,0,0,"The program can't find any usable optical drives.","The program can't find any usable optical drives."
            DRV:0,256,999,0,"","",""
            MSG:5010,0,0,"Failed to open disc","Failed to open disc"
            TCOUNT:0
            """)
        #expect(scan.message(code: MessageCode.noUsableDrives) != nil)
        #expect(scan.message(code: MessageCode.failedToOpenDisc) != nil)
        #expect(scan.disc?.titleCount == 0)
        #expect(scan.disc?.titles == [])
    }
}

// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation
import MakeMKVRobot
import XCTest

/// The parts of a TheDiscDb `discNN.json` that restate facts from the MakeMKV log beside it.
///
/// TheDiscDb wrote these from the same logs with its own parser, so agreeing with them across its
/// whole data repository is the closest thing to a second implementation this parser can be tested
/// against.
struct TheDiscDbDisc: Decodable {
    struct Title: Decodable {
        struct Track: Decodable {
            var Index: Int
            var type: String

            enum CodingKeys: String, CodingKey {
                case Index
                case type = "Type"
            }
        }
        var Index: Int
        var SourceFile: String?
        var SegmentMap: String?
        var Duration: String?
        var Size: Int?
        var Tracks: [Track]?
    }

    var Format: String?
    var Titles: [Title]
}

/// Compare a parsed scan against its TheDiscDb record. Returns one line per disagreement.
func disagreements(between scan: DiscScan, and record: TheDiscDbDisc) -> [String] {
    var problems: [String] = []
    guard let disc = scan.disc else {
        return ["no disc parsed"]
    }
    for expected in record.Titles {
        guard let title = disc.title(index: expected.Index) else {
            problems.append("title \(expected.Index) missing")
            continue
        }
        if title.sourceIdentifier != expected.SourceFile {
            problems.append("title \(expected.Index) source \(title.sourceIdentifier ?? "nil") != \(expected.SourceFile ?? "nil")")
        }
        if title.segmentMap != expected.SegmentMap {
            problems.append("title \(expected.Index) segments \(title.segmentMap ?? "nil") != \(expected.SegmentMap ?? "nil")")
        }
        if title.durationText != expected.Duration {
            problems.append("title \(expected.Index) duration \(title.durationText ?? "nil") != \(expected.Duration ?? "nil")")
        }
        if title.sizeBytes != expected.Size {
            problems.append("title \(expected.Index) size \(title.sizeBytes.map(String.init) ?? "nil") != \(expected.Size.map(String.init) ?? "nil")")
        }
        for track in expected.Tracks ?? [] {
            guard let parsed = title.tracks.first(where: { $0.index == track.Index }) else {
                problems.append("title \(expected.Index) stream \(track.Index) missing")
                continue
            }
            // TheDiscDb stores the type as the text MakeMKV printed, which is localised — "Untertitel"
            // on a German install — so agree on either the code-derived kind or the literal text.
            let kind: TrackKind? = switch track.type {
            case "Video": .video
            case "Audio": .audio
            case "Subtitles": .subtitles
            default: nil
            }
            if parsed.kind != kind && parsed[.type] != track.type {
                problems.append("title \(expected.Index) stream \(track.Index) kind \(parsed.kind) != \(track.type)")
            }
        }
    }
    return problems
}

enum Fixture {
    static func url(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"), "fixture \(name)")
    }

    static func text(_ name: String) throws -> String {
        try String(contentsOf: url(name), encoding: .utf8)
    }

    static func record(_ name: String) throws -> TheDiscDbDisc {
        try JSONDecoder().decode(TheDiscDbDisc.self, from: Data(contentsOf: url(name)))
    }
}

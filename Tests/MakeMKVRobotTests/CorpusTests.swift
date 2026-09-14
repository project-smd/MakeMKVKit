// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation
import MakeMKVRobot
import Testing

/// Runs the parser over every log in a clone of github.com/TheDiscDb/data and compares each against
/// the JSON TheDiscDb derived from it. Disabled unless `MAKEMKVKIT_THEDISCDB_DATA` names the clone.
///
///     MAKEMKVKIT_THEDISCDB_DATA=~/src/thediscdb-data swift test -c release --filter CorpusTests
struct CorpusTests {
    static var dataRoot: String? { ProcessInfo.processInfo.environment["MAKEMKVKIT_THEDISCDB_DATA"] }

    /// Logs that are broken in the repository rather than in this parser. Each still has to parse
    /// well enough for its titles to agree with TheDiscDb's record; only its unreadable lines are
    /// excused.
    ///
    /// - Miami Vice disc 9 is truncated at the top and opens part-way through a multi-line message.
    private static let damagedUpstream: Set<String> = [
        "series/Miami Vice (1984)/2016-complete-series-blu-ray/disc09.txt",
    ]

    @Test(.enabled(if: dataRoot != nil, "set MAKEMKVKIT_THEDISCDB_DATA to a clone of TheDiscDb/data"))
    func everyLogAgreesWithItsRecord() throws {
        let root = try #require(Self.dataRoot)
        let dataURL = URL(fileURLWithPath: (root as NSString).expandingTildeInPath).appendingPathComponent("data")
        let enumerator = try #require(FileManager.default.enumerator(at: dataURL, includingPropertiesForKeys: nil))

        var logs = 0
        var unreadable: [String] = []
        var problems: [String] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("disc"), name.hasSuffix(".txt"), name.count == 10 else { continue }
            let recordURL = url.deletingPathExtension().appendingPathExtension("json")
            guard FileManager.default.fileExists(atPath: recordURL.path) else { continue }
            logs += 1

            let scan = DiscScan(parsing: decode(try Data(contentsOf: url)))
            let record = try JSONDecoder().decode(TheDiscDbDisc.self, from: Data(contentsOf: recordURL))

            let path = String(url.path.dropFirst(dataURL.path.count + 1))
            if !Self.damagedUpstream.contains(path) {
                for line in scan.unrecognised where !line.hasPrefix("HSH:") {
                    unreadable.append("\(path): \(line.prefix(80))")
                }
            }
            for problem in disagreements(between: scan, and: record) {
                problems.append("\(path): \(problem)")
            }
        }

        #expect(logs > 1000, "expected the whole corpus, found \(logs) logs under \(dataURL.path)")
        #expect(unreadable.count == 0, "lines not parsed, by file:\n\(histogram(unreadable))\nfirst few:\n\(unreadable.prefix(8).joined(separator: "\n"))")
        #expect(problems.count == 0, "disagreements, by file:\n\(histogram(problems))\nfirst few:\n\(problems.prefix(8).joined(separator: "\n"))")
        print("corpus: \(logs) logs, \(unreadable.count) unreadable lines, \(problems.count) disagreements")
    }

    /// MakeMKV writes UTF-8, but a few logs in the corpus were saved through something that
    /// re-encoded them as UTF-16 with a byte-order mark. Honour the mark; otherwise read as UTF-8,
    /// lossily, since a handful carry stray bytes that are not valid in any encoding.
    private func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            let byteOrder: String.Encoding = data.starts(with: [0xFF, 0xFE]) ? .utf16LittleEndian : .utf16BigEndian
            if let text = String(data: data.dropFirst(2), encoding: byteOrder) {
                return text
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// "path: detail" lines counted per path, most first, capped so the failure message stays readable.
    private func histogram(_ entries: [String]) -> String {
        var counts: [String: Int] = [:]
        for entry in entries {
            counts[String(entry.prefix { $0 != ":" }), default: 0] += 1
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(15)
            .map { "\($0.value)\t\($0.key)" }
            .joined(separator: "\n")
    }
}

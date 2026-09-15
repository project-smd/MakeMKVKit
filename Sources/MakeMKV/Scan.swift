// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation
import MakeMKVRobot

/// One completed `info` run: what was scanned, how, and what it said.
///
/// This is the only thing a rip accepts, because the title indices inside it are only meaningful
/// together with the source and settings that produced them.
public struct Scan: Hashable, Sendable {
    public let source: Source
    public let settings: ScanSettings
    /// The robot-mode run this came from, empty for a scan made through an `EngineSession`.
    public let result: DiscScan
    private let engineDisc: DiscInfo?

    public init(source: Source, settings: ScanSettings, result: DiscScan) {
        self.source = source
        self.settings = settings
        self.result = result
        self.engineDisc = nil
    }

    /// A scan made through an `EngineSession`, which hands back the disc directly.
    public init(source: Source, settings: ScanSettings, disc: DiscInfo) {
        self.source = source
        self.settings = settings
        self.result = DiscScan(lines: [])
        self.engineDisc = disc
    }

    public var disc: DiscInfo? { engineDisc ?? result.disc }
    public var titles: [Title] { disc?.titles ?? [] }

    /// The title with this index, if the scan listed it.
    public func title(index: Int) -> Title? {
        disc?.title(index: index)
    }
}

/// Progress of a rip, as MakeMKV reports it: a caption for the step, a caption for the job, and a
/// pair of counters out of `maximum`.
public struct RipProgress: Hashable, Sendable {
    public var current: ProgressTitle?
    public var total: ProgressTitle?
    public var value: ProgressValue

    public init(current: ProgressTitle?, total: ProgressTitle?, value: ProgressValue) {
        self.current = current
        self.total = total
        self.value = value
    }
}

public struct RipResult: Hashable, Sendable {
    /// The file MakeMKV wrote, named by the title's `outputFileName` inside the destination.
    public let outputURL: URL
    public let log: [RobotLine]

    public init(outputURL: URL, log: [RobotLine]) {
        self.outputURL = outputURL
        self.log = log
    }

    public var messages: [Message] {
        log.compactMap {
            if case .message(let message) = $0 { message } else { nil }
        }
    }
}

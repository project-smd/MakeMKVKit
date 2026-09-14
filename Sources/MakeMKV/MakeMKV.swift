// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation
import MakeMKVRobot

/// A `makemkvcon` installation, driven in robot mode.
///
/// An actor because MakeMKV tolerates one process per drive at a time; every call here runs to
/// completion before the next starts, which is the whole of the concurrency story.
public actor MakeMKV {
    public nonisolated let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// Finds `makemkvcon` in the application bundle, then on `PATH`.
    public init() throws {
        self.init(executable: try Self.locate())
    }

    public static let defaultLocations = [
        URL(fileURLWithPath: "/Applications/MakeMKV.app/Contents/MacOS/makemkvcon"),
    ]

    public static func locate(
        defaultLocations: [URL] = defaultLocations,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        var searched = defaultLocations
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            searched.append(URL(fileURLWithPath: String(directory)).appendingPathComponent("makemkvcon"))
        }
        if let found = searched.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return found
        }
        throw MakeMKVError.executableNotFound(searched: searched)
    }

    // MARK: - Operations

    /// The drive table, one entry per slot MakeMKV knows about, present or not.
    ///
    /// There is no command for this, so it asks `info` about a disc index MakeMKV cannot have: the
    /// engine enumerates drives on startup, prints them, fails to open the disc and exits non-zero.
    /// That exit status is the expected outcome here, not a failure. This is how the GUI's drive
    /// list is obtained by everyone who scripts `makemkvcon`.
    public func drives() async throws -> [Drive] {
        let lines = try await run(
            settings: ScanSettings(cacheMegabytes: 1),
            command: ["info", "disc:9999"],
            onLine: nil,
            tolerateFailure: true
        )
        return DiscScan(lines: lines).drives
    }

    /// `makemkvcon -r … info SOURCE`. Throws `discUnavailable` when the run listed no disc.
    ///
    /// `onLine` sees every line as it arrives, which is how a caller shows MakeMKV's messages while
    /// the disc is still being read rather than when the scan returns. The same lines are in the
    /// result afterwards.
    public func scan(
        _ source: Source,
        settings: ScanSettings = ScanSettings(),
        onLine: (@Sendable (RobotLine) -> Void)? = nil
    ) async throws -> Scan {
        let lines = try await run(settings: settings, command: ["info", source.argument], onLine: onLine)
        let result = DiscScan(lines: lines)
        guard result.disc != nil,
              result.message(code: MessageCode.noUsableDrives) == nil,
              result.message(code: MessageCode.failedToOpenDisc) == nil else {
            throw MakeMKVError.discUnavailable(messages: result.messages)
        }
        return Scan(source: source, settings: settings, result: result)
    }

    /// `makemkvcon -r … mkv SOURCE INDEX DESTINATION`, with the source and settings of `scan`.
    ///
    /// `title` must be one of `scan.titles`, compared whole rather than by index, so a title carried
    /// over from a different scan is refused before anything spins.
    ///
    /// `profile` says which tracks the file keeps. Without one MakeMKV uses the selection rule saved
    /// in this machine's preferences, which is whatever the GUI last had, so a rip meant to be the
    /// same everywhere passes one. The profile is written to a temporary file for the run and
    /// removed afterwards.
    public func rip(
        _ title: Title,
        from scan: Scan,
        to destination: URL,
        profile: ConversionProfile? = nil,
        onLine: (@Sendable (RobotLine) -> Void)? = nil,
        progress: (@Sendable (RipProgress) -> Void)? = nil
    ) async throws -> RipResult {
        guard scan.titles.contains(title) else {
            throw MakeMKVError.titleNotInScan(index: title.index)
        }
        guard let outputFileName = title.outputFileName else {
            throw MakeMKVError.titleHasNoOutputName(index: title.index)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var settings = scan.settings
        var profileURL: URL?
        if let profile {
            let url = try profile.writeToTemporaryFile()
            profileURL = url
            settings.additionalArguments.append("--profile=\(url.path)")
        }
        defer {
            if let profileURL {
                try? FileManager.default.removeItem(at: profileURL)
            }
        }

        let tracker = ProgressTracker(report: progress)
        var observe: (@Sendable (RobotLine) -> Void)?
        if progress != nil || onLine != nil {
            observe = { @Sendable line in
                tracker.observe(line)
                onLine?(line)
            }
        }
        let lines = try await run(
            settings: settings,
            command: ["mkv", scan.source.argument, String(title.index), destination.path],
            onLine: observe
        )

        let outputURL = destination.appendingPathComponent(outputFileName)
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            let messages = lines.compactMap { if case .message(let m) = $0 { m } else { nil } }
            throw MakeMKVError.outputMissing(outputURL, messages: messages)
        }
        return RipResult(outputURL: outputURL, log: lines)
    }

    // MARK: - Process

    private func run(
        settings: ScanSettings,
        command: [String],
        onLine: (@Sendable (RobotLine) -> Void)?,
        tolerateFailure: Bool = false
    ) async throws -> [RobotLine] {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-r", "--messages=-stdout", "--progress=-same"] + settings.arguments + command

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let exit = ExitStatus()
        process.terminationHandler = { exit.resume(with: $0.terminationStatus) }
        try process.run()

        var parser = RobotLineParser()
        var lines: [RobotLine] = []
        for try await physical in pipe.fileHandleForReading.bytes.lines {
            if let line = parser.feed(physical) {
                lines.append(line)
                onLine?(line)
            }
        }
        if let line = parser.finish() {
            lines.append(line)
            onLine?(line)
        }

        let status = await exit.value()
        guard status == 0 || tolerateFailure else {
            let messages = lines.compactMap { if case .message(let m) = $0 { m } else { nil } }
            throw MakeMKVError.processFailed(status: status, messages: messages)
        }
        return lines
    }
}

/// Bridges `Process.terminationHandler` to an awaitable value. The handler may fire before or after
/// anyone asks, so both orders are handled under one lock.
private final class ExitStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func resume(with status: Int32) {
        lock.lock()
        self.status = status
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: status)
    }

    func value() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

/// Folds the three progress line types into one report per `PRGV`.
private final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var current: ProgressTitle?
    private var total: ProgressTitle?
    private let report: (@Sendable (RipProgress) -> Void)?

    init(report: (@Sendable (RipProgress) -> Void)?) {
        self.report = report
    }

    func observe(_ line: RobotLine) {
        lock.lock()
        defer { lock.unlock() }
        switch line {
        case .progressCurrent(let title):
            current = title
        case .progressTotal(let title):
            total = title
        case .progressValue(let value):
            report?(RipProgress(current: current, total: total, value: value))
        default:
            break
        }
    }
}

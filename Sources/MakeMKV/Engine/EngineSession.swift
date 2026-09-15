// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation
import MakeMKVRobot

/// One MakeMKV engine kept alive across operations, the way the GUI keeps it: the disc is opened
/// once, its titles and tracks are ticked individually, and every ticked title is written in one
/// job. That is what `makemkvcon mkv` cannot do, and why ripping several titles through it
/// re-reads the disc for each.
///
/// The protocol is MakeMKV's own, unpublished, read from its open-source GUI; see
/// `EngineProtocol`. Use it where the re-reads matter and robot mode where stability does.
public actor EngineSession {
    public enum Failure: Error {
        case notStarted
        case engineExited
        case engineReported(code: Int, text: String)
        case openFailed
        case noDiscOpen
        case saveRefused
        case unknownTitle(Int)
    }

    /// What the engine says while it works, delivered as it arrives.
    public struct Event: Sendable {
        public enum Kind: Sendable {
            case message(Message)
            case progress(RipProgress)
            case currentInfo(String)
            case jobStarted
            case jobFinished
        }
        public var kind: Kind
    }

    public nonisolated let executable: URL
    private let connection: EngineConnection
    private var started = false
    private var inJob = false
    private var eventHandler: (@Sendable (Event) -> Void)?

    // Drive table, as the engine reports it.
    private var driveTable: [Int: Drive] = [:]

    // The open disc: item handles the engine hands out, by title and track index.
    private var collectionHandle: UInt64?
    private var titleHandles: [Int: UInt64] = [:]
    private var trackHandles: [Int: [Int: UInt64]] = [:]
    private var chapterHandles: [Int: [Int: UInt64]] = [:]
    private var attachmentHandles: [Int: [UInt64]] = [:]
    private var expectedTitles = 0

    // Progress state, folded from the engine's separate callbacks.
    /// How many job cycles the engine has finished. A job-triggering call waits for this to move
    /// past the value it read beforehand, which is reliable whether the job runs inside the call's
    /// own callback loop or starts a moment after it returns — the case an `inJob` check raced on.
    private var jobsCompleted = 0
    private var currentTitleCode: UInt32 = 0
    private var totalTitleCode: UInt32 = 0
    private var currentBar = 0
    private var totalBar = 0
    private var stringCache: [UInt32: String] = [:]

    public init(executable: URL) {
        self.executable = executable
        self.connection = EngineConnection(executable: executable)
    }

    /// Where the engine's messages and progress go. Set before starting long operations.
    public func setEventHandler(_ handler: (@Sendable (Event) -> Void)?) {
        eventHandler = handler
    }

    // MARK: - Lifecycle

    public func start() async throws {
        try await connection.start()
        started = true
    }

    /// For diagnosing a dead engine: its exit status and anything it wrote to stderr.
    public var diagnostics: String {
        "exit=\(connection.terminationStatus.map(String.init) ?? "running") stderr=\(connection.stderrText)"
    }

    /// Ask the engine to exit, then make sure it has.
    public func quit() async {
        if started, connection.isRunning {
            _ = try? await call(.callSignalExit)
        }
        connection.terminate()
        started = false
    }

    // MARK: - Engine facts

    /// One of the engine's own strings: name, version, key type, output folder and so on.
    public func appString(_ id: EngineProtocol.AppString) async throws -> String? {
        try await appString(id.rawValue)
    }

    func appString(_ id: UInt32, index1: UInt32 = 0, index2: UInt32 = 0) async throws -> String? {
        let reply = try await call(.callAppGetString, args: [id, index1, index2])
        return reply.args.first != 0 ? reply.string : nil
    }

    /// The text of a message code, cached; how a coded attribute value becomes its words.
    func messageText(_ code: UInt32) async -> String {
        if let cached = stringCache[code] { return cached }
        let text = (try? await appString(EngineProtocol.messageStringBase + code)) ?? ""
        stringCache[code] = text
        return text
    }

    // MARK: - Drives

    /// The drive table. The engine scans on request and reports each slot back through callbacks,
    /// possibly after the call returns, so this pumps the engine until the job is over.
    public func drives() async throws -> [Drive] {
        try await runJob { try await self.call(.callUpdateAvailableDrives, args: [0]) }
        return driveTable.keys.sorted().compactMap { driveTable[$0] }
    }

    // MARK: - Disc

    /// Open a source and read back the whole title tree as a `DiscInfo`, the same shape a robot
    /// scan produces. The disc stays open in the engine until `close()` or the next `open`.
    ///
    /// The engine hands over items as handles while it opens the disc; each attribute is then a
    /// separate round trip per item, so a Blu-ray with thirty titles is a few thousand
    /// transactions, which takes a second or two over the pipe. A coded value — a track's type,
    /// a disc's kind — comes back as a message code and is resolved to its text through the
    /// engine, so the result carries the same codes robot mode prints.
    public func open(_ source: Source, minimumTitleLength: Int? = nil) async throws -> DiscInfo {
        if let minimumTitleLength {
            _ = try await call(.callSetSettingInt, args: [EngineProtocol.Setting.dvdMinimumTitleLength.rawValue, UInt32(minimumTitleLength)])
        }
        let opened: EngineProtocol.Frame
        switch source {
        case .disc(let index):
            opened = try await runJob { try await self.call(.callOpenCdDisk, args: [UInt32(index), 0]) }
        case .device(let path):
            opened = try await runJob { try await self.call(.callOpenTitleCollection, args: [0], string: "dev:" + path) }
        case .iso(let url), .folder(let url):
            opened = try await runJob { try await self.call(.callOpenFile, args: [0], string: url.path) }
        }
        guard opened.args.first != 0, let collectionHandle else { throw Failure.openFailed }

        let discAttributes = try await attributes(of: collectionHandle)
        var titles: [Title] = []
        attachmentHandles = [:]
        for index in titleHandles.keys.sorted() {
            let titleAttributes = try await attributes(of: titleHandles[index]!)
            var tracks: [Track] = []
            for trackIndex in (trackHandles[index] ?? [:]).keys.sorted() {
                let handle = trackHandles[index]![trackIndex]!
                let track = Track(index: trackIndex, attributes: try await attributes(of: handle))
                // The engine lists a disc's cover art as an item beside the tracks, type code
                // 6214, and ticks it. Robot mode never lists it and never writes it, so for the
                // two paths to produce the same file it is kept out of the tracks and unticked.
                if track.attributes[.type]?.messageCode == EngineProtocol.attachmentTypeCode {
                    attachmentHandles[index, default: []].append(handle)
                    trackHandles[index]?[trackIndex] = nil
                    continue
                }
                tracks.append(track)
            }
            titles.append(Title(index: index, attributes: titleAttributes, tracks: tracks))
        }
        for handles in attachmentHandles.values {
            for handle in handles {
                try await setState(of: handle, enabledBit: false)
            }
        }
        return DiscInfo(titleCount: expectedTitles, attributes: discAttributes, titles: titles)
    }


    /// The selection rule the engine applies when it opens a disc: MakeMKV's own
    /// `app_DefaultSelectionString`, set in the engine's memory for this session only. Set it
    /// before `open`, since the engine ticks tracks as it builds the tree. `saveSettings` is never
    /// called, so the user's own preference on disk is left alone.
    public func setSelectionRule(_ rule: SelectionRule) async throws {
        _ = try await call(.callSetSettingString, args: [EngineProtocol.Setting.appDefaultSelectionString.rawValue, 1], string: rule.description)
    }

    /// Whether the engine has a title ticked for saving.
    public func isSelected(title index: Int) async throws -> Bool {
        guard let handle = titleHandles[index] else { throw Failure.unknownTitle(index) }
        return try await state(of: handle) & EngineProtocol.itemEnabledBit != 0
    }

    /// Tick or untick a title. Only ticked titles are written by `saveSelectedTitles`.
    public func setSelected(_ selected: Bool, title index: Int) async throws {
        guard let handle = titleHandles[index] else { throw Failure.unknownTitle(index) }
        try await setState(of: handle, enabledBit: selected)
    }

    /// Whether the engine has a track ticked, after the selection rule and any change since.
    public func isSelected(title index: Int, track: Int) async throws -> Bool {
        guard let handle = trackHandles[index]?[track] else { throw Failure.unknownTitle(index) }
        return try await state(of: handle) & EngineProtocol.itemEnabledBit != 0
    }

    public func setSelected(_ selected: Bool, title index: Int, track: Int) async throws {
        guard let handle = trackHandles[index]?[track] else { throw Failure.unknownTitle(index) }
        try await setState(of: handle, enabledBit: selected)
    }

    /// Write every ticked title to `destination` in one job, the disc read once for the lot. The
    /// files are named by each title's `outputFileName`. Progress and messages arrive through the
    /// event handler; this returns when the engine leaves job mode.
    public func saveSelectedTitles(to destination: URL) async throws {
        guard collectionHandle != nil else { throw Failure.noDiscOpen }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try await call(.callSetOutputFolder, string: destination.path)
        let saved = try await runJob { try await self.call(.callSaveAllSelectedTitlesToMkv) }
        guard saved.args.first != 0 else { throw Failure.saveRefused }
    }

    /// Stop whatever job is running. The engine finishes the file it is on cleanly.
    public func cancel() async throws {
        _ = try await call(.callCancelAllJobs)
    }

    private func state(of handle: UInt64) async throws -> UInt32 {
        let reply = try await call(.callGetUiItemState, args: [UInt32(truncatingIfNeeded: handle), UInt32(truncatingIfNeeded: handle >> 32)])
        return reply.args.first ?? 0
    }

    private func setState(of handle: UInt64, enabledBit: Bool) async throws {
        let current = try await state(of: handle)
        let wanted = enabledBit ? current | EngineProtocol.itemEnabledBit : current & ~EngineProtocol.itemEnabledBit
        guard wanted != current else { return }
        _ = try await call(.callSetUiItemState, args: [UInt32(truncatingIfNeeded: handle), UInt32(truncatingIfNeeded: handle >> 32), wanted])
    }

    /// Close the open disc, ejecting nothing.
    public func close() async throws {
        try await runJob { try await self.call(.callCloseDisk, args: [EngineProtocol.maxDrives]) }
        collectionHandle = nil
        titleHandles = [:]
        trackHandles = [:]
    }

    /// Every attribute the engine has for an item, keyed as robot mode keys them.
    private func attributes(of handle: UInt64) async throws -> [AttributeID: Attribute] {
        var result: [AttributeID: Attribute] = [:]
        for raw in 1...50 {
            let reply = try await call(.callGetUiItemInfo, args: [UInt32(truncatingIfNeeded: handle), UInt32(truncatingIfNeeded: handle >> 32), UInt32(raw)])
            let id = AttributeID(rawValue: raw)
            if let code = reply.args.first, code != 0 {
                result[id] = Attribute(id: id, messageCode: Int(code), value: await messageText(code))
            } else if reply.args.count > 1, reply.args[1] != 0 {
                result[id] = Attribute(id: id, messageCode: 0, value: reply.string)
            }
        }
        return result
    }

    // MARK: - Transactions

    /// Send a call and service every callback the engine raises before it returns.
    @discardableResult
    func call(_ command: EngineProtocol.Command, args: [UInt32] = [], data: Data = Data()) async throws -> EngineProtocol.Frame {
        guard started else { throw Failure.notStarted }
        var outgoing = EngineProtocol.Frame(command, args: args, data: data)
        while true {
            let reply = try await connection.transact(outgoing)
            switch reply.command {
            case .return:
                return reply
            case .backExit, .backFatalCommError, .backOutOfMem:
                started = false
                throw Failure.engineExited
            default:
                outgoing = try await handle(callback: reply)
            }
        }
    }

    func call(_ command: EngineProtocol.Command, args: [UInt32] = [], string: String?) async throws -> EngineProtocol.Frame {
        try await call(command, args: args, data: string.map { Data($0.utf8) + [0] } ?? Data())
    }

    /// Service one callback and produce the `clientDone` frame that lets the engine continue.
    /// The shapes are `CApClient::ExecCmdPacked` in `client.cpp`.
    private func handle(callback frame: EngineProtocol.Frame) async throws -> EngineProtocol.Frame {
        var done = EngineProtocol.Frame(.clientDone)
        switch frame.command {
        case .nop:
            break
        case .backEnterJobMode:
            inJob = true
            emit(.jobStarted)
        case .backLeaveJobMode:
            inJob = false
            jobsCompleted += 1
            emit(.jobFinished)
        case .backUpdateDrive:
            let strings = frame.strings
            var cursor = 0
            func next(_ present: Bool) -> String {
                guard present, cursor < strings.count else { return "" }
                defer { cursor += 1 }
                return strings[cursor]
            }
            let mask = frame.args[1]
            let driveName = next(mask & 1 != 0)
            let discName = next(mask & 2 != 0)
            let deviceName = next(mask & 4 != 0)
            let index = Int(frame.args[0])
            driveTable[index] = Drive(
                index: index,
                state: DriveState(rawValue: Int(frame.args[2])),
                enabled: 999,
                media: MediaFlags(rawValue: Int(frame.args[3])),
                driveName: driveName,
                discName: discName,
                devicePath: deviceName
            )
        case .backSetTotalName:
            totalTitleCode = frame.args[0]
        case .backUpdateLayout:
            currentTitleCode = frame.args[0]
        case .backUpdateCurrentInfo:
            emit(.currentInfo(frame.string))
        case .backUpdateCurrentBar:
            currentBar = Int(frame.args[0])
            await emitProgress()
        case .backUpdateTotalBar:
            totalBar = Int(frame.args[0])
            await emitProgress()
        case .backReportUiMessage:
            let code = Int(frame.args[0])
            let flags = frame.args[1]
            emit(.message(Message(code: code, flags: flags, text: frame.string, format: frame.string, parameters: [])))
            done = EngineProtocol.Frame(.clientDone, args: [0])
        case .backReportUiDialog:
            // A question the GUI would put to the user. -1 is "no answer", which is what libmmbd
            // gives; the engine then takes its default, and the message log says what was asked.
            emit(.message(Message(code: Int(frame.args[0]), flags: frame.args[1], text: "Engine asked: " + frame.strings.joined(separator: " / "), format: "", parameters: [])))
            done = EngineProtocol.Frame(.clientDone, args: [UInt32(bitPattern: -1)], data: Data([0]))
        case .backSetTitleCollInfo:
            collectionHandle = frame.handle(at: 0)
            expectedTitles = Int(frame.args[2])
            titleHandles = [:]
            trackHandles = [:]
            chapterHandles = [:]
        case .backSetTitleInfo:
            let title = Int(frame.args[0])
            titleHandles[title] = frame.handle(at: 1)
            trackHandles[title] = [:]
            chapterHandles[title] = [:]
        case .backSetTrackInfo:
            trackHandles[Int(frame.args[0]), default: [:]][Int(frame.args[1])] = frame.handle(at: 2)
        case .backSetChapterInfo:
            chapterHandles[Int(frame.args[0]), default: [:]][Int(frame.args[1])] = frame.handle(at: 2)
        default:
            done = EngineProtocol.Frame(.clientDone, args: [0])
        }
        return done
    }

    /// Run a call that starts a background job, and return only when that job has finished.
    ///
    /// The engine runs disc opens, scans and rips as jobs, reporting progress and results through
    /// callbacks and bracketing each with enter/leave job mode. A job may finish inside the
    /// triggering call's own callback loop, or start a moment after it returns; watching `inJob`
    /// right after the call races on the second case and returns before any result arrives, which
    /// is how a disc could open with an empty title list. Waiting for the completion counter to
    /// advance past what it was before the call covers both. `libmmbd`'s `WaitJob` polls `OnIdle`
    /// the same way; the counter is what makes it reliable here.
    @discardableResult
    func runJob(_ trigger: () async throws -> EngineProtocol.Frame) async throws -> EngineProtocol.Frame {
        let baseline = jobsCompleted
        let result = try await trigger()
        var pumps = 0
        while jobsCompleted == baseline {
            _ = try await call(.callOnIdle)
            if jobsCompleted != baseline { break }
            pumps += 1
            // ~ half an hour of 25 ms polls, so a job that never signals completion eventually
            // gives up rather than hanging the caller forever.
            if pumps > 72000 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        _ = try await call(.callOnIdle)
        return result
    }

    private func emit(_ kind: Event.Kind) {
        eventHandler?(Event(kind: kind))
    }

    private func emitProgress() async {
        let current = currentTitleCode == 0 ? nil : ProgressTitle(code: Int(currentTitleCode), id: 0, name: await messageText(currentTitleCode))
        let total = totalTitleCode == 0 ? nil : ProgressTitle(code: Int(totalTitleCode), id: 0, name: await messageText(totalTitleCode))
        emit(.progress(RipProgress(current: current, total: total, value: ProgressValue(current: currentBar, total: totalBar, maximum: EngineProtocol.progressMaximum))))
    }
}

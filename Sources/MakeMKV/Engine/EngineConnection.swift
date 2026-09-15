// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation

/// A running `makemkvcon guiserver` and the two pipes to it, with one blocking transaction at a
/// time on a private thread.
///
/// The spawn contract is `ApSpawnApp` in `api_posix.cpp`: `makemkvcon guiserver A0001+std` with
/// the client's pipes on the engine's stdin and stdout. The engine answers `A0001:std$` on stdout,
/// then the stdio transport's own handshake, a `0xaa` byte from the engine answered by `0xbb`
/// from the client, after which every exchange is one frame each way.
final class EngineConnection: @unchecked Sendable {
    enum Failure: Error {
        case launchFailed(Error)
        case handshakeTimedOut
        case abiMismatch(engine: String, expected: String)
        case connectionLost
        case readTimedOut
    }

    private let process = Process()
    private let toEngine = Pipe()
    private let fromEngine = Pipe()
    private let stderrPipe = Pipe()
    private let queue = DispatchQueue(label: "makemkvkit.engine", qos: .userInitiated)
    /// How long to wait for the engine to say anything. The GUI allows 29 seconds per read; a
    /// disc open on a slow drive is quiet for longer than that here, so this is generous.
    private let readTimeout: TimeInterval

    private var readFD: Int32 { fromEngine.fileHandleForReading.fileDescriptor }
    private var writeFD: Int32 { toEngine.fileHandleForWriting.fileDescriptor }

    init(executable: URL, readTimeout: TimeInterval = 600) {
        self.readTimeout = readTimeout
        process.executableURL = executable
        process.arguments = ["guiserver", "\(EngineProtocol.abiVersion)+std"]
        process.standardInput = toEngine
        process.standardOutput = fromEngine
        process.standardError = stderrPipe
    }

    var isRunning: Bool { process.isRunning }
    /// The engine's exit status once it has exited, for diagnosing a lost connection.
    var terminationStatus: Int32? { process.isRunning ? nil : process.terminationStatus }
    /// Whatever the engine wrote to stderr, which is not protocol but is evidence.
    private(set) var stderrText = ""
    private let stderrLock = NSLock()

    /// Launch and complete both handshakes.
    func start() async throws {
        try await onQueue {
            do {
                try self.process.run()
            } catch {
                throw Failure.launchFailed(error)
            }
            // Drain stderr so the engine never blocks on it; nothing there is protocol.
            self.stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let text = String(decoding: handle.availableData, as: UTF8.self)
                guard let self, !text.isEmpty else { return }
                self.stderrLock.lock()
                self.stderrText += text
                self.stderrLock.unlock()
            }
            // "A0001:std$"
            var response = Data()
            while true {
                let byte = try self.readByte()
                if byte == UInt8(ascii: "$") { break }
                response.append(byte)
                if response.count > 512 { throw Failure.handshakeTimedOut }
            }
            let text = String(decoding: response, as: UTF8.self)
            let engineABI = text.split(separator: ":", maxSplits: 1).first.map(String.init) ?? text
            guard engineABI == EngineProtocol.abiVersion else {
                throw Failure.abiMismatch(engine: engineABI, expected: EngineProtocol.abiVersion)
            }
            // Transport handshake.
            while try self.readByte() != 0xaa {}
            try self.write(Data([0xbb]))
        }
    }

    /// Send one frame and read the engine's next frame. The caller drives the callback loop.
    func transact(_ frame: EngineProtocol.Frame) async throws -> EngineProtocol.Frame {
        try await onQueue {
            try self.write(frame.encoded)
            return try self.readFrame()
        }
    }

    func terminate() {
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Blocking I/O, on the queue

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private func readFrame() throws -> EngineProtocol.Frame {
        let first = try readByte()
        if first >= 0xf0 {
            return EngineProtocol.Frame(EngineProtocol.Command(rawValue: first - 0xf0) ?? .unknown)
        }
        var headerBytes = Data([first])
        headerBytes.append(try read(count: 3))
        let header = headerBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        let command = EngineProtocol.Command(rawValue: UInt8(header >> 24)) ?? .unknown
        let argCount = Int((header >> 16) & 0xff)
        let dataSize = Int(header & 0xffff)
        let rest = try read(count: argCount * 4 + dataSize)
        var args: [UInt32] = []
        args.reserveCapacity(argCount)
        for i in 0..<argCount {
            args.append(rest.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self) }.littleEndian)
        }
        return EngineProtocol.Frame(command, args: args, data: rest.suffix(dataSize))
    }

    private func readByte() throws -> UInt8 {
        try read(count: 1)[0]
    }

    private func read(count: Int) throws -> Data {
        var out = Data(capacity: count)
        var buffer = [UInt8](repeating: 0, count: min(count, 65536))
        while out.count < count {
            var pfd = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32(readTimeout * 1000))
            if ready == 0 { throw Failure.readTimedOut }
            if ready < 0 { throw Failure.connectionLost }
            let n = buffer.withUnsafeMutableBytes { Darwin.read(readFD, $0.baseAddress, min(count - out.count, $0.count)) }
            if n <= 0 { throw Failure.connectionLost }
            out.append(contentsOf: buffer[0..<n])
        }
        return out
    }

    private func write(_ data: Data) throws {
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { Darwin.write(writeFD, $0.baseAddress! + offset, data.count - offset) }
            if n <= 0 { throw Failure.connectionLost }
            offset += n
        }
    }
}
